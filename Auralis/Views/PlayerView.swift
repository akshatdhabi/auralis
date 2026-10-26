import SwiftUI

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).padding(.vertical, 9)
            .background(.white.opacity(configuration.isPressed ? 0.13 : 0.05), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}
struct PlayerView: View {
    @Bindable var model: PlayerSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubbing = false
    @State private var seekPosition = 0.0
    var body: some View {
        VStack(spacing: 0) {
            if (model.stage && !model.immersive) || model.showingWebsite { header }
            if let notice = model.notice {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                    Text(notice).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Reload") { model.reload() }
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message")
                }.font(.system(size: 12)).padding(14).background(model.accent.opacity(0.12))
            }
            ZStack {
                // Keep the same view mounted. Switching presentation never reloads the playback source.
                // Cover the website with opaque native surfaces instead of setting opacity to zero.
                // WebKit otherwise defers lazy thumbnails needed by the native catalog and queue.
                EmbeddedPlayer(session: model)
                    .allowsHitTesting(model.showingWebsite).accessibilityHidden(!model.showingWebsite)
                if !model.showingWebsite {
                    // This backing stays opaque throughout native fades, including separator gaps.
                    Color.ink
                    if model.stage {
                        ListeningView(model: model).transition(.opacity)
                    }
                    else { BrowseView(model: model).transition(.opacity) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            // The full website keeps its own controls; native screens share exactly one transport.
            if !model.showingWebsite && (!model.stage || !model.immersive) { transport }
        }
        .frame(minWidth: 900, minHeight: 650)
        .foregroundStyle(Color.warmWhite).background(Color.ink).preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.stage)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.showQueue)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            guard (notification.object as? NSWindow) === model.window else { return }; model.isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            guard (notification.object as? NSWindow) === model.window else { return }
            model.isFullScreen = false
            if model.immersive { model.exitImmersive() }
        }
    }
    private var header: some View {
        HStack(spacing: 24) {
            HStack(spacing: 0) {
                Text("auralis").font(.system(size: 22, weight: .bold)).tracking(-1.8)
                Text(".").font(.system(size: 26, weight: .black)).foregroundStyle(model.accent)
            }.padding(.trailing, 14)
            Button { model.stage = false; model.website = false } label: { tab(model.showingWebsite ? "Back to Auralis" : "browse", selected: !model.stage) }.buttonStyle(.plain).keyboardShortcut("1")
            Button { model.stage = true } label: { tab("now playing", selected: model.stage) }.buttonStyle(.plain).keyboardShortcut("2")
            Spacer()
            if model.loading { ProgressView().controlSize(.small).accessibilityLabel("Loading YouTube Music") }
            if !model.stage {
                Button { model.player.goBack() } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).help("Back").disabled(!model.player.canGoBack)
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Reload YouTube Music")
            }
            if model.stage {
                Button { model.enterImmersive() } label: { Image(systemName: "sparkles.tv").font(.system(size: 17)) }.buttonStyle(.plain).accessibilityLabel("Enter immersive mode").help("Immersive full screen")
                if model.radioBusy { HStack(spacing: 8) { ProgressView().controlSize(.mini); Text("Starting mix…").font(.system(size: 12)).foregroundStyle(Color.secondaryInk) } }
                Button { model.toggleQueue() } label: { Label("Up next", systemImage: "list.bullet").font(.system(size: 11)) }.buttonStyle(QuietButton())
                Menu {
                    ForEach(model.queue?.links ?? []) { link in Button("Go to \(link.kind): \(link.title)") { model.open(link) } }
                    Divider()
                    Button("Start radio") { model.startRadio() }.disabled(model.queue?.canRadio != true)
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Current track actions")
            }
            Button { model.account() } label: {
                Label(model.signedIn ? "Account" : "Sign in", systemImage: model.signedIn ? "person.crop.circle" : "person.crop.circle.badge.plus")
                    .font(.system(size: 12))
            }.buttonStyle(QuietButton())
            Button { model.fullScreen() } label: {
                Image(systemName: model.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }.buttonStyle(.plain).accessibilityLabel(model.isFullScreen ? "Leave full screen" : "Full screen")
        }.padding(.horizontal, 36).padding(.vertical, 12)
            .background { ChromePattern(accent: model.accent) }
    }
    private func tab(_ text: String, selected: Bool) -> some View {
        VStack(spacing: 7) {
            Text(text).font(.system(size: 27, weight: .semibold)).tracking(-0.9).foregroundStyle(selected ? Color.warmWhite : Color.secondaryInk)
            Rectangle().fill(selected ? model.accent : .clear).frame(height: 2)
        }.fixedSize()
    }
    private var transport: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 22) {
                if !model.stage {
                    Button { model.website = false; model.stage = true } label: {
                      HStack(spacing: 12) {
                        ZStack {
                            Color.tile
                            if let image = model.artwork { Image(nsImage: image).resizable().scaledToFill() }
                            else if model.artworkLoading { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "music.note").foregroundStyle(Color.secondaryInk) }
                        }.frame(width: 42, height: 42).clipped()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.snapshot?.title.isEmpty == false ? model.snapshot!.title : "Your music, here.").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(model.snapshot?.artist ?? "Choose a track to begin").font(.system(size: 12)).foregroundStyle(Color.secondaryInk).lineLimit(1)
                        }
                      }.frame(width: 190, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityLabel("Open Now Playing")
                        .accessibilityValue("\(model.snapshot?.title ?? "No track selected"), \(model.snapshot?.artist ?? "")")
                        .help("Open Now Playing")
                }
                HStack(spacing: 17) {
                    control("backward.end.fill", label: "Previous track", action: .previoustrack)
                    Button { model.togglePlayback() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17))
                            .frame(width: 45, height: 45).foregroundStyle(Color.ink)
                            .background(model.accent.opacity(model.fresh ? 1 : 0.3), in: Circle())
                    }.buttonStyle(.plain).disabled(!model.supports(model.isPlaying ? .pause : .play))
                        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                    control("forward.end.fill", label: "Next track", action: .nexttrack)
                }
                TimelineView(.periodic(from: .now, by: 0.5)) { time in
                    VStack(spacing: 2) {
                        Slider(value: Binding(get: { scrubbing ? seekPosition : model.position(at: time.date) ?? 0 }, set: { seekPosition = $0 }),
                               in: 0...max(1, model.snapshot?.duration ?? 1), onEditingChanged: { editing in
                            if editing { seekPosition = model.position(at: Date()) ?? 0; scrubbing = true }
                            else { model.command(.seekto, seekTime: seekPosition); scrubbing = false }
                        }).tint(model.accent).disabled(!model.supports(.seekto)).accessibilityLabel("Playback position")
                            .accessibilityValue("\(ClockText.format(model.position(at: time.date))) of \(ClockText.format(model.snapshot?.duration))")
                            .accessibilityAdjustableAction { direction in
                                guard model.supports(.seekto), let position = model.position(at: Date()), let duration = model.snapshot?.duration else { return }
                                model.command(.seekto, seekTime: min(duration, max(0, position + (direction == .increment ? 5 : -5))))
                            }
                        HStack {
                            Text(ClockText.format(scrubbing ? seekPosition : model.position(at: time.date)))
                            Spacer()
                            Text(model.fresh ? "YOUTUBE MUSIC" : (model.snapshot == nil ? "CHOOSE A TRACK" : "UPDATING…")).tracking(1.2)
                            Spacer(); Text(ClockText.format(model.snapshot?.duration))
                        }.font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.secondaryInk)
                    }
                }
                Button { model.stage = true; if !model.showQueue { model.toggleQueue() } else { model.loadQueue() } } label: { Image(systemName: "list.bullet").foregroundStyle(Color.secondaryInk) }
                    .buttonStyle(.plain).accessibilityLabel("Show Up next")
                Menu {
                    Text("Quality is managed by YouTube Music.")
                    Text("This app cannot verify the stream bitrate.")
                    Button("Open YouTube Music") { model.openWebsite() }
                } label: { Image(systemName: "info.circle").foregroundStyle(Color.secondaryInk) }.menuStyle(.borderlessButton).fixedSize().help("Playback quality and information")
            }.padding(.horizontal, 30).padding(.vertical, 18)
        }.background(Color.ink)
    }
    private func control(_ icon: String, label: String, action: PlaybackAction) -> some View {
        Button { model.command(action) } label: { Image(systemName: icon).frame(width: 22, height: 32) }
            .buttonStyle(.plain).disabled(!model.supports(action)).accessibilityLabel(label).help(label)
    }
}
