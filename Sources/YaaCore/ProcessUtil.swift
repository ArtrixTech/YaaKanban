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

    /// The controlling terminal of `pid` (`/dev/ttys003`), if it has one.
    public static func tty(of pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard pid > 0, sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, let name = devname(dev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// Whether the terminal `tty` (`/dev/ttys003`) is back at its shell's prompt: the foreground
    /// process group is the session leader's own and that leader is a shell. False while any
    /// command runs in the foreground (an agent, tmux, ssh) or when the tty has no processes.
    public static func shellAtPrompt(tty: String) -> Bool {
        var st = stat()
        guard stat(tty, &st) == 0, (st.st_mode & S_IFMT) == S_IFCHR else { return false }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(bitPattern: UInt32(st.st_rdev))]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return false }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 4)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return false }
        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride).contains { p in
            let pid = p.kp_proc.p_pid
            // A session leader's process group is its own pid.
            guard pid > 0, p.kp_eproc.e_pgid == pid, p.kp_eproc.e_tpgid == pid, (p.kp_eproc.e_flag & EPROC_SLEADER) != 0
            else { return false }
            return name(of: pid).map { shells.contains($0.hasPrefix("-") ? String($0.dropFirst()) : $0) } ?? false
        }
    }

    /// Parents of `pid`, nearest first, up to (not including) launchd.
    public static func ancestors(of pid: Int32, limit: Int = 16) -> [Int32] {
        var out: [Int32] = []
        var cur = pid
        while out.count < limit, let p = parent(of: cur), p > 1, p != cur {
            out.append(p)
            cur = p
        }
        return out
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
