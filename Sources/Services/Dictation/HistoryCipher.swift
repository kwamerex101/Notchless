import Foundation
import CryptoKit
import Security

/// AES-GCM encryption for the dictation history file. The symmetric key lives in
/// the login Keychain, created on first use.
enum HistoryCipher {
    private static let keychainAccount = "com.rexdanquah.Notchless.historyKey"

    static func encrypt(_ data: Data) -> Data? {
        guard let key = loadOrCreateKey(),
              let sealed = try? AES.GCM.seal(data, using: key) else { return nil }
        return sealed.combined
    }

    static func decrypt(_ data: Data) -> Data? {
        guard let key = loadOrCreateKey(),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return plain
    }

    private static func loadOrCreateKey() -> SymmetricKey? {
        if let existing = readKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        storeKey(key)
        return key
    }

    private static func readKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func storeKey(_ key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
