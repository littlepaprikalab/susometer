import Flutter
// Stand-ins for the Objective-C GeneratedPluginRegistrant and the Keychain store
// (KeychainStore.swift uses Darwin-only CF bridging; it is syntax-checked only).
final class GeneratedPluginRegistrant {
  static func register(with registry: FlutterPluginRegistry) {}
}
enum KeychainStore {
  static func read() -> String? { nil }
  @discardableResult static func save(_ value: String) -> Int32 { 0 }
  @discardableResult static func delete() -> Int32 { 0 }
  static func hasKey() -> Bool { false }
  static func hint() -> String? { nil }
  static func prepareAtLaunch() {}
}
let errSecSuccess: Int32 = 0
