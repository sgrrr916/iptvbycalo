  import Foundation

  extension KeyedDecodingContainer {
      func flex<T: Decodable>(_ key: Key) throws -> T? {
          if let v = try? decode(T.self, forKey: key) { return v }
          if let s = try? decode(String.self, forKey: key), let v = s as? T { return v }
          if let i = try? decode(Int.self, forKey: key), let v = i as? T { return v }
          if let d = try? decode(Double.self, forKey: key), let v = d as? T { return v }
          return nil
      }
  }

  struct Category: Decodable, Identifiable, Hashable {
      let id: Int
      let name: String
      init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          id   = try c.flex(.id)   ?? 0
          name = try c.flex(.name) ?? ""
      }
  }

  struct LiveChannel: Decodable, Identifiable, Hashable {
      let id: Int
      let name: String
      let icon: String?
      let categoryId: Int?
      init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          id          = try c.flex(.id) ?? 0
          name        = try c.flex(.name) ?? ""
          icon        = try c.flex(.icon)
          categoryId  = try c.flex(.categoryId)
      }
  }

  struct EPGProgram: Decodable, Identifiable, Hashable {
      let id: String
      let channelId: Int
      let title: String
      let description: String?
      let start: Date
      let end: Date
      let category: String?

      init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          id          = try c.flex(.id) ?? UUID().uuidString
          channelId   = try c.flex(.channelId) ?? 0
          title       = try c.flex(.title) ?? ""
          description = try c.flex(.description)
          category    = try c.flex(.category)

          let startTS: Int = try c.flex(.start) ?? 0
          let endTS:   Int = try c.flex(.end)   ?? 0
          start = Date(timeIntervalSince1970: TimeInterval(startTS))
          end   = Date(timeIntervalSince1970: TimeInterval(endTS))
      }

      var isLiveNow: Bool { let now = Date(); return now >= start && now <= end }
      var isUpcoming: Bool { Date() < start }
      var duration: TimeInterval { end.timeIntervalSince(start) }
      var formattedTime: String {
          let f = DateFormatter(); f.dateFormat = "HH:mm"
          return "\(f.string(from: start)) - \(f.string(from: end))"
      }
  }

  struct EPGChannel: Identifiable, Hashable {
      let id: Int
      let name: String
      let icon: String?
      let programs: [EPGProgram]

      init(channel: LiveChannel, programs: [EPGProgram] = []) {
          self.id = channel.id
          self.name = channel.name
          self.icon = channel.icon
          self.programs = programs.sorted { $0.start < $1.start }
      }

      var currentProgram: EPGProgram? { programs.first { $0.isLiveNow } }
      var nextProgram: EPGProgram? { programs.first { $0.isUpcoming } }
  }

  struct FootballMatch: Identifiable, Hashable {
      let id: String
      let homeTeam: String
      let awayTeam: String
      let league: String
      let startTime: Date
      let endTime: Date
      let channels: [LiveChannel]

      var isLiveNow: Bool { let now = Date(); return now >= startTime && now <= endTime }
      var formattedTime: String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: startTime) }
      var formattedDate: String {
          let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEEE d MMMM"
          return f.string(from: startTime).capitalized
      }
  }

  struct LeagueGroup: Identifiable {
      let id = UUID()
      let name: String
      let matches: [FootballMatch]
  }

  protocol CatalogItem: Decodable, Identifiable {
      var id: Int { get }
      var title: String { get }
      var imageURL: String? { get }
  }

  struct Movie: CatalogItem {
      let id: Int
      let title: String
      let imageURL: String?
      let containerExtension: String?
      let rating: String?
      init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          id = try c.flex(.id) ?? 0
          title = try c.flex(.title) ?? ""
          imageURL = try c.flex(.imageURL)
          containerExtension = try c.flex(.containerExtension)
          rating = try c.flex(.rating)
      }
  }

  struct Show: CatalogItem {
      let id: Int
      let title: String
      let imageURL: String?
      let plot: String?
      init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          id = try c.flex(.id) ?? 0
          title = try c.flex(.title) ?? ""
          imageURL = try c.flex(.imageURL)
          plot = try c.flex(.plot)
      }
  }

  struct Episode: Decodable, Identifiable, Hashable {
      let id: Int
      let title: String
      let containerExtension: String?
      let episodeNum: Int?
      let imageURL: String?
      init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          id = try c.flex(.id) ?? 0
          title = try c.flex(.title) ?? ""
          containerExtension = try c.flex(.containerExtension)
          episodeNum = try c.flex(.episodeNum)
          imageURL = try c.flex(.imageURL)
      }
  }

  struct SeriesDetail: Decodable {
      let info: Show?
      let episodes: [Int: [Episode]]
  }

  struct AuthInfo: Decodable {
      let authorized: Bool
      let status: String?
  }
