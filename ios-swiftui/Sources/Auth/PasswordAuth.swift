import CryptoKit
import Foundation

enum PasswordAuth {
    private static let hashPrefix = "sha256$"
    private static let hashPrefixAlt = "sha256:"

    static func verify(stored: String, inputPlain: String) -> Bool {
        let s = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if isHashedFormat(s) {
            let expectedRaw: String
            if s.hasPrefix(hashPrefix) {
                expectedRaw = String(s.dropFirst(hashPrefix.count))
            } else if s.hasPrefix(hashPrefixAlt) {
                expectedRaw = String(s.dropFirst(hashPrefixAlt.count))
            } else {
                expectedRaw = extractSha256Hex(s) ?? s
            }
            let expectedHex = (extractSha256Hex(expectedRaw) ?? expectedRaw).lowercased()
            let actualHex = sha256Hex(inputPlain).lowercased()
            if timingSafeEqual(expectedHex, actualHex) { return true }
            let trimmed = inputPlain.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != inputPlain {
                let trimmedActual = sha256Hex(trimmed).lowercased()
                if timingSafeEqual(expectedHex, trimmedActual) { return true }
            }
            return false
        }
        return timingSafeEqual(s, inputPlain) || timingSafeEqual(s, inputPlain.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func isHashedFormat(_ stored: String) -> Bool {
        if stored.hasPrefix(hashPrefix), stored.count > hashPrefix.count + 32 { return true }
        if stored.hasPrefix(hashPrefixAlt), stored.count > hashPrefixAlt.count + 32 { return true }
        return extractSha256Hex(stored) != nil
    }

    private static func extractSha256Hex(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeSha256Hex(s) { return s }
        let pattern = try? NSRegularExpression(pattern: "([a-fA-F0-9]{64})")
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = pattern?.firstMatch(in: s, range: range),
              let r = Range(match.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private static func looksLikeSha256Hex(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 64 else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    private static func sha256Hex(_ plain: String) -> String {
        let data = Data(plain.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func timingSafeEqual(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        var out: UInt8 = 0
        for (x, y) in zip(a.utf8, b.utf8) { out |= x ^ y }
        return out == 0
    }
}
