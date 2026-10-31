  import SwiftUI
  import AVKit

  @main
  struct IPTVPlayerApp: App {
      @StateObject private var app = AppState.shared
      var body: some Scene {
          WindowGroup {
              RootView().environmentObject(app).preferredColorScheme(.dark)
          }
      }
  }

  struct RootView: View {
      @EnvironmentObject var app: AppState
      var body: some View {
          if let _ = app.client {
              TabView {
                  LiveView().tabItem { Label("Live", systemImage: "tv") }
                  EPGView().tabItem { Label("Guida TV", systemImage: "calendar") }
                  SportView().tabItem { Label("Sport", systemImage: "sportscourt") }
                  SettingsView().tabItem { Label("Impostazioni", systemImage: "gearshape") }
              }
          } else { LoginView() }
      }
  }

  struct LoginView: View {
      @EnvironmentObject var app: AppState
      @State private var host = ""; @State private var username = ""; @State private var password = ""
      @State private var busy = false; @State private var error: String?
      var body: some View {
          NavigationStack {
              Form {
                  Section("Server Xtream Codes") {
                      TextField("http://server.com:8080", text:
  $host).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                      TextField("Username", text:
  $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                      SecureField("Password", text: $password)
                  }
                  if let error { Text(error).foregroundStyle(.red) }
                  Button { Task { await login() } } label: { if busy { ProgressView().frame(maxWidth: .infinity) } else
  { Text("Accedi").frame(maxWidth: .infinity) } }
                      .disabled(busy || host.isEmpty || username.isEmpty || password.isEmpty)
              }.navigationTitle("Accedi")
          }
      }
      private func login() async {
          busy = true; error = nil
          let c = Credentials(host: host, username: username, password: password)
          do { try await XtreamClient(creds: c).authenticate(); app.creds = c } catch { self.error =
  error.localizedDescription }
          busy = false
      }
  }

  struct PlayItem: Identifiable { let id = UUID(); let url: URL; let title: String }

  struct PlayerRepresentable: UIViewControllerRepresentable {
      let player: AVPlayer; let pip: Bool
      func makeUIViewController(context: Context) -> AVPlayerViewController {
          let vc = AVPlayerViewController(); vc.player = player; vc.allowsPictureInPicturePlayback = pip;
  vc.canStartPictureInPictureAutomaticallyFromInline = pip; return vc
      }
      func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
  }

  struct PlayerScreen: View {
      let item: PlayItem; let pip: Bool
      @Environment(\.dismiss) private var dismiss
      @State private var player: AVPlayer
      init(item: PlayItem, pip: Bool) { self.item = item; self.pip = pip; _player = State(initialValue: AVPlayer(url:
  item.url)) }
      var body: some View {
          ZStack(alignment: .topLeading) {
              Color.black.ignoresSafeArea()
              PlayerRepresentable(player: player, pip: pip).ignoresSafeArea()
              Button { player.pause(); dismiss() } label: { Image(systemName:
  "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.85)).padding() }
          }
          .onAppear { try? AVAudioSession.sharedInstance().setCategory(.playback); try?
  AVAudioSession.sharedInstance().setActive(true); player.play() }
      }
  }

  extension View {
      func playerCover(_ item: Binding<PlayItem?>, pip: Bool) -> some View { fullScreenCover(item: item) {
  PlayerScreen(item: $0, pip: pip) } }
  }
