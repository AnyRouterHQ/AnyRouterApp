import CryptoKit
import Foundation
import Security

enum PKCE {
    struct Failure: Error {}

    /// 32 random bytes encode to a 43-character base64url verifier (RFC 7636 allows 43 to 128).
    static func makeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw Failure()
        }
        return base64URL(Data(bytes))
    }

    /// S256: base64url(SHA-256(verifier)).
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
