import AppKit
import Darwin
import Foundation

@MainActor
final class SingleInstanceGuard {
    static let shared = SingleInstanceGuard()

    private var lockFileDescriptor: Int32 = -1
    private(set) var ownsLock = false

    private init() {}

    func acquire() -> Bool {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BG3HonorAssistant", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let lockPath = directory.appendingPathComponent("instance.lock").path
        lockFileDescriptor = Darwin.open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        // Do not make a filesystem failure prevent the assistant from launching.
        guard lockFileDescriptor >= 0 else {
            ownsLock = true
            return true
        }

        ownsLock = Darwin.lockf(lockFileDescriptor, F_TLOCK, 0) == 0
        return ownsLock
    }

    func activateExistingOwner() {
        otherAssistantApplications().first?.activate()
    }

    func terminateLegacyDuplicates() {
        for application in otherAssistantApplications() {
            if !application.terminate() {
                application.forceTerminate()
            }
        }
    }

    private func otherAssistantApplications() -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { application in
            guard application.processIdentifier != currentPID else { return false }
            return application.bundleIdentifier == "com.local.BG3HonorAssistant"
                || application.executableURL?.lastPathComponent == "BG3HonorAssistant"
        }
    }

    deinit {
        if lockFileDescriptor >= 0 {
            if ownsLock {
                Darwin.lockf(lockFileDescriptor, F_ULOCK, 0)
            }
            Darwin.close(lockFileDescriptor)
        }
    }
}
