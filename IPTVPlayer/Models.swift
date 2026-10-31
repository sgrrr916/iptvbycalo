import Foundation

extension KeyedDecodingContainer {
    /// Xtream restituisce lo stesso campo a volte come stringa, a volte come numero.
    func flex(_ key: Key) -> String? {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) { return String(d) }
        return nil
    }
}

protocol CatalogItem: Identifiable, Hashable {
    var title: String { get }
    var imageURL: URL? { get }
}

struct Category: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    enum K: String, CodingKey { case category_id, category_name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = c.flex(.category_id) ?? UUID().uuidString
        name = c.flex(.category_name) ?? "—"
    }
}

struct LiveChannel: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let icon: URL?
    enum K: String, CodingKey { case stream_id, name, stream_icon }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = Int(c.flex(.stream_id) ?? "") ?? 0
        name = c.flex(.name) ?? ""
        icon = c.flex(.stream_icon).flatMap { URL(string: $0) }
    }
}

struct Movie: CatalogItem, Decodable {
    let id: Int
    let title: String
    let imageURL: URL?
    let ext: String
    let rating: String?
    enum K: String, CodingKey { case stream_id, name, stream_icon, container_extension, rating }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = Int(c.flex(.stream_id) ?? "") ?? 0
        title = c.flex(.name) ?? ""
        imageURL = c.flex(.stream_icon).flatMap { URL(string: $0) }
        ext = c.flex(.container_extension) ?? "mp4"
        rating = c.flex(.rating)
    }
}

struct Show: CatalogItem, Decodable {
    let id: Int
    let title: String
    let imageURL: URL?
    let plot: String?
    enum K: String, CodingKey { case series_id, name, cover, plot }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = Int(c.flex(.series_id) ?? "") ?? 0
        title = c.flex(.name) ?? ""
        imageURL = c.flex(.cover).flatMap { URL(string: $0) }
        plot = c.flex(.plot)
    }
}

struct Episode: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let ext: String
    let number: Int
    let image: URL?
    enum K: String, CodingKey { case id, title, container_extension, episode_num, info }
    enum I: String, CodingKey { case movie_image }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = c.flex(.id) ?? UUID().uuidString
        title = c.flex(.title) ?? "Episodio"
        ext = c.flex(.container_extension) ?? "mp4"
        number = Int(c.flex(.episode_num) ?? "") ?? 0
        let info = try? c.nestedContainer(keyedBy: I.self, forKey: .info)
        image = info?.flex(.movie_image).flatMap { URL(string: $0) }
    }
}

struct SeriesDetail: Decodable {
    let seasons: [Int: [Episode]]
    enum K: String, CodingKey { case episodes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        // Se non ci sono episodi alcuni server mandano [] invece di {}
        let raw = (try? c.decode([String: [Episode]].self, forKey: .episodes)) ?? [:]
        seasons = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in
            Int(k).map { n in (n, v.sorted { $0.number < $1.number }) }
        })
    }
}

struct AuthInfo: Decodable {
    let authorized: Bool
    let status: String
    enum K: String, CodingKey { case user_info }
    enum U: String, CodingKey { case auth, status }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let u = try c.nestedContainer(keyedBy: U.self, forKey: .user_info)
        authorized = u.flex(.auth) == "1"
        status = u.flex(.status) ?? ""
    }
}
