/*
 This file is part of TrollVNC
 Copyright (c) 2025 82Flex <82flex@gmail.com> and contributors

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License version 2
 as published by the Free Software Foundation.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see <https://www.gnu.org/licenses/>.
*/

import Darwin
import Foundation

@_silgen_name("posix_spawnattr_set_persona_np")
private func posix_spawnattr_set_persona_np(
    _ attr: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ personaID: uid_t,
    _ flags: UInt32
) -> Int32

@_silgen_name("posix_spawnattr_set_persona_uid_np")
private func posix_spawnattr_set_persona_uid_np(
    _ attr: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ personaID: uid_t
) -> Int32

@_silgen_name("posix_spawnattr_set_persona_gid_np")
private func posix_spawnattr_set_persona_gid_np(
    _ attr: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ personaID: uid_t
) -> Int32

private let posixSpawnPersonaFlagsOverride = UInt32(1)

@objcMembers
public final class TVNCServiceLauncher: NSObject {
    private static let alivePort: UInt16 = 46751
    private static let logDirectoryPath = "/var/mobile/Media/TrollVNC"
    private static let logFilePath = "/var/mobile/Media/TrollVNC/widget-launch.log"
    private static let logLock = NSLock()
    private static let maxLogFileSize: UInt64 = 512 * 1024

    public static func ensureServiceRunning() -> Bool {
        log("ensureServiceRunning begin")
        if isServiceRunning() {
            log("ensureServiceRunning already running")
            return true
        }
        let spawned = spawnService()
        log("ensureServiceRunning spawn result=\(spawned)")
        return spawned
    }

