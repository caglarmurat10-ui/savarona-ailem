import Foundation
import Security

enum KeychainCredentialStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.savarona.ailem"
    private static let account = "savarona.deviceToken"
    static func saveDeviceToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        SecItemDelete(query as CFDictionary)
        var add=query; add[kSecValueData as String]=data; add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary,nil)==errSecSuccess
    }
    static func readDeviceToken() -> String? {
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var item:CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary,&item)==errSecSuccess, let data=item as? Data else{return nil}
        return String(data:data,encoding:.utf8)
    }
    static func clear(){ let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]; SecItemDelete(q as CFDictionary) }
}
