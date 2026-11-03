import Darwin
import Foundation
import PaceBarCore

/// Reads Claude Code's per-chat state files, `~/.claude/sessions/<pid>.json`, for the Claude Code
/// Chats widget. The only code that touches `~/.claude`.
///
/// Read-only. It opens nothing but `<pid>.json` files in that one folder, never the `.key` files
/// beside them, transcripts, or anything else under `~/.claude`. Only runs while the setting is on.
actor ChatSessionReader {
    private let directory: URL
    /// The last decode of each file by name, so an unchanged file isn't read again.
    private var cache: [String: (modified: Date, file: SessionFile?)] = [:]

    init(home: String = NSHomeDirectory()) {
        directory = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    /// The files of chats whose process is still running.
    func scan() -> [SessionFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var seen = Set<String>()
        var live: [SessionFile] = []
        for name in names where SessionFile.isSessionFileName(name) {
            seen.insert(name)
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= SessionFile.maxFileSize,
                  let modified = values.contentModificationDate
            else { continue }

            let file: SessionFile?
            if let cached = cache[name], cached.modified == modified {
                file = cached.file
            } else {
                file = (try? Data(contentsOf: url)).flatMap(SessionFile.decode)
                cache[name] = (modified, file)
            }
            // The file must be the one its name says, for a process that's still running.
            guard let file, let pid = file.pid, name == "\(pid).json",
                  Self.isRunning(pid: pid, procStart: file.procStart) else { continue }
            live.append(file)
        }
        cache = cache.filter { name, _ in seen.contains(name) }
        return live
    }

    /// Whether `pid` is running and started when the file says, which rules out a PID the system
    /// has since given to another process. Asks the kernel for the process's start time; it
    /// sends no signal and reads nothing else about the process.
    static func isRunning(pid: Int32, procStart: String?) -> Bool {
        guard pid > 0 else { return false }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0,
              info.kp_proc.p_pid == pid else { return false }
        let started = info.kp_proc.p_un.__p_starttime
        let startTime = Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
        return ProcessIdentity.matches(procStart: procStart, startTime: startTime)
    }
}
