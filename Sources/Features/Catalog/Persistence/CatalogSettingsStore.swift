import Foundation
import Security
import SwiftUI

@MainActor
final class CatalogSettingsStore: ObservableObject {
    static let shared = CatalogSettingsStore()

    @Published private(set) var connection: CatalogConnection
    private let defaults: UserDefaults

    private enum Key {
        static let source = "CatalogSource"
        static let cubURL = "CatalogCUBURL"
        static let route = "CatalogTMDBRoute"
        static let proxy = "CatalogTMDBProxy"
        static let mirror = "CatalogImageMirror"
        static let timeout = "CatalogTimeout"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuration = CatalogTMDBConnection(
            route: defaults.string(forKey: Key.route).flatMap(CatalogTMDBRoute.init(rawValue:)) ?? .direct,
            proxy: defaults.string(forKey: Key.proxy).flatMap(CatalogConnection.endpoint),
            timeout: defaults.object(forKey: Key.timeout) == nil ? 12 : min(30, max(5, defaults.double(forKey: Key.timeout)))
        )
        connection = CatalogConnection(
            source: defaults.string(forKey: Key.source).flatMap(CatalogSource.init(rawValue:)) ?? .tmdb,
            cubURL: defaults.string(forKey: Key.cubURL).flatMap(CatalogConnection.endpoint) ?? CatalogConnection.publicCUB,
            cubToken: CatalogCUBCredential.read(),
            tmdb: configuration,
            imageMirror: defaults.string(forKey: Key.mirror).flatMap(CatalogConnection.endpoint)
        )
    }

    func save(_ value: CatalogConnection) -> Bool {
        guard value.cubToken == connection.cubToken || CatalogCUBCredential.save(value.cubToken) else {
            return false
        }
        defaults.set(value.source.rawValue, forKey: Key.source)
        defaults.set(value.cubURL.absoluteString, forKey: Key.cubURL)
        defaults.set(value.tmdb.route.rawValue, forKey: Key.route)
        defaults.set(value.tmdb.proxy?.absoluteString, forKey: Key.proxy)
        defaults.set(value.imageMirror?.absoluteString, forKey: Key.mirror)
        defaults.set(value.timeout, forKey: Key.timeout)
        if value != connection { connection = value }
        return true
    }
}

private enum CatalogCUBCredential {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "TorrServeSilicon",
            kSecAttrAccount as String: "Catalog CUB token"
        ]
    }

    static func read() -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ token: String) -> Bool {
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let value = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var request = query
        request[kSecValueData as String] = value
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }
}