    public static func isServiceRunning() -> Bool {
        #if targetEnvironment(simulator)
        log("isServiceRunning simulator -> true")
        return true
        #else
        let sockfd = socket(AF_INET, SOCK_STREAM, 0)
        if sockfd < 0 {
            let socketErrno = errno
            log("isServiceRunning socket failed errno=\(socketErrno) \(errnoDescription(socketErrno))")
            return false
        }
        defer { close(sockfd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(alivePort).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sockfd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let running = result == 0
        if running {
            log("isServiceRunning connect 127.0.0.1:\(alivePort) -> true")
        } else {
            let connectErrno = errno
            log("isServiceRunning connect 127.0.0.1:\(alivePort) -> false errno=\(connectErrno) \(errnoDescription(connectErrno))")
        }
        return running
        #endif
    }

    public static func spawnService() -> Bool {
        #if targetEnvironment(simulator)
        log("spawnService simulator -> true")
        return true
        #else
        log("spawnService begin uid=\(getuid()) euid=\(geteuid()) gid=\(getgid()) egid=\(getegid()) bundle=\(Bundle.main.bundleIdentifier ?? "nil") bundleURL=\(Bundle.main.bundleURL.path)")
        guard let appBundleURL = hostAppBundleURL() else {
            log("spawnService failed: host app bundle not found")
            return false
        }
        log("spawnService hostAppBundleURL=\(appBundleURL.path)")

        let managerURL = appBundleURL.appendingPathComponent("trollvncmanager", isDirectory: false)
        let managerPath = managerURL.path
        guard FileManager.default.isExecutableFile(atPath: managerPath) else {
            let exists = FileManager.default.fileExists(atPath: managerPath)
            log("spawnService failed: manager not executable exists=\(exists) path=\(managerPath)")
            return false
        }
        log("spawnService manager executable path=\(managerPath)")

        var spawnAttrs: posix_spawnattr_t?
        let attrInitResult = posix_spawnattr_init(&spawnAttrs)
        guard attrInitResult == 0 else {
            log("spawnService failed: posix_spawnattr_init result=\(attrInitResult) \(errnoDescription(attrInitResult))")
            return false
        }
        defer { posix_spawnattr_destroy(&spawnAttrs) }

        let personaResult = posix_spawnattr_set_persona_np(&spawnAttrs, 99, posixSpawnPersonaFlagsOverride)
        let personaUIDResult = posix_spawnattr_set_persona_uid_np(&spawnAttrs, 0)
        let personaGIDResult = posix_spawnattr_set_persona_gid_np(&spawnAttrs, 0)
        log("spawnService persona results persona=\(personaResult) uid=\(personaUIDResult) gid=\(personaGIDResult)")

        let oldDirectoryPath = FileManager.default.currentDirectoryPath
        let changedDirectory = FileManager.default.changeCurrentDirectoryPath(appBundleURL.path)
        log("spawnService chdir \(appBundleURL.path) result=\(changedDirectory)")
        defer { _ = FileManager.default.changeCurrentDirectoryPath(oldDirectoryPath) }

        let argvStrings = [managerPath]
        let envStrings = taskEnvironment().compactMap { key, value -> String? in
            let item = "\(key)=\(value)"
            return item.utf8.contains(0) ? nil : item
        }
        log("spawnService argv=\(argvStrings) envCount=\(envStrings.count)")

        return withCStringArray(argvStrings) { argv in
            withCStringArray(envStrings) { envp in
                var pid = pid_t()
                let result = managerPath.withCString { path in
                    posix_spawn(&pid, path, nil, &spawnAttrs, argv, envp)
                }
                if result != 0 {
                    log("spawnService posix_spawn failed result=\(result) \(errnoDescription(result)) pid=\(pid)")
                    return false
                }

                var status: Int32 = 0
                let waitResult = waitpid(pid, &status, WNOHANG)
                log("spawnService posix_spawn success pid=\(pid) waitpid=\(waitResult) status=\(status)")
                return true
            }
        }
        #endif
    }

    public static func managerExecutablePath() -> String? {
        hostAppBundleURL()?.appendingPathComponent("trollvncmanager", isDirectory: false).path
    }

    public static func debugLogPath() -> String {
        logFilePath
    }

    public static func log(_ message: String) {
        logLock.lock()
        defer { logLock.unlock() }

        let manager = FileManager.default
        do {
            try manager.createDirectory(
                atPath: logDirectoryPath,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.none]
            )

            if let attributes = try? manager.attributesOfItem(atPath: logFilePath),
               let fileSize = attributes[.size] as? NSNumber,
               fileSize.uint64Value > maxLogFileSize {
                try? manager.removeItem(atPath: logFilePath)
            }

            if !manager.fileExists(atPath: logFilePath) {
                _ = manager.createFile(atPath: logFilePath, contents: nil, attributes: [.protectionKey: FileProtectionType.none])
            } else {
                try? manager.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: logFilePath)
            }

            let line = "\(logTimestamp()) [\(ProcessInfo.processInfo.processName):\(getpid())] \(message)\n"
            guard let data = line.data(using: .utf8),
                  let handle = FileHandle(forWritingAtPath: logFilePath) else {
                return
            }
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private static func hostAppBundleURL() -> URL? {
        var url = Bundle.main.bundleURL
        log("hostAppBundleURL start=\(url.path)")

        while !url.path.isEmpty && url.path != "/" {
            if url.pathExtension == "app" {
                log("hostAppBundleURL found app=\(url.path)")
                return url
            }
            log("hostAppBundleURL walk url=\(url.path)")
            url.deleteLastPathComponent()
        }

        let fallback = Bundle.main.path(forResource: "trollvncmanager", ofType: nil).map {
            URL(fileURLWithPath: $0).deletingLastPathComponent()
        }
        log("hostAppBundleURL fallback=\(fallback?.path ?? "nil")")
        return fallback
    }

    private static func taskEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let languageCode = Locale.preferredLanguages.first {
            env["TVNC_LANGUAGE_CODE"] = languageCode
        }
        return env
    }

    private static func withCStringArray<R>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R
    ) -> R {
        let cStrings = strings.map { strdup($0) }
        defer {
            for ptr in cStrings {
                if let ptr {
                    free(ptr)
                }
            }
        }

        var pointers = cStrings
        pointers.append(nil)
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }

    private static func errnoDescription(_ code: Int32) -> String {
        String(cString: strerror(code))
    }

    private static func logTimestamp() -> String {
        var timeval = timeval()
        gettimeofday(&timeval, nil)

        var localTime = time_t(timeval.tv_sec)
        var tmValue = tm()
        localtime_r(&localTime, &tmValue)

        var buffer = [CChar](repeating: 0, count: 32)
        strftime(&buffer, buffer.count, "%Y-%m-%d %H:%M:%S", &tmValue)
        let seconds = String(cString: buffer)
        return String(format: "%@.%03d", seconds, Int(timeval.tv_usec / 1000))
    }
}
