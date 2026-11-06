import Foundation
import Security

/// Stores the Presage API key in the iOS Keychain (SPEC.md §6, §9).
///
/// The key is written once from Dart on save and read only here in Swift.
/// It never travels back to Dart; `hint()` returns just the last 4 characters.
enum KeychainStore {
  private static let service = "com.littlepaprikalab.susometer.presage"
  private static let account = "presage-api-key"

  /// UserDefaults flag used only to detect a fresh install. iOS keeps Keychain
  /// items after an app is deleted, so without this the key would survive a
  /// reinstall. UserDefaults is wiped on delete, which makes "the key is removed
  /// when the app is deleted" (SPEC.md §8) true. No game data is stored here.
  private static let installMarkerKey = "sus.installMarker.v1"

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func read() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    let value = String(data: data, encoding: .utf8)
    return (value?.isEmpty ?? true) ? nil : value
  }

  @discardableResult
  static func save(_ value: String) -> OSStatus {
    delete()
    var attributes = baseQuery
    attributes[kSecValueData as String] = Data(value.utf8)
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil)
  }

  @discardableResult
  static func delete() -> OSStatus {
    SecItemDelete(baseQuery as CFDictionary)
  }

  static func hasKey() -> Bool { read() != nil }

  /// "••••1a2b": only the last 4 characters, for display after saving.
  static func hint() -> String? {
    guard let key = read() else { return nil }
    return "••••" + String(key.suffix(4))
  }

  /// Call once at launch, before anything reads the key.
  static func prepareAtLaunch() {
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: installMarkerKey) {
      delete()
      defaults.set(true, forKey: installMarkerKey)
    }
    #if DEBUG
      seedFromDebugSecretsIfNeeded()
    #endif
  }

  #if DEBUG
    /// Debug builds only: copy PRESAGE_API_KEY from the gitignored
    /// Secrets.xcconfig (exposed via Info.plist) into the Keychain once,
    /// if the Keychain is empty. Release builds never compile this.
    private static func seedFromDebugSecretsIfNeeded() {
      guard read() == nil else { return }
      guard
        let raw = Bundle.main.object(forInfoDictionaryKey: "PresageApiKey") as? String
      else { return }
      let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty, !key.hasPrefix("$("), key != "paste-your-presage-api-key-here"
      else { return }
      save(key)
    }
  #endif
}
