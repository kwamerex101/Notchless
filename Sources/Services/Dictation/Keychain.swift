import Foundation
import Security

/// Tiny wrapper for storing string secrets (e.g. the Anthropic API key) in the
/// login Keychain, keyed by account name.
enum Keychain {
    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}
