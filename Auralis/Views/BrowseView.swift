import SwiftUI
import AppKit

struct BrowseArtwork: View {
    let address: String?
    var round = false
    var seed: NSImage? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var imageAddress: String?
    @State private var resolved = false
    var body: some View {
        let reduceMotion = reduceMotion
        GeometryReader { geo in
            let verticalParallax = min(12, geo.size.height * 0.06)
            ZStack {
                LinearGradient(colors: [Color(red: 0.17, green: 0.14, blue: 0.21), .ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = (imageAddress == address ? image : nil) ?? seed ?? BrowseArtworkCache.shared.cached(address) { Image(nsImage: image).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(reduceMotion ? 1 : 1.16)
                    .scrollTransition(.interactive, axis: .vertical) { effect, phase in effect.offset(y: reduceMotion ? 0 : phase.value * -verticalParallax) }
                    .modifier(PanoramaArtworkOffset())
                    .clipped() }
                else { VStack(spacing: 10) { Image(systemName: "music.note").font(.system(size: 26, weight: .ultraLight)); if address != nil && !resolved { ProgressView().controlSize(.mini).tint(.white.opacity(0.3)) } }.foregroundStyle(.white.opacity(0.16)) }
            }.clipShape(RoundedRectangle(cornerRadius: round ? geo.size.width / 2 : 5))
        }
        .task(id: address) {
            resolved = false; imageAddress = address; image = seed ?? BrowseArtworkCache.shared.cached(address)
            for attempt in 0..<3 {
                let value = await BrowseArtworkCache.shared.image(address)
                guard !Task.isCancelled else { return }
                if let value { image = value; resolved = true; return }
                guard let address, let url = URL(string: address), ArtworkPolicy.permits(url), attempt < 2 else { break }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
            resolved = true
        }
        .accessibilityHidden(true)
    }
}
struct BrowseView: View {
    @Bindable var model: PlayerSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var position = PanoramaPosition()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PanoramaBackdrop(position: position, accent: model.accent)
                VStack(alignment: .leading, spacing: 0) {
                    toolbar
                    masthead(width: geometry.size.width)
                    pivots
                    GeometryReader { viewport in panorama(size: viewport.size) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    PanoramaRail(position: position, accent: model.accent).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .auralisSearch)) { _ in searchFocused = true }
        .onChange(of: reduceMotion, initial: true) { position.reduceMotion = reduceMotion }
        .task { await model.prepareBrowse() }
    }
    private var route: String { model.browse?.route ?? model.browse?.path ?? "/" }
    private var pageTitle: String {
        if let title = model.loadingPage { return title }
        if let detail = model.browse?.detail, !detail.title.isEmpty { return detail.title }
        if model.browse?.path == "/search" { return "search" }
        switch model.destination { case .home: return "music"; case .explore: return "discover"; case .library: return "library" }
    }
    private var toolbar: some View {
        HStack(spacing: 22) {
            HStack(spacing: 0) {
                Text("auralis").font(.system(size: 22, weight: .bold)).tracking(-1.2)
                Text(".").font(.system(size: 26, weight: .black)).foregroundStyle(model.accent)
            }
            Button { model.browseBack() } label: { Image(systemName: "arrow.left").frame(width: 28, height: 32) }.buttonStyle(.plain).help("Back")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryInk)
                TextField("search your music", text: $model.searchText)
                    .textFieldStyle(.plain).font(.system(size: 17, weight: .medium)).focused($searchFocused).onSubmit { model.search() }
                    .accessibilityLabel("Search YouTube Music")
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search")
                } else { Text("⌘K").font(.system(size: 10)).foregroundStyle(Color.secondaryInk) }
            }.padding(.horizontal, 14).padding(.vertical, 10).background(Color.tile, in: RoundedRectangle(cornerRadius: 7)).frame(maxWidth: 380)
            Spacer(minLength: 0)
            if model.browsingBusy { ProgressView().controlSize(.mini) }
            Menu {
                ForEach(model.browse?.library ?? []) { item in Button(item.title) { model.select(item) } }
                Divider()
                Button("Open YouTube Music") { model.openWebsite() }
            } label: { Label("Playlists", systemImage: "square.stack") }.menuStyle(.borderlessButton).fixedSize().font(.system(size: 13, weight: .medium)).accessibilityLabel("Your playlists")
            Button { model.account() } label: { Image(systemName: model.signedIn ? "person.crop.circle" : "person.crop.circle.badge.plus").font(.system(size: 20)) }
                .buttonStyle(.plain).accessibilityLabel(model.signedIn ? "Account" : "Sign in")
            Button { model.fullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13)) }.buttonStyle(.plain).help("Full screen")
        }.padding(.horizontal, 36).frame(height: 58)
            .background { ChromePattern(accent: model.accent) }
    }
    private func masthead(width: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 20) {
            Text(pageTitle).font(.system(size: min(132, width * 0.116), weight: .bold)).tracking(-6)
                .lineLimit(1).minimumScaleFactor(0.5)
                .modifier(PanoramaTitleOffset(position: position))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if model.browse?.detail == nil {
                Text("YOUR MUSIC.\nA LITTLE MORE SPACE.").font(.system(size: 9, weight: .semibold)).tracking(1.8).lineSpacing(4)
                    .foregroundStyle(model.accent).padding(.bottom, 14)
            }
        }.padding(.horizontal, 36).frame(height: 126, alignment: .bottom).clipped()
    }
    private var pivots: some View {
        HStack(spacing: 26) {
            pivot("for you", destination: .home)
            pivot("discover", destination: .explore)
            pivot("library", destination: .library)
            Button { model.stage = true } label: { HStack(spacing: 8) { Text("now playing"); Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .medium)) } }
                .buttonStyle(.plain).foregroundStyle(Color.secondaryInk)
            Spacer(minLength: 0)
        }.font(.system(size: 31, weight: .semibold)).tracking(-1.2)
            .padding(.horizontal, 36).frame(height: 70, alignment: .center)
    }
    private func pivot(_ title: String, destination: BrowseDestination) -> some View {
        let selected = model.destination == destination && model.browse?.detail == nil && model.browse?.path != "/search"
        return Button { model.navigate(destination) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).foregroundStyle(selected ? Color.warmWhite : Color.secondaryInk.opacity(0.6))
                Rectangle().fill(selected ? model.accent : .clear).frame(height: 3)
            }.fixedSize()
        }.buttonStyle(.plain).accessibilityLabel(title.capitalized).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func panorama(size: CGSize) -> some View {
        let panels = makePanels(viewport: size)
        let total = panels.reduce(CGFloat(36)) { $0 + $1.width + 44 }
        return PanoramaViewport(position: position, size: size, contentWidth: total, resetKey: route + "|" + (model.loadingPage ?? "ready"), moveRequest: position.request, requestedOffset: position.target) {
            HStack(alignment: .top, spacing: 44) {
                ForEach(panels) { panel in
                    PanoramaPanel(origin: panel.origin, width: panel.width) {
                        panelView(panel, height: size.height)
                    }
                }
            }.padding(.horizontal, 36).frame(width: max(size.width, total), height: size.height, alignment: .topLeading)
                .foregroundStyle(Color.warmWhite).environment(position)
        }.frame(height: size.height)
    }
    private struct Panel: Identifiable {
        let id: String
        var origin: CGFloat = 0
        let width: CGFloat
        let title: String
        let index: Int
        var items: [BrowseItem] = []
        var detail: BrowseDetail?
        var featured = false
        var message: String?
        var loading = false
    }
    private func makePanels(viewport: CGSize) -> [Panel] {
        let leadWidth = max(640, min(1040, viewport.width * 0.82))
        if model.loadingPage != nil || ((model.loading || model.browsingBusy) && model.browse?.shelves.isEmpty != false) {
            return [Panel(id: "loading", origin: 36, width: max(640, viewport.width - 72), title: model.loadingPage ?? "your music", index: 0, loading: true)]
        }
        var result: [Panel] = []
        if let error = model.browseError {
            result.append(Panel(id: "error", width: leadWidth, title: "a little patience.", index: 0, message: error))
        }
        if let catalog = model.browse, !catalog.shelves.isEmpty {
            if catalog.path == "/" {
                // Prefer actual published image sources for live faces, keeping every catalog
                // item directly accessible in the subsequent section panels.
                let cards = (catalog.shelves.first?.items ?? []).filter { $0.artwork.flatMap(URL.init(string:)).map(ArtworkPolicy.permits) == true }
                result.append(Panel(id: "featured", width: leadWidth, title: "in rotation", index: result.count, items: Array(cards.prefix(30)), featured: true))
            } else if let detail = catalog.detail {
                result.append(Panel(id: "detail", width: leadWidth, title: detail.kind, index: result.count, detail: detail))
            }
            let songRows = max(2, min(4, Int((viewport.height - 76) / 84)))
            for shelf in catalog.shelves {
                let songs = shelf.items.allSatisfy { $0.kind == "song" }
                let capacity = songs ? songRows * 2 : 6
                for start in stride(from: 0, to: shelf.items.count, by: capacity) {
                    let chunk = Array(shelf.items.dropFirst(start).prefix(capacity))
                    let width = songs ? max(700, min(900, viewport.width * 0.74)) : max(750, min(1000, viewport.width * 0.82))
                    result.append(Panel(id: shelf.id + ":\(start)", width: width, title: shelf.title, index: result.count, items: chunk))
                }
            }
        }
        if result.isEmpty {
            result = [Panel(id: "empty", width: leadWidth, title: model.signedIn ? "room to explore." : "make yourself at home.", index: 0,
                message: model.signedIn ? "This page is available in the full YouTube Music view." : "Sign in with Google to bring your music into Auralis.")]
        }
        var x: CGFloat = 36
        for index in result.indices { result[index].origin = x; x += result[index].width + 44 }
        return result
    }
    private func panelView(_ panel: Panel, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(String(format: "%02d", panel.index + 1)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(model.accent)
                Text(panel.title.lowercased()).font(.system(size: panel.featured || panel.detail != nil ? 24 : 43, weight: .bold)).tracking(-1.6).lineLimit(1)
                    .modifier(PanoramaSectionOffset())
                Spacer()
                if !panel.items.isEmpty { Text(String(format: "%02d", panel.items.count)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.secondaryInk) }
            }.frame(height: 48)
            if panel.loading { skeleton }
            else if let message = panel.message { messagePanel(message) }
            else if let detail = panel.detail { collectionHeader(detail) }
            else if panel.featured { hero(panel.items) }
            else if panel.items.allSatisfy({ $0.kind == "song" }) {
                let count = (panel.items.count + 1) / 2
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 6) { ForEach(Array(panel.items.prefix(count))) { BrowseTrackRow(item: $0, model: model) }; Spacer(minLength: 0) }
                    VStack(spacing: 6) { ForEach(Array(panel.items.dropFirst(count))) { BrowseTrackRow(item: $0, model: model) }; Spacer(minLength: 0) }
                }
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) { ForEach(Array(panel.items.prefix(3))) { BrowseCard(item: $0, model: model) }; if panel.items.count < 3 { Spacer(minLength: 0) } }
                    if panel.items.count > 3 { HStack(alignment: .top, spacing: 12) { ForEach(Array(panel.items.dropFirst(3))) { BrowseCard(item: $0, model: model) }; if panel.items.count < 6 { Spacer(minLength: 0) } } }
                }
            }
        }.frame(height: height - 8, alignment: .top).modifier(MusicArrival(order: panel.index))
    }
    private func hero(_ items: [BrowseItem]) -> some View {
        let groups = (0..<5).map { slot in Array(items.enumerated().filter { $0.offset % 5 == slot }.map(\.element)) }
        return HStack(spacing: 9) {
            LiveMusicTile(items: groups[0], ordinal: 0, compact: false, model: model).frame(maxWidth: .infinity)
            VStack(spacing: 9) {
                HStack(spacing: 9) {
                    LiveMusicTile(items: groups[1], ordinal: 1, compact: true, model: model)
                    LiveMusicTile(items: groups[2], ordinal: 2, compact: true, model: model)
                }
                HStack(spacing: 9) {
                    LiveMusicTile(items: groups[3], ordinal: 3, compact: true, model: model)
                    LiveMusicTile(items: groups[4], ordinal: 4, compact: true, model: model)
                }
            }.frame(maxWidth: .infinity)
        }.frame(maxHeight: .infinity)
    }
    private func collectionHeader(_ detail: BrowseDetail) -> some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 28) {
                BrowseArtwork(address: detail.artwork).frame(width: min(geometry.size.height, 330), height: min(geometry.size.height, 330))
                VStack(alignment: .leading, spacing: 20) {
                    Text(detail.title).font(.system(size: 38, weight: .bold)).tracking(-1.4).lineLimit(3)
                    Text(detail.subtitle).font(.system(size: 17, weight: .medium)).foregroundStyle(Color.secondaryInk).lineLimit(4)
                    HStack(spacing: 12) {
                        ForEach(detail.actions.filter { ["play", "shuffle"].contains($0.kind) }) { action in
                            Button { model.open(action) } label: { Label(action.title.lowercased(), systemImage: action.kind == "shuffle" ? "shuffle" : "play.fill") }.buttonStyle(QuietButton())
                        }
                    }.font(.system(size: 18, weight: .semibold))
                    ForEach(detail.actions.filter { $0.kind == "artist" }) { link in
                        Button(link.title) { model.open(link) }.buttonStyle(.plain).foregroundStyle(model.accent).font(.system(size: 19, weight: .medium))
                    }
                    Text("SCROLL FOR THE MUSIC →").font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(Color.secondaryInk)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
            }
        }
    }
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) { ProgressView().controlSize(.small); Text("bringing your music in…").font(.system(size: 28, weight: .semibold)) }.foregroundStyle(Color.secondaryInk)
            HStack(spacing: 10) { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 9).fill(Color.tile).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) } } }
        }.frame(maxHeight: .infinity)
    }
    private func messagePanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(message).font(.system(size: 28, weight: .medium)).foregroundStyle(Color.secondaryInk).frame(maxWidth: 600, alignment: .leading)
            HStack(spacing: 16) {
                if !model.signedIn { Button("Sign in with Google") { model.signIn() }.buttonStyle(QuietButton()) }
                Button("Open YouTube Music") { model.openWebsite() }.buttonStyle(QuietButton())
            }.font(.system(size: 17, weight: .semibold))
            Spacer()
        }.padding(.top, 15)
    }
}

