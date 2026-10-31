import SwiftUI

// MARK: Live
struct LiveView: View {
    @EnvironmentObject var app: AppState
    @State private var categories: [Category] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""

    private var filtered: [Category] {
        search.isEmpty ? categories : categories.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ChannelListView(title: "Preferiti", category: nil, onlyFavorites: true)
                } label: { Label("Preferiti", systemImage: "heart.fill") }
                ForEach(filtered) { cat in
                    NavigationLink {
                        ChannelListView(title: cat.name, category: cat.id, onlyFavorites: false)
                    } label: { Label(cat.name, systemImage: "folder") }
                }
            }
            .overlay {
                if loading { ProgressView() }
                else if let error { Text(error).foregroundStyle(.secondary).padding() }
            }
            .navigationTitle("Live")
            .searchable(text: $search, prompt: "Cerca categoria")
            .task {
                guard let client = app.client else { return }
                do { categories = try await client.liveCategories() }
                catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }
}

struct ChannelListView: View {
    let title: String
    let category: String?
    let onlyFavorites: Bool
    @EnvironmentObject var app: AppState
    @State private var channels: [LiveChannel] = []
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var playing: PlayItem?

    private var shown: [LiveChannel] {
        channels.filter {
            (!onlyFavorites || app.favorites.contains($0.id)) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List(shown) { ch in
            HStack {
                Button { play(ch) } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: ch.icon) { $0.resizable().scaledToFit() } placeholder: {
                            Image(systemName: "tv").foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: 44)
                        Text(ch.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                Button { app.toggleFavorite(ch.id) } label: {
                    Image(systemName: app.favorites.contains(ch.id) ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if let error { Text(error).foregroundStyle(.secondary).padding() }
            else if shown.isEmpty { Text("Nessun canale").foregroundStyle(.secondary) }
        }
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Cerca canale")
        .playerCover($playing, pip: app.pipEnabled)
        .task {
            guard let client = app.client else { return }
            do { channels = try await client.liveChannels(category: category) }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    private func play(_ ch: LiveChannel) {
        guard let url = app.client?.liveURL(ch) else { return }
        playing = PlayItem(url: url, title: ch.name)
    }
}

// MARK: Catalogo generico (Film e Serie)
struct PosterCell<Item: CatalogItem>: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: item.imageURL) { $0.resizable().scaledToFill() } placeholder: {
                ZStack { Color.gray.opacity(0.2); Image(systemName: "photo").foregroundStyle(.secondary) }
            }
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.title).font(.caption).lineLimit(2).multilineTextAlignment(.leading)
        }
    }
}

struct CatalogView<Item: CatalogItem, Detail: View>: View {
    let title: String
    let loadCategories: () async throws -> [Category]
    let loadItems: (String) async throws -> [Item]
    @ViewBuilder let detail: (Item) -> Detail

    @State private var categories: [Category] = []
    @State private var selected: String?
    @State private var cache: [String: [Item]] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""

    private var items: [Item] {
        let all = cache[selected ?? ""] ?? []
        return search.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(categories) { cat in
                            Button(cat.name) { selected = cat.id }
                                .buttonStyle(.bordered)
                                .tint(cat.id == selected ? .accentColor : .gray)
                        }
                    }
                    .padding(.horizontal)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { PosterCell(item: item) }.buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .overlay {
                if loading { ProgressView() }
                else if let error { Text(error).foregroundStyle(.secondary).padding() }
            }
            .navigationDestination(for: Item.self) { detail($0) }
            .navigationTitle(title)
            .searchable(text: $search, prompt: "Cerca")
            .task {
                do {
                    categories = try await loadCategories()
                    selected = categories.first?.id
                    if categories.isEmpty { loading = false }
                } catch {
                    self.error = error.localizedDescription
                    loading = false
                }
            }
            .task(id: selected) {
                guard let sel = selected else { return }
                if cache[sel] == nil {
                    loading = true
                    do { cache[sel] = try await loadItems(sel) }
                    catch { self.error = error.localizedDescription }
                }
                loading = false
            }
        }
    }
}

// MARK: Film
struct MoviesView: View {
    let client: XtreamClient
    var body: some View {
        CatalogView(title: "Film",
                    loadCategories: { try await client.movieCategories() },
                    loadItems: { try await client.movies(category: $0) }) { movie in
            MovieDetailView(movie: movie)
        }
    }
}

struct MovieDetailView: View {
    let movie: Movie
    @EnvironmentObject var app: AppState
    @State private var playing: PlayItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AsyncImage(url: movie.imageURL) { $0.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.2) }
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(movie.title).font(.title2.bold()).multilineTextAlignment(.center)
                if let r = movie.rating, !r.isEmpty, r != "0" {
                    Label(r, systemImage: "star.fill").foregroundStyle(.yellow)
                }
                Button {
                    if let url = app.client?.movieURL(movie) { playing = PlayItem(url: url, title: movie.title) }
                } label: {
                    Label("Riproduci", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .playerCover($playing, pip: app.pipEnabled)
    }
}

// MARK: Serie
struct SeriesView: View {
    let client: XtreamClient
    var body: some View {
        CatalogView(title: "Serie",
                    loadCategories: { try await client.seriesCategories() },
                    loadItems: { try await client.shows(category: $0) }) { show in
            SeriesDetailView(show: show)
        }
    }
}

struct SeriesDetailView: View {
    let show: Show
    @EnvironmentObject var app: AppState
    @State private var detail: SeriesDetail?
    @State private var season = 1
    @State private var loading = true
    @State private var playing: PlayItem?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: show.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(show.plot ?? "").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let detail {
                Picker("Stagione", selection: $season) {
                    ForEach(detail.seasons.keys.sorted(), id: \.self) { Text("Stagione \($0)").tag($0) }
                }
                .pickerStyle(.menu)
                Section {
                    ForEach(detail.seasons[season] ?? []) { ep in
                        Button { play(ep) } label: {
                            HStack {
                                Text("\(ep.number)").foregroundStyle(.secondary).frame(width: 28)
                                Text(ep.title)
                                Spacer()
                                Image(systemName: "play.fill").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .playerCover($playing, pip: app.pipEnabled)
        .task {
            guard let client = app.client else { return }
            if let d = try? await client.seriesDetail(id: show.id) {
                detail = d
                season = d.seasons.keys.min() ?? 1
            }
            loading = false
        }
    }

    private func play(_ ep: Episode) {
        guard let url = app.client?.episodeURL(ep) else { return }
        playing = PlayItem(url: url, title: ep.title)
    }
}
