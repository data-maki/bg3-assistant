import Foundation
import StoreKit

struct AppTransactionAuthenticator {
    func signedAppTransaction(refresh: Bool = false) async throws -> String {
        let result = try await (refresh ? AppTransaction.refresh() : AppTransaction.shared)
        switch result {
        case .verified:
            return result.jwsRepresentation
        case .unverified(_, let verificationError):
            throw AppTransactionAuthenticationError.unverified(String(describing: verificationError))
        }
    }
}

enum AppTransactionAuthenticationError: LocalizedError {
    case unverified(String)

    var errorDescription: String? {
        switch self {
        case .unverified:
            "TestFlight could not verify this installation with the App Store."
        }
    }
}
