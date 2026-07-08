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

    public static func ensureServiceRunning() -> Bool {
        if isServiceRunning() {
            return true
        }
        return spawnService()
    }

    public static func isServiceRunning() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        let sockfd = socket(AF_INET, SOCK_STREAM, 0)
        if sockfd < 0 {
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
        return result == 0
        #endif
    }

    public static func spawnService() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        guard let appBundleURL = hostAppBundleURL() else {
            return false
        }

        let managerURL = appBundleURL.appendingPathComponent("trollvncmanager", isDirectory: false)
        let managerPath = managerURL.path
        guard FileManager.default.isExecutableFile(atPath: managerPath) else {
            return false
        }

        var spawnAttrs: posix_spawnattr_t?
        guard posix_spawnattr_init(&spawnAttrs) == 0 else {
            return false
        }
        defer { posix_spawnattr_destroy(&spawnAttrs) }

        _ = posix_spawnattr_set_persona_np(&spawnAttrs, 99, posixSpawnPersonaFlagsOverride)
        _ = posix_spawnattr_set_persona_uid_np(&spawnAttrs, 0)
        _ = posix_spawnattr_set_persona_gid_np(&spawnAttrs, 0)

        let oldDirectoryPath = FileManager.default.currentDirectoryPath
        _ = FileManager.default.changeCurrentDirectoryPath(appBundleURL.path)
        defer { _ = FileManager.default.changeCurrentDirectoryPath(oldDirectoryPath) }

        let argvStrings = [managerPath]
        let envStrings = taskEnvironment().compactMap { key, value -> String? in
            let item = "\(key)=\(value)"
            return item.utf8.contains(0) ? nil : item
        }

        return withCStringArray(argvStrings) { argv in
            withCStringArray(envStrings) { envp in
                var pid = pid_t()
                let result = managerPath.withCString { path in
                    posix_spawn(&pid, path, nil, &spawnAttrs, argv, envp)
                }
                if result != 0 {
                    return false
                }

                var status: Int32 = 0
                _ = waitpid(pid, &status, WNOHANG)
                return true
            }
        }
        #endif
    }

    public static func managerExecutablePath() -> String? {
        hostAppBundleURL()?.appendingPathComponent("trollvncmanager", isDirectory: false).path
    }

    private static func hostAppBundleURL() -> URL? {
        var url = Bundle.main.bundleURL

        while !url.path.isEmpty && url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }

        return Bundle.main.path(forResource: "trollvncmanager", ofType: nil).map {
            URL(fileURLWithPath: $0).deletingLastPathComponent()
        }
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
}
