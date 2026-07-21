import Foundation
import Security

enum CredentialStore {
    private static let legacyService = "com.datamaki.BG3HonorAssistant.openrouter"
    private static let account = "api-key"

    /// App Store/TestFlight builds are sandboxed while direct builds are not.
    /// Separate services keep their different signing requirements from
    /// claiming the same legacy Keychain item and rejecting each other later.
    static func credentialService(isSandboxed: Bool) -> String {
        "\(legacyService).\(isSandboxed ? "appstore" : "direct")"
    }

    private static var service: String {
        credentialService(
            isSandboxed: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        )
    }

    static func openRouterKey() throws -> String? {
        do {
            if let value = try value(for: service) { return value }
            return try value(for: legacyService)
        } catch CredentialStoreError.keychain(errSecAuthFailed) {
            // A legacy item may belong to the other signing channel. Treat it
            // as unavailable so the user can save a replacement in this one.
            return nil
        }
    }

    private static func value(for service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.keychain(status)
        }
        return value
    }

    static func saveOpenRouterKey(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            try deleteOpenRouterKey()
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychain(updateStatus)
        }
    }

    static func deleteOpenRouterKey() throws {
        try delete(service: service, ignoringAuthenticationFailure: false)
        try delete(service: legacyService, ignoringAuthenticationFailure: true)
    }

    private static func delete(service: String, ignoringAuthenticationFailure: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if ignoringAuthenticationFailure, status == errSecAuthFailed { return }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        case .verificationFailed:
            "The API key could not be verified after saving. Please try again."
        }
    }
}
