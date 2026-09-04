import Foundation
import Security

/// Credential storage.
///
/// The refresh token goes in the Keychain because it is the long-lived secret —
/// 30 days of account access if it leaks. The access token deliberately stays in
/// memory only: it expires in 15 minutes, so persisting it buys nothing and just
/// widens the attack surface.
@Observable
final class TokenStore {

    private(set) var accessToken: String?
    private(set) var currentUser: UserProfileDTO?

    private let service = "com.abhay.animaldex"
    private let refreshAccount = "refresh_token"
    private let userDefaultsKey = "animaldex.currentUser"

    var refreshToken: String? {
        get { readKeychain(refreshAccount) }
        set {
            if let newValue { writeKeychain(refreshAccount, newValue) }
            else { deleteKeychain(refreshAccount) }
        }
    }

    var isSignedIn: Bool { refreshToken != nil }

    init() {
        // The cached profile is a convenience so the UI can render a trainer card
        // before the first network call returns. It is not authoritative.
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            currentUser = try? JSONDecoder().decode(UserProfileDTO.self, from: data)
        }
    }

    func store(_ pair: TokenPairDTO) {
        accessToken = pair.accessToken
        refreshToken = pair.refreshToken
        currentUser = pair.user
        if let data = try? JSONEncoder().encode(pair.user) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Keychain

    private func readKeychain(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKeychain(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Delete-then-add rather than SecItemUpdate: it is one code path instead
        // of two, and there is nothing to preserve on the existing item.
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        // ThisDeviceOnly so the token never rides an iCloud Keychain backup to
        // another device.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func deleteKeychain(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
