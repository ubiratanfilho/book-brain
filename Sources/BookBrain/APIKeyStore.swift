import BookBrainCore
import Foundation
import Security

enum APIKeyStore {
  private static func query(_ provider: APIProvider) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "BookBrain.ProviderAPIKey",
      kSecAttrAccount as String: provider.rawValue,
    ]
  }

  static func key(for provider: APIProvider) throws -> String {
    var request = query(provider)
    request[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound {
      throw BookBrainError.message("Add your \(provider.name) API key in API settings.")
    }
    try check(status)
    guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
      throw BookBrainError.message("Replace the saved API key in API settings.")
    }
    return key
  }

  static func save(_ key: String, for provider: APIProvider) throws {
    let request = query(provider)
    let data = [kSecValueData as String: Data(key.utf8)]
    let status = SecItemUpdate(request as CFDictionary, data as CFDictionary)
    if status == errSecItemNotFound {
      var item = request.merging(data) { _, value in value }
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      try check(SecItemAdd(item as CFDictionary, nil))
    } else {
      try check(status)
    }
  }

  static func remove(for provider: APIProvider) throws {
    let status = SecItemDelete(query(provider) as CFDictionary)
    if status != errSecItemNotFound { try check(status) }
  }

  private static func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      throw BookBrainError.message("Keychain access failed (\(status)).")
    }
  }
}
