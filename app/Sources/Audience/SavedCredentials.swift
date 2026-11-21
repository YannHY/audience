import Foundation
import Security

/// The Audience account: its e-mail in the preferences, its password in the login keychain.
/// Keychain calls can wait for the user to answer a system prompt, so callers run them off the main actor.
enum SavedCredentials {
    private static let service = "fr.audience.native.account"
    private static let emailKey = "accountEmail"

    static var email: String { UserDefaults.standard.string(forKey: emailKey) ?? "" }

    static func password(for email: String) -> String? {
        var query = baseQuery(account: email)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(email: String, password: String) {
        UserDefaults.standard.set(email, forKey: emailKey)
        guard Self.password(for: email) != password else { return }
        // A single account is kept: signing in with another address replaces the previous one.
        forgetPassword()
        var item = baseQuery(account: email)
        item[kSecAttrLabel as String] = "Audience"
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Keeps the e-mail so the sign-in form stays filled in.
    static func forgetPassword() {
        SecItemDelete(baseQuery(account: nil) as CFDictionary)
    }

    private static func baseQuery(account: String?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }
}
