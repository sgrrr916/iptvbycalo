  import SwiftUI
  import AVKit

  struct PosterCell: View {
      let item: any CatalogItem
      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              AsyncImage(url: URL(string: item.imageURL ?? "")) { phase in
                  switch phase {
                  case .success(let img): img.resizable().aspectRatio(2/3, contentMode: .fill)
                  case .failure: Color.gray.opacity(0.3).aspectRatio(2/3, contentMode: .fit)
                  default: Color.gray.opacity(0.2).aspectRatio(2/3, contentMode: .fit)
                  }
              }
              .clipShape(RoundedRectangle(cornerRadius: 8))
              Text(item.title).font(.caption).lineLimit(2).foregroundStyle(.white)
          }
      }
  }

  // MARK: - LIVE
  struct LiveView: View {
      @EnvironmentObject var app: AppState
      @State private var categories: [Category] = []
      @State private var error: String?

      var body: some View {
          NavigationStack {
              List {
                  if !app.favorites.isEmpty {
                      NavigationLink {
                          ChannelListView(category: nil, title: "Preferiti", onlyFavorites: true)
                      } label: { Label("Preferiti", systemImage: "star.fill").foregroundStyle(.yellow) }
                  }
                  ForEach(categories) { cat in
                      NavigationLink { ChannelListView(category: cat.id, title: cat.name) } label: { Text(cat.name) }
                  }
              }
              .navigationTitle("TV in diretta")
              .task { await loadCategories() }
              .refreshable { await loadCategories() }
              .overlay { if categories.isEmpty && error == nil { ProgressView() } }
              .alert("Errore", isPresented: .constant(error != nil), actions: { Button("OK") { error = nil } }, message:
  { Text(error ?? "") })
          }
      }
      private func loadCategories() async {
          guard let client = app.client else { return }
          do { categories = try await client.liveCategories() } catch { self.error = error.localizedDescription }
      }
  }

  struct ChannelListView: View {
      @EnvironmentObject var app: AppState
      let category: Int?
      let title: String
      var onlyFavorites: Bool = false
      @State private var channels: [LiveChannel] = []
      @State private var error: String?
      @State private var searchText = ""

      var filtered: [LiveChannel] { searchText.isEmpty ? channels : channels.filter {
  $0.name.localizedCaseInsensitiveContains(searchText) } }

      var body: some View {
          List(filtered) { ch in
              HStack(spacing: 12) {
                  AsyncImage(url: URL(string: ch.icon ?? "")) { $0.resizable() } placeholder: { Color.gray.opacity(0.3)
  }
                      .frame(width: 50, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
                  Text(ch.name).lineLimit(1)
                  Spacer()
                  Button { app.toggleFavorite(ch.id) } label: {
                      Image(systemName: app.favorites.contains(ch.id) ? "heart.fill" : "heart")
                          .foregroundStyle(app.favorites.contains(ch.id) ? .red : .gray)
                  }
              }
              .contentShape(Rectangle())
              .onTapGesture { play(ch) }
          }
          .searchable(text: $searchText, prompt: "Cerca canale")
          .navigationTitle(title)
          .task { await load() }
          .refreshable { await load() }
          .overlay { if channels.isEmpty && error == nil { ProgressView() } }
          .alert("Errore", isPresented: .constant(error != nil), actions: { Button("OK") { error = nil } }, message: {
  Text(error ?? "") })
      }
      private func load() async {
          guard let client = app.client else { return }
          do {
              let all = try await client.liveChannels(category: category)
              channels = onlyFavorites ? all.filter { app.favorites.contains($0.id) } : all
          } catch { self.error = error.localizedDescription }
      }
      private func play(_ ch: LiveChannel) {
          guard let client = app.client, let url = client.liveURL(ch) else { return }
          let item = PlayItem(url: url, title: ch.name, icon: ch.icon, channelId: ch.id)
          app.addToHistory(item); app.currentPlayItem = item
      }
  }

  // MARK: - EPG / GUIDA TV
  struct EPGView: View {
      @EnvironmentObject var app: AppState
      @State private var epgChannels: [EPGChannel] = []
      @State private var categories: [Category] = []
      @State private var selectedCategory: Int? = nil
      @State private var selectedDate = Date()
      @State private var error: String?
      @State private var isLoading = false

      var filteredChannels: [EPGChannel] {
          guard let cat = selectedCategory else { return epgChannels }
          return epgChannels.filter { ch in
              // semplice filtro: se il canale appartiene alla categoria (via categoryId non disponibile qui, fallback
  su nome)
              true // per ora mostra tutti; puoi raffinare salvando categoryId in EPGChannel
          }
      }

      var body: some View {
          NavigationStack {
              VStack(spacing: 0) {
                  ScrollView(.horizontal, showsIndicators: false) {
                      HStack(spacing: 12) {
                          CategoryChip(title: "Tutti", isSelected: selectedCategory == nil) { selectedCategory = nil }
                          ForEach(categories) { cat in
                              CategoryChip(title: cat.name, isSelected: selectedCategory == cat.id) { selectedCategory =
  cat.id }
                          }
                      }.padding(.horizontal)
                  }.padding(.vertical, 8)

                  DatePicker("", selection: $selectedDate, displayedComponents: .date)
                      .datePickerStyle(.compact).labelsHidden().padding(.horizontal)
                      .onChange(of: selectedDate) { _ in Task { await loadEPG() } }

                  if epgChannels.isEmpty && !isLoading {
                      ContentUnavailableView("Nessun dato EPG", systemImage: "tv.badge.wifi", description: Text("Scarica
  la guida TV dal server"))
                  } else {
                      ScrollView {
                          LazyVStack(alignment: .leading, spacing: 16) {
                              ForEach(filteredChannels) { ch in EPGChannelRow(channel: ch, selectedDate: selectedDate) }
                          }.padding()
                      }
                  }
              }
              .navigationTitle("Guida TV")
              .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { Task { await loadEPG() } } label: {
  Image(systemName: "arrow.clockwise") }.disabled(isLoading) } }
              .task { await loadCategories(); await loadEPG() }
              .refreshable { await loadCategories(); await loadEPG() }
              .alert("Errore", isPresented: .constant(error != nil), actions: { Button("OK") { error = nil } }, message:
  { Text(error ?? "") })
          }
      }
      private func loadCategories() async {
          guard let client = app.client else { return }
          do { categories = try await client.liveCategories() } catch { self.error = error.localizedDescription }
      }
      private func loadEPG() async {
          guard let client = app.client else { return }
          isLoading = true; error = nil
          do {
              let programs: [EPGProgram] = try await client.epgAll()
              let channels = try await client.liveChannels()
              let cal = Calendar.current
              let dayPrograms = programs.filter { cal.isDate($0.start, inSameDayAs: selectedDate) }
              var map: [Int: [EPGProgram]] = [:]
              for p in dayPrograms { map[p.channelId, default: []].append(p) }
              epgChannels = channels.compactMap { ch in
                  guard let progs = map[ch.id], !progs.isEmpty else { return nil }
                  return EPGChannel(channel: ch, programs: progs)
              }
          } catch { self.error = error.localizedDescription }
          isLoading = false
      }
  }

  struct CategoryChip: View {
      let title: String; let isSelected: Bool; let action: () -> Void
      var body: some View {
          Button(action: action) {
              Text(title).font(.subheadline).padding(.horizontal, 16).padding(.vertical, 8)
                  .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                  .foregroundStyle(isSelected ? .white : .primary).clipShape(Capsule())
          }
      }
  }

  struct EPGChannelRow: View {
      let channel: EPGChannel; let selectedDate: Date
      @EnvironmentObject var app: AppState
      var body: some View {
          VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 8) {
                  AsyncImage(url: URL(string: channel.icon ?? "")) { $0.resizable() } placeholder: {
  Color.gray.opacity(0.3) }
                      .frame(width: 40, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
                  Text(channel.name).font(.headline).foregroundStyle(.white)
                  Spacer()
                  if let _ = channel.currentProgram { LiveBadge() }
              }
              ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 8) { ForEach(channel.programs) { prog in EPGProgramCard(program: prog, channel:
  channel) } }
              }
          }
      }
  }

  struct LiveBadge: View {
      @State private var blink = false
      var body: some View {
          Text("IN ONDA").font(.caption2).bold().padding(.horizontal, 6).padding(.vertical, 2)
              .background(Color.red).foregroundStyle(.white).clipShape(Capsule())
              .opacity(blink ? 1 : 0.5).onAppear { withAnimation(.easeInOut(duration: 1).repeatForever()) { blink = true
  } }
      }
  }

  struct EPGProgramCard: View {
      let program: EPGProgram; let channel: EPGChannel
      @EnvironmentObject var app: AppState
      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              Text(program.formattedTime).font(.caption2).foregroundStyle(.gray)
              Text(program.title).font(.subheadline).bold().lineLimit(2).foregroundStyle(.white)
              if let cat = program.category, cat.lowercased().contains("sport") || cat.lowercased().contains("calcio") {
                  Text(cat).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                      .background(Color.green.opacity(0.3)).foregroundStyle(.green).clipShape(Capsule())
              }
          }
          .frame(width: 160).padding(8)
          .background(program.isLiveNow ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).stroke(program.isLiveNow ? Color.blue : Color.clear, lineWidth:
  2))
          .onTapGesture { playChannel() }
      }
      private func playChannel() {
          guard let client = app.client, let url = client.liveURL(LiveChannel(id: channel.id, name: channel.name, icon:
  channel.icon, categoryId: nil)) else { return }
          let item = PlayItem(url: url, title: channel.name, icon: channel.icon, channelId: channel.id)
          app.addToHistory(item); app.currentPlayItem = item
      }
  }

  // MARK: - SPORT
  struct SportView: View {
      @EnvironmentObject var app: AppState
      @State private var leagues: [LeagueGroup] = []
      @State private var error: String?
      @State private var isLoading = false

      var body: some View {
          NavigationStack {
              Group {
                  if leagues.isEmpty && !isLoading {
                      ContentUnavailableView("Nessuna partita", systemImage: "sportscourt", description: Text("Nessun
  evento sportivo trovato nell'EPG"))
                  } else {
                      List {
                          ForEach(leagues) { league in
                              Section(league.name) {
                                  ForEach(league.matches) { match in
                                      NavigationLink { MatchDetailView(match: match) } label: { MatchRow(match: match) }
                                  }
                              }
                          }
                      }
                  }
              }
              .navigationTitle("Sport ⚽")
              .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { Task { await loadMatches() } } label:
  { Image(systemName: "arrow.clockwise") }.disabled(isLoading) } }
              .task { await loadMatches() }
              .refreshable { await loadMatches() }
              .alert("Errore", isPresented: .constant(error != nil), actions: { Button("OK") { error = nil } }, message:
  { Text(error ?? "") })
          }
      }

      private func loadMatches() async {
          guard let client = app.client else { return }
          isLoading = true; error = nil
          do {
              let programs: [EPGProgram] = try await client.epgAll()
              let channels = try await client.liveChannels()

              let now = Date()
              let window = now.addingTimeInterval(7 * 24 * 3600)
              let sportPrograms = programs.filter {
                  let cat = $0.category?.lowercased() ?? ""
                  return (cat.contains("calcio") || cat.contains("sport") || cat.contains("football") ||
  cat.contains("serie a") || cat.contains("champions") || cat.contains("europa") || cat.contains("coppa") ||
  cat.contains("premier") || cat.contains("liga") || cat.contains("bundesliga") || cat.contains("serie b"))
                  && $0.start <= window && $0.end >= now.addingTimeInterval(-3600)
              }

              var matchMap: [String: FootballMatch] = [:]
              for prog in sportPrograms {
                  let key = "\(prog.title)_\(Int(prog.start.timeIntervalSince1970 / 300))"
                  let matchChannels = channels.filter { ch in
                      sportPrograms.contains { $0.channelId == ch.id && $0.title == prog.title &&
  abs($0.start.timeIntervalSince(prog.start)) < 300 }
                  }
                  if var existing = matchMap[key] {
                      let merged = Array(Set(existing.channels + matchChannels))
                      existing = FootballMatch(id: existing.id, homeTeam: existing.homeTeam, awayTeam:
  existing.awayTeam, league: existing.league, startTime: existing.startTime, endTime: existing.endTime, channels:
  merged)
                      matchMap[key] = existing
                  } else {
                      let (home, away) = parseTeams(from: prog.title)
                      let league = extractLeague(from: prog.category ?? "", title: prog.title)
                      matchMap[key] = FootballMatch(id: prog.id, homeTeam: home, awayTeam: away, league: league,
  startTime: prog.start, endTime: prog.end, channels: matchChannels)
                  }
              }

              var leagueMap: [String: [FootballMatch]] = [:]
              for m in matchMap.values { leagueMap[m.league, default: []].append(m) }
              leagues = leagueMap.map { LeagueGroup(name: $0.key, matches: $0.value.sorted { $0.startTime < $1.startTime
  }) }.sorted { $0.name < $1.name }
          } catch { self.error = error.localizedDescription }
          isLoading = false
      }

      private func parseTeams(from title: String) -> (String, String) {
          let seps = [" vs ", " - ", " contro ", " vs. "]
          for sep in seps { let p = title.components(separatedBy: sep); if p.count == 2 { return
  (p[0].trimmingCharacters(in: .whitespaces), p[1].trimmingCharacters(in: .whitespaces)) } }
          return (title, "")
      }
      private func extractLeague(from category: String, title: String) -> String {
          let cat = category.lowercased()
          if cat.contains("serie a") { return "Serie A" }
          if cat.contains("serie b") { return "Serie B" }
          if cat.contains("champions") { return "Champions League" }
          if cat.contains("europa") { return "Europa League" }
          if cat.contains("conference") { return "Conference League" }
          if cat.contains("premier") { return "Premier League" }
          if cat.contains("liga") { return "La Liga" }
          if cat.contains("bundesliga") { return "Bundesliga" }
          if cat.contains("ligue 1") { return "Ligue 1" }
          if cat.contains("serie c") { return "Serie C" }
          if cat.contains("primavera") { return "Primavera" }
          if cat.contains("coppa italia") { return "Coppa Italia" }
          if cat.contains("supercoppa") { return "Supercoppa" }
          if cat.contains("mondiali") { return "Mondiali" }
          if cat.contains("europei") { return "Europei" }
          if cat.contains("nations") { return "Nations League" }
          return "Altro"
      }
  }

  struct MatchRow: View {
      let match: FootballMatch
      var body: some View {
          HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                  Text("\(match.homeTeam) vs \(match.awayTeam)").font(.headline).foregroundStyle(.white)
                  Text(match.league).font(.caption).foregroundStyle(.gray)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 2) {
                  Text(match.formattedTime).font(.subheadline).bold().foregroundStyle(.white)
                  if match.isLiveNow { LiveBadge() } else {
  Text(match.formattedDate).font(.caption2).foregroundStyle(.gray) }
                  Text("\(match.channels.count) canale\(match.channels.count == 1 ? "" :
  "i")").font(.caption2).foregroundStyle(.blue)
              }
          }.padding(.vertical, 4)
      }
  }

  struct MatchDetailView: View {
      let match: FootballMatch
      @EnvironmentObject var app: AppState
      var body: some View {
          List {
              Section {
                  VStack(spacing: 12) {
                      Text("\(match.homeTeam) vs
  \(match.awayTeam)").font(.title2).bold().multilineTextAlignment(.center)
                      Text(match.league).font(.subheadline).foregroundStyle(.gray)
                      HStack(spacing: 20) { Label(match.formattedDate, systemImage: "calendar");
  Label(match.formattedTime, systemImage: "clock") }.font(.subheadline).foregroundStyle(.white)
                      if match.isLiveNow { LiveBadge() }
                  }.frame(maxWidth: .infinity).padding(.vertical)
              }
              Section("Canali disponibili (\(match.channels.count))") {
                  ForEach(match.channels) { ch in
                      Button { playChannel(ch) } label: {
                          HStack(spacing: 12) {
                              AsyncImage(url: URL(string: ch.icon ?? "")) { $0.resizable() } placeholder: {
  Color.gray.opacity(0.3) }
                                  .frame(width: 50, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
                              Text(ch.name).foregroundStyle(.white)
                              Spacer()
                              Image(systemName: "play.circle.fill").foregroundStyle(.green)
                          }
                      }
                  }
              }
          }
          .navigationTitle("Dettaglio partita")
          .navigationBarTitleDisplayMode(.inline)
      }
      private func playChannel(_ ch: LiveChannel) {
          guard let client = app.client, let url = client.liveURL(ch) else { return }
          let item = PlayItem(url: url, title: ch.name, icon: ch.icon, channelId: ch.id)
          app.addToHistory(item); app.currentPlayItem = item
      }
  }

  // MARK: - IMPOSTAZIONI
  struct SettingsView: View {
      @EnvironmentObject var app: AppState
      var body: some View {
          NavigationStack {
              Form {
                  Section("Account") { LabeledContent("Server", value: app.creds?.baseURL ?? "");
  LabeledContent("Utente", value: app.creds?.username ?? "") }
                  Section("TV in diretta") { Toggle("Picture in Picture", isOn: $app.pipEnabled); LabeledContent("Canali
  preferiti", value: "\(app.favorites.count)"); Button("Rimuovi tutti i preferiti", role: .destructive) { app.favorites
  = [] }.disabled(app.favorites.isEmpty) }
                  Section("Cronologia") { LabeledContent("Elementi", value: "\(app.recentHistory.count)"); if
  !app.recentHistory.isEmpty { Button("Cancella cronologia", role: .destructive) { app.recentHistory = [] } } }
                  Section { Button("Esci", role: .destructive) { app.logout() } }
              }.navigationTitle("Impostazioni")
          }
      }
  }
