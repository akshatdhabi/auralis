import SwiftUI

/// The listening room is another landscape, with the real provider queue beside
/// the artwork. Background, title, cover and queue each occupy a different depth.
struct ListeningView: View {
    @Bindable var model: PlayerSession
    @State private var position = PanoramaPosition()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PanoramaBackdrop(position: position, accent: model.accent)
                AmbientCanvas(accent: model.accent, style: model.motion, active: model.isPlaying && model.active, lowPower: model.lowPower).opacity(0.48).allowsHitTesting(false)
                if model.textAtmosphere != .off {
                    TypeAtmosphere(title: model.title, artist: model.artist, phrases: atmospherePhrases,
                                   accent: model.accent, active: model.isPlaying && model.active, lowPower: model.lowPower)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if model.immersive { immersionToolbar }
                    else {
                        HStack(alignment: .lastTextBaseline, spacing: 22) {
                            Text("now playing").font(.system(size: min(112, geometry.size.width * 0.094), weight: .bold)).tracking(-5)
                                .modifier(PanoramaTitleOffset(position: position, rate: 0.14, limit: 130)).accessibilityAddTraits(.isHeader)
                            Spacer(minLength: 0)
                            atmosphereMenu.padding(.bottom, 14)
                        }.padding(.horizontal, 36).frame(height: 116).clipped()
                    }
                    // The viewport receives the remaining layout space. Never subtract a
                    // remembered full-screen header/footer size from the window geometry.
                    GeometryReader { viewport in listeningPanorama(size: viewport.size) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !model.immersive { PanoramaRail(position: position, accent: model.accent, label: model.showQueue ? "scroll into your queue" : "made for the music").fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
        .onChange(of: reduceMotion, initial: true) { position.reduceMotion = reduceMotion }
        .onChange(of: model.showQueue) { if model.showQueue { model.loadQueue() }; position.move(to: 0) }
        .task { if model.showQueue { model.loadQueue() } }
        .task(id: model.textAtmosphere.rawValue + model.contextKey + String(model.fresh)) { await model.prepareTextAtmosphere() }
    }
    private var immersionToolbar: some View {
        HStack(spacing: 22) {
            Text("auralis.").font(.system(size: 22, weight: .bold)).tracking(-1).foregroundStyle(model.accent)
            Spacer()
            Button { model.command(.previoustrack) } label: { Image(systemName: "backward.end.fill") }.buttonStyle(.plain).accessibilityLabel("Previous track")
            Button { model.togglePlayback() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain).accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            Button { model.command(.nexttrack) } label: { Image(systemName: "forward.end.fill") }.buttonStyle(.plain).accessibilityLabel("Next track")
            atmosphereMenu
            Button { model.exitImmersive() } label: { Label("Exit immersion", systemImage: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(QuietButton()).font(.system(size: 12, weight: .medium)).keyboardShortcut(.escape, modifiers: [])
        }.padding(.horizontal, 36).frame(height: 62)
    }
    private func listeningPanorama(size: CGSize) -> some View {
        let leadWidth = model.showQueue && !model.immersive ? max(640, size.width * 0.76) : max(1, size.width - 72)
        let queueWidth: CGFloat = 440
        let total = 72 + leadWidth + (model.showQueue && !model.immersive ? 52 + queueWidth : 0)
        return PanoramaViewport(position: position, size: size, contentWidth: total, resetKey: "listening", moveRequest: position.request, requestedOffset: position.target) {
            HStack(alignment: .top, spacing: 52) {
                PanoramaPanel(origin: 36, width: leadWidth) { listeningRoom(width: leadWidth, height: size.height) }
                if model.showQueue && !model.immersive {
                    PanoramaPanel(origin: 36 + leadWidth + 52, width: queueWidth) { QueueView(model: model) }
                }
            }.padding(.horizontal, 36).frame(width: max(total, size.width), height: size.height, alignment: .topLeading)
                .foregroundStyle(Color.warmWhite).environment(position)
        }
    }
    private var atmospherePhrases: [String] {
        if model.textAtmosphere == .lyrics, let lyrics = model.lyrics, lyrics.title == model.snapshot?.title { return lyrics.lines }
        if model.textAtmosphere == .artist, let story = model.artistStory, story.artist == model.snapshot?.artist {
            return [story.artist] + story.text.components(separatedBy: ". ").filter { !$0.isEmpty }
        }
        return [model.title, model.artist, model.snapshot?.album ?? "", model.title, model.artist].filter { !$0.isEmpty }
    }
    private var atmosphereMenu: some View {
        Menu {
            Picker("Background text", selection: $model.textAtmosphere) {
                ForEach(TextAtmosphere.allCases) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Picker("Ambient motion", selection: $model.motion) { ForEach(AmbientMotion.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Colour", selection: $model.theme) {
                Text("From artwork").tag(0); Text("Ember").tag(1); Text("Ultraviolet").tag(2); Text("Glacier").tag(3)
            }
            Divider()
            Button("Immersive full screen") { model.enterImmersive() }
        } label: { Label("Atmosphere", systemImage: "sparkles").font(.system(size: 13, weight: .semibold)) }
            .menuStyle(.borderlessButton).fixedSize().help("Drifting text follows time and playback state. Artist story looks up the artist name on Wikipedia.")
    }
    @ViewBuilder private var atmosphereCredit: some View {
        HStack(alignment: .center, spacing: 10) {
            if model.contextBusy { ProgressView().controlSize(.mini); Text(model.textAtmosphere == .artist ? "Finding the artist’s story…" : "Checking YouTube Music lyrics…") }
            else if let message = model.contextMessage { Text(message) }
            else if model.textAtmosphere == .artist, let story = model.artistStory {
                Button { model.openStorySource() } label: { Label("Artist story: \(story.article) · Wikipedia · CC BY-SA ↗", systemImage: "text.book.closed") }.buttonStyle(.plain)
            } else if model.textAtmosphere == .lyrics, model.lyrics != nil { Text("LYRICS FROM YOUTUBE MUSIC · NOT SYNCHRONIZED") }
            else { Text("AMBIENT TYPOGRAPHY · ARTWORK FROM YOUTUBE MUSIC") }
            Spacer(minLength: 0)
        }.font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondaryInk)
            .help("Time and playback state drive motion. No audio analysis or beat detection.")
    }
    private func listeningRoom(width: CGFloat, height: CGFloat) -> some View {
        let mainHeight = max(1, height - 96)
        let compact = mainHeight < 290
        let coverSize = max(1, min(mainHeight, width * (model.immersive ? 0.43 : 0.47)))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(model.accent).frame(width: 6, height: 6)
                Text(model.fresh ? (model.isPlaying ? "PLAYING FROM YOUTUBE MUSIC" : "ON PAUSE") : "YOUR SPACE")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Color.secondaryInk)
            }.frame(height: 24)
            HStack(alignment: .center, spacing: 32) {
                Group {
                    if let artwork = model.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                    else { MotionStudyArt(accent: model.accent) }
                }.frame(width: coverSize, height: coverSize).scaleEffect(reduceMotion ? 1 : 1.06)
                    .modifier(PanoramaArtworkOffset()).frame(width: coverSize, height: coverSize).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8)).shadow(color: .black.opacity(0.38), radius: 24, y: 16)
                    .accessibilityLabel(model.artwork == nil ? "Placeholder artwork" : "Album artwork")
                VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                    Text(model.title).font(.system(size: min(66, width * 0.072, mainHeight * 0.23), weight: .bold)).tracking(-2.2)
                        .lineLimit(compact ? 2 : 4).minimumScaleFactor(0.5).layoutPriority(1)
                    if let artist = model.queue?.links.first(where: { $0.kind == "artist" }) {
                        Button(model.artist) { model.open(artist) }.buttonStyle(.plain).font(.system(size: compact ? 19 : 24, weight: .medium)).foregroundStyle(model.accent).lineLimit(2).help("Open artist")
                    } else { Text(model.artist).font(.system(size: compact ? 19 : 24, weight: .medium)).foregroundStyle(Color.secondaryInk).lineLimit(2) }
                    if !compact, let album = model.snapshot?.album, !album.isEmpty {
                        if let link = model.queue?.links.first(where: { $0.kind == "album" || $0.kind == "playlist" }) {
                            Button(album) { model.open(link) }.buttonStyle(.plain).font(.system(size: 16)).foregroundStyle(Color.secondaryInk).lineLimit(2)
                        } else { Text(album).font(.system(size: 16)).foregroundStyle(Color.secondaryInk).lineLimit(2) }
                    }
                    HStack(spacing: 14) {
                        Button { model.startRadio() } label: { Label("start mix", systemImage: "dot.radiowaves.left.and.right") }.buttonStyle(.plain).disabled(model.radioBusy || model.queue?.canRadio != true)
                        Button { if model.immersive { model.exitImmersive() }; model.stage = false; model.website = false } label: { Image(systemName: "arrow.up.left").accessibilityLabel("Browse music") }.buttonStyle(.plain)
                    }.font(.system(size: 16, weight: .semibold)).foregroundStyle(model.accent).padding(.top, compact ? 0 : 8)
                }.frame(maxWidth: .infinity, maxHeight: mainHeight, alignment: .leading)
            }.frame(height: mainHeight).padding(.vertical, 20)
            atmosphereCredit.lineLimit(1).minimumScaleFactor(0.75).frame(height: 28, alignment: .center)
        }.frame(width: width, height: height, alignment: .top)
    }
}
