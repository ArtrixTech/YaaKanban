// Usage: swift dmg-background.swift <logo.svg> <out.png> <scale> [preview-light|preview-dark]
// Draws the DMG window background: the brand mark and name on top, a green arrow from the app
// (left) to Applications (right), and a chip under each icon so Finder's label stays readable
// whether it draws it white (dark mode) or black (light mode). No translatable text.
// A preview mode also draws the icons and labels, to check the layout without Finder.
// Layout (window content size, icon centres) must match scripts/dmg.sh.
import AppKit

let args = CommandLine.arguments
let logo = NSImage(contentsOf: URL(fileURLWithPath: args[1]))!
let scale = CGFloat(Double(args[3]) ?? 1)
let preview = args.count > 4 ? args[4] : nil
let size = CGSize(width: 640, height: 400)
let iconY: CGFloat = 210, appX: CGFloat = 170, appsX: CGFloat = 470, iconSize: CGFloat = 120
// Finder coordinates run from the top; AppKit's from the bottom.
func top(_ y: CGFloat) -> CGFloat { size.height - y }
func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                           pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Backdrop: soft light gradient with a faint green glow behind the arrow.
NSGradient(starting: rgb(0xFAFBFC), ending: rgb(0xE9ECF0))!.draw(in: NSRect(origin: .zero, size: size), angle: -90)
NSGradient(starting: rgb(0x10B981, 0.10), ending: rgb(0x10B981, 0))!
    .draw(fromCenter: NSPoint(x: size.width / 2, y: top(iconY)), radius: 0,
          toCenter: NSPoint(x: size.width / 2, y: top(iconY)), radius: 260, options: [])

// Brand: mark + name, centred.
let name = NSAttributedString(string: "YaaKanban", attributes: [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: rgb(0x16181D)])
let mark: CGFloat = 32, gap: CGFloat = 10
let groupW = mark + gap + name.size().width
let gx = (size.width - groupW) / 2
logo.draw(in: NSRect(x: gx, y: top(70) - mark / 2, width: mark, height: mark))
name.draw(at: NSPoint(x: gx + mark + gap, y: top(70) - name.size().height / 2))

// Arrow between the icons: green gradient shaft with a rounded head.
let y = top(iconY), x0 = appX + iconSize / 2 + 34, x1 = appsX - iconSize / 2 - 34
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: x0, y: y))
arrow.addLine(to: CGPoint(x: x1, y: y))
arrow.move(to: CGPoint(x: x1 - 16, y: y + 16))
arrow.addLine(to: CGPoint(x: x1, y: y))
arrow.addLine(to: CGPoint(x: x1 - 16, y: y - 16))
let ctx = NSGraphicsContext.current!.cgContext
ctx.saveGState()
ctx.addPath(arrow.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.clip()
NSGradient(starting: rgb(0x10B981), ending: rgb(0x4ADE80))!
    .draw(in: NSRect(x: x0 - 4, y: y - 20, width: x1 - x0 + 8, height: 40), angle: 0)
ctx.restoreGState()

// Label chips: mid grey, readable under both white and black text.
let labelY = iconY + iconSize / 2 + 18
for (x, w) in [(appX, CGFloat(104)), (appsX, CGFloat(104))] {
    rgb(0x8A9099, 0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: top(labelY) - 11, width: w, height: 22),
                 xRadius: 11, yRadius: 11).fill()
}

if let preview {
    let folder = NSWorkspace.shared.icon(forFile: "/Applications")
    let icon = NSImage(contentsOf: URL(fileURLWithPath: "build/YaaKanban.app/Contents/Resources/AppIcon.icns")) ?? logo
    icon.draw(in: NSRect(x: appX - iconSize / 2, y: y - iconSize / 2, width: iconSize, height: iconSize))
    folder.draw(in: NSRect(x: appsX - iconSize / 2, y: y - iconSize / 2, width: iconSize, height: iconSize))
    let color: NSColor = preview == "preview-dark" ? .white : .black
    for (x, s) in [(appX, "YaaKanban.app"), (appsX, "Applications")] {
        let t = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
        t.draw(at: NSPoint(x: x - t.size().width / 2, y: top(labelY) - t.size().height / 2))
    }
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