private struct BrowseTrackRow: View {
    let item: BrowseItem
    @Bindable var model: PlayerSession
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 12) {
            Button { model.select(item) } label: { BrowseArtwork(address: item.artwork).frame(width: 64, height: 64) }.buttonStyle(.plain).accessibilityLabel("Play \(item.title)")
            VStack(alignment: .leading, spacing: 5) {
                Button(item.title) { model.select(item) }.buttonStyle(.plain).font(.system(size: 20, weight: .semibold)).tracking(-0.5).lineLimit(1)
                if let artist = item.links?.first(where: { $0.kind == "artist" }) {
                    Button(artist.title) { model.open(artist) }.buttonStyle(.plain).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.secondaryInk).lineLimit(1)
                } else { Text(item.subtitle).font(.system(size: 14)).foregroundStyle(Color.secondaryInk).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { model.startRadio(item) } label: { Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 14)) }
                .buttonStyle(.plain).foregroundStyle(model.accent).opacity(hovered ? 1 : 0.5)
                .accessibilityLabel("Start radio from \(item.title)").help("Start a mix in YouTube Music").disabled(model.browsingBusy)
            MusicItemMenu(item: item, model: model).disabled(model.browsingBusy)
        }.padding(7).frame(height: 78).background(hovered ? Color.raised : Color.tile.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }.contextMenu { MusicItemActions(item: item, model: model) }
    }
}
private struct BrowseCard: View {
    let item: BrowseItem
    @Bindable var model: PlayerSession
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.select(item) } label: {
                ZStack(alignment: .bottomLeading) {
                    BrowseArtwork(address: item.artwork)
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.kind.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(model.accent)
                        Text(item.title).font(.system(size: 25, weight: .bold)).tracking(-0.9).foregroundStyle(.white).lineLimit(2)
                    }.padding(13)
                    if hovered { Image(systemName: item.kind == "song" ? "play.fill" : "arrow.up.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(14) }
                }.clipShape(RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.title)
            HStack(spacing: 8) {
                if let artist = item.links?.first(where: { $0.kind == "artist" }) {
                    Button(artist.title) { model.open(artist) }.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.secondaryInk).lineLimit(1)
                } else { Text(item.subtitle).font(.system(size: 13)).foregroundStyle(Color.secondaryInk).lineLimit(1) }
                Spacer(minLength: 0); MusicItemMenu(item: item, model: model)
            }.frame(height: 20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(hovered && !reduceMotion ? 1.012 : 1)
            .onHover { hovered = $0 }.animation(reduceMotion ? nil : MusicMotion.settle, value: hovered)
            .contextMenu { MusicItemActions(item: item, model: model) }
    }
}
extension Notification.Name { static let auralisSearch = Notification.Name("AuralisFocusSearch") }
