import Foundation
import Security
import Combine

// MARK: - Credentials
struct Credentials: Codable, Equatable {
    let host: String
    let username: String
    let password: String

    var baseURL: String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.lowercased().hasPrefix("http") { h = "http://" + h }
        if h.hasSuffix("/") { h.removeLast() }
        return h
    }

    var auth: String { "\(username)/\(password)" }
}

// MARK: - Errors
enum XtreamError: LocalizedError {
    case badURL, server(String), auth
    var errorDescription: String? {
        switch self {
        case .badURL: return "URL non valido"
        case .server(let m): return m
        case .auth: return "Credenziali non valide"
        }
    }
}

// MARK: - Xtream Client
final class XtreamClient {
    let creds: Credentials
    private let session: URLSession

    init(creds: Credentials) {
        self.creds = creds
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Generic GET
    private func get<T: Decodable>(_ action: String? = nil, _ params: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(string: "\(creds.baseURL)/player_api.php")!
        var q = [
            "username": creds.username,
            "password": creds.password
        ]
        if let a = action { q["action"] = a }
        q.merge(params) { _, new in new }
        comps.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = comps.url else { throw XtreamError.badURL }

        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            if let msg = String(data: data, encoding: .utf8) { throw XtreamError.server(msg) }
            throw XtreamError.server("Errore HTTP")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Auth
    func authenticate() async throws {
        let _: AuthInfo = try get()
    }

    // MARK: - Categories
    func liveCategories() async throws -> [Category] { try get("get_live_categories") }
    func movieCategories() async throws -> [Category] { try get("get_vod_categories") }
    func seriesCategories() async throws -> [Category] { try get("get_series_categories") }

    // MARK: - Streams
    func liveChannels(category: Int? = nil) async throws -> [LiveChannel] {
        var p: [String: String] = [:]
        if let c = category { p["category_id"] = "\(c)" }
        return try get("get_live_streams", p)
    }

    func movies(category: Int? = nil) async throws -> [Movie] {
        var p: [String: String] = [:]
        if let c = category { p["category_id"] = "\(c)" }
        return try get("get_vod_streams", p)
    }

    func shows(category: Int? = nil) async throws -> [Show] {
        var p: [String: String] = [:]
        if let c = category { p["category_id"] = "\(c)" }
        return try get("get_series_streams", p)
    }

    func seriesDetail(id: Int) async throws -> SeriesDetail {
        try get("get_series_info", ["series_id": "\(id)"])
    }

    // MARK: - EPG
    /// Scarica l'EPG completo (può essere pesante). Restituisce array di programmi.
    func epgAll() async throws -> [EPGProgram] {
        try get("get_simple_data_table", ["table": "epg"])
    }

    /// EPG per un canale specifico (più leggero)
    func epgForChannel(_ channelId: Int) async throws -> [EPGProgram] {
        try get("get_simple_data_table", ["table": "epg", "stream_id": "\(channelId)"])
    }

    /// EPG per categoria
    func epgForCategory(_ categoryId: Int) async throws -> [EPGProgram] {
        try get("get_simple_data_table", ["table": "epg", "category_id": "\(categoryId)"])
    }

    // MARK: - Playback URLs
    func liveURL(_ c: LiveChannel) -> URL? {
        URL(string: "\(creds.baseURL)/live/\(creds.auth)/\(c.id).m3u8")
    }

    func movieURL(_ m: Movie) -> URL? {
        guard let ext = m.containerExtension else { return nil }
        return URL(string: "\(creds.baseURL)/movie/\(creds.auth)/\(m.id).\(ext)")
    }

    func episodeURL(_ e: Episode) -> URL? {
        guard let ext = e.containerExtension else { return nil }
        return URL(string: "\(creds.baseURL)/series/\(creds.auth)/\(e.id).\(ext)")
    }
}

// MARK: - Keychain Helper
enum Keychain {
    static func save(_ data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - AppState
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var creds: Credentials? {
        didSet { saveCreds() }
    }
    @Published var favorites: Set<Int> = [] { didSet { saveFav() } }
    @Published var pipEnabled: Bool = false { didSet { UserDefaults.standard.set(pipEnabled, forKey: "pip") } }
    @Published var recentHistory: [PlayItem] = [] { didSet { saveHistory() } }

    var client: XtreamClient? { creds.map { XtreamClient(creds: $0) } }

    private init() { loadAll() }

    func toggleFavorite(_ id: Int) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    func addToHistory(_ item: PlayItem) {
        recentHistory.removeAll { $0.url == item.url }
        recentHistory.insert(item, at: 0)
        if recentHistory.count > 50 { recentHistory = Array(recentHistory.prefix(50)) }
    }

    func logout() {
        if let c = creds { Keychain.delete(key: "creds_\(c.username)") }
        creds = nil
        favorites = []
        recentHistory = []
    }

    // MARK: Persistence
    private func loadAll() {
        loadCreds()
        favorites = Set(UserDefaults.standard.array(forKey: "fav") as? [Int] ?? [])
        pipEnabled = UserDefaults.standard.bool(forKey: "pip")
        if let data = UserDefaults.standard.data(forKey: "history"),
           let items = try? JSONDecoder().decode([PlayItem].self, from: data) {
            recentHistory = items
        }
    }

    private func loadCreds() {
        if let u = UserDefaults.standard.string(forKey: "last_user"),
           let data = Keychain.load(key: "creds_\(u)"),
           let c = try? JSONDecoder().decode(Credentials.self, from: data) {
            creds = c
        }
    }

    private func saveCreds() {
        if let c = creds,
           let data = try? JSONEncoder().encode(c) {
            Keychain.save(data, key: "creds_\(c.username)")
            UserDefaults.standard.set(c.username, forKey: "last_user")
        } else {
            UserDefaults.standard.removeObject(forKey: "last_user")
        }
    }

    private func saveFav() {
        UserDefaults.standard.set(Array(favorites), forKey: "fav")
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentHistory) {
            UserDefaults.standard.set(data, forKey: "history")
        }
    }
}

// MARK: - PlayItem (per player e history)
struct PlayItem: Identifiable, Codable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let icon: String?
    let channelId: Int?

    init(url: URL, title: String, icon: String? = nil, channelId: Int? = nil) {
        self.url = url
        self.title = title
        self.icon = icon
        self.channelId = channelId
    }

    // Codable conformance (id is excluded)
    enum CodingKeys: String, CodingKey { case url, title, icon, channelId }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(channelId, forKey: .channelId)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(URL.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        channelId = try c.decodeIfPresent(Int.self, forKey: .channelId)
    }
}
