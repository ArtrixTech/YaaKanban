import Darwin
import Foundation

public enum ProcessUtil {
    public static func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    public static func parent(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbi_ppid)
    }

    public static func name(of pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env"]

    /// The agent process that ran this hook: the first ancestor that is not a shell.
    public static func hookOwner(startingAt pid: Int32 = getppid()) -> Int32? {
        var cur = pid
        for _ in 0..<6 {
            guard let n = name(of: cur) else { return nil }
            if !shells.contains(n) { return cur }
            guard let p = parent(of: cur), p > 1 else { return nil }
            cur = p
        }
        return nil
    }
}

/// Single-quotes a string for POSIX sh.
public func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
