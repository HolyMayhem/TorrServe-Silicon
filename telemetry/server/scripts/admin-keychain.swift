// Invoked only by admin-credentials.mjs. Stdout is captured in memory, never logged.
import Foundation
import Security
let service = "com.holymayhem.torrserve.telemetry.admin"
let account = "owner"
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service, kSecAttrAccount as String: account]
var result: CFTypeRef?
var readQuery = query
readQuery[kSecReturnData as String] = true
let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) {
    print(value)
} else if status == errSecItemNotFound && CommandLine.arguments.contains("--create-if-missing") {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { exit(1) }
    let value = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    var item = query
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrLabel as String] = "TorrServe Silicon — ключ аналитики"
    let stored = SecItemAdd(item as CFDictionary, nil)
    guard stored == errSecSuccess else { fputs("Keychain write failed: \(stored)\n", stderr); exit(1) }
    print(value)
} else {
    fputs("Keychain read failed: \(status)\n", stderr)
    exit(1)
}
