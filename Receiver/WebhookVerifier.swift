import CryptoKit
import Foundation

enum SignatureVerdict {
    case valid
    case invalid
    case notConfigured
    case missing
}

enum WebhookVerifier {
    static func verify(body: Data, headers: [String: String], secret: String?) -> SignatureVerdict {
        guard let secret, !secret.isEmpty else { return .notConfigured }
        guard let provided = headers["x-hub-signature-256"] else { return .missing }

        let key = SymmetricKey(data: Data(secret.utf8))
        let digest = HMAC<SHA256>.authenticationCode(for: body, using: key)
        let expected = "sha256=" + digest.map { String(format: "%02x", $0) }.joined()

        guard let providedBytes = provided.data(using: .utf8),
              let expectedBytes = expected.data(using: .utf8) else {
            return .invalid
        }

        guard providedBytes.count == expectedBytes.count else { return .invalid }
        var difference: UInt8 = 0
        for (a, b) in zip(providedBytes, expectedBytes) {
            difference |= a ^ b
        }
        return difference == 0 ? .valid : .invalid
    }
}
