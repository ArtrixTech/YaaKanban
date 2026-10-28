import AppKit
import SwiftUI

@MainActor func render(_ view: some View, size: NSSize, dark: Bool, to path: String) {
    let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    w.contentView = host
    w.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    w.orderOut(nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let size = NSSize(width: 1040, height: 560)
MainActor.assumeIsolated {
    render(BoardA().background(Color(white: 0.93)), size: size, dark: false, to: "/tmp/yaak-ds/dir-A.png")
    render(BoardB().background(Color(white: 0.97)), size: size, dark: false, to: "/tmp/yaak-ds/dir-B.png")
    render(BoardC().background(Color.black), size: size, dark: true, to: "/tmp/yaak-ds/dir-C.png")
    render(BoardD().background(Color.black), size: size, dark: true, to: "/tmp/yaak-ds/dir-D.png")
}
