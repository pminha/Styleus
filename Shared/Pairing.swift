import Foundation
import Security

struct PairingCredential: Codable, Equatable {
    var id: UUID
    var secret: Data
    var serviceName: String { "Styleus-" + id.uuidString }
    var code: String { "styleus:1:\(id.uuidString):\(secret.base64EncodedString())" }

    static func create() throws -> PairingCredential {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ProtocolError.randomFailure
        }
        return PairingCredential(id: UUID(), secret: Data(bytes))
    }

    static func parse(_ text: String) throws -> PairingCredential {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == "styleus", fields[1] == "1",
              let id = UUID(uuidString: String(fields[2])),
              let secret = Data(base64Encoded: String(fields[3])), secret.count == 32 else {
            throw ProtocolError.invalidPairing
        }
        return PairingCredential(id: id, secret: secret)
    }
}

enum PairingStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "Styleus") + ".pairing",
         kSecAttrAccount as String: "approved-peer"]
    }

    static func load() throws -> PairingCredential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ProtocolError.keychain(status) }
        let value = try JSONDecoder().decode(PairingCredential.self, from: data)
        guard value.secret.count == 32 else { throw ProtocolError.invalidPairing }
        return value
    }

    static func save(_ credential: PairingCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw ProtocolError.keychain(update) }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        entry[kSecAttrSynchronizable as String] = false
        let result = SecItemAdd(entry as CFDictionary, nil)
        guard result == errSecSuccess else { throw ProtocolError.keychain(result) }
    }

    static func forget() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw ProtocolError.keychain(result) }
    }
}
