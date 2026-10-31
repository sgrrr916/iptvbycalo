import Foundation
import Security

struct Credentials: Codable, Equatable {
    var host: String
    var username: String
    var password: String

    var baseURL: String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.lowercased().hasPrefix("http") { h = "http://" + h }
        while h.hasSuffix("/") { h.removeLast() }
        return h
    }
}

enum XtreamError: LocalizedError {
    case badURL, server, auth
    var errorDescription: String? {
        switch self {
        case .badURL: return "Indirizzo server non valido."
        case .server: return "Il server non risponde correttamente."
        case .auth: return "Credenziali non valide o account scaduto."
        }
    }
}

struct XtreamClient {
    let creds: Credentials

    private func get<T: Decodable>(_ action: String? = nil, _ params: [String: String] = [:]) async throws -> T {
        guard var comps = URLComponents(string: creds.baseURL + "/player_api.php") else { throw XtreamError.badURL }
        var items = [
            URLQueryItem(name: "username", value: creds.username.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "password", value: creds.password)
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in params { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        guard let url = comps.url else { throw XtreamError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw XtreamError.server }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func authenticate() async throws {
        let info: AuthInfo
        do { info = try await get() } catch is DecodingError { throw XtreamError.auth }
        guard info.authorized else { throw XtreamError.auth }
    }

    func liveCategories() async throws -> [Category] { try await get("get_live_categories") }
    func movieCategories() async throws -> [Category] { try await get("get_vod_categories") }
    func seriesCategories() async throws -> [Category] { try await get("get_series_categories") }

    func liveChannels(category: String?) async throws -> [LiveChannel] {
        try await get("get_live_streams", category.map { ["category_id": $0] } ?? [:])
    }
    func movies(category: String?) async throws -> [Movie] {
        try await get("get_vod_streams", category.map { ["category_id": $0] } ?? [:])
    }
    func shows(category: String?) async throws -> [Show] {
        try await get("get_series", category.map { ["category_id": $0] } ?? [:])
    }
    func seriesDetail(id: Int) async throws -> SeriesDetail {
        try await get("get_series_info", ["series_id": String(id)])
    }

    // MARK: URL di riproduzione
    private var auth: String {
        let u = creds.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? creds.username
        let p = creds.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? creds.password
        return "\(u)/\(p)"
    }
    func liveURL(_ c: LiveChannel) -> URL? { URL(string: "\(creds.baseURL)/live/\(auth)/\(c.id).m3u8") }
    func movieURL(_ m: Movie) -> URL? { URL(string: "\(creds.baseURL)/movie/\(auth)/\(m.id).\(m.ext)") }
    func episodeURL(_ e: Episode) -> URL? { URL(string: "\(creds.baseURL)/series/\(auth)/\(e.id).\(e.ext)") }
}

// MARK: Keychain
enum Keychain {
    static func save(_ data: Data, key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
    static func load(key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
    static func delete(key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: Stato globale
@MainActor
final class AppState: ObservableObject {
    @Published var creds: Credentials? { didSet { persist() } }
    @Published var favorites: Set<Int> {
        didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") }
    }
    @Published var pipEnabled: Bool {
        didSet { UserDefaults.standard.set(pipEnabled, forKey: "pip") }
    }

    init() {
        if let d = Keychain.load(key: "creds"), let c = try? JSONDecoder().decode(Credentials.self, from: d) {
            creds = c
        } else {
            creds = nil
        }
        favorites = Set((UserDefaults.standard.array(forKey: "favorites") as? [Int]) ?? [])
        pipEnabled = UserDefaults.standard.object(forKey: "pip") as? Bool ?? true
    }

    var client: XtreamClient? { creds.map { XtreamClient(creds: $0) } }

    func toggleFavorite(_ id: Int) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    private func persist() {
        if let creds, let d = try? JSONEncoder().encode(creds) {
            Keychain.save(d, key: "creds")
        } else {
            Keychain.delete(key: "creds")
        }
    }
}
