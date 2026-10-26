import SwiftUI

struct MusicItemActions: View {
    let item: BrowseItem
    @Bindable var model: PlayerSession
    var body: some View {
        Button(item.kind == "song" ? "Play \(item.title)" : "Open \(item.title)") { model.select(item) }
        ForEach(item.links ?? []) { link in
            Button("Go to \(link.kind == "item" ? "collection" : link.kind): \(link.title)") { model.open(link) }
        }
        Divider()
        Button("Start radio") { model.startRadio(item) }
    }
}
struct MusicItemMenu: View {
    let item: BrowseItem
    @Bindable var model: PlayerSession
    var body: some View {
        Menu { MusicItemActions(item: item, model: model) } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for \(item.title)")
    }
}

/// Artwork-first live tile. New, fully loaded artwork pushes softly into the
/// existing frame; the card never rotates or exposes a synthetic metadata back.
struct LiveMusicTile: View {
    let items: [BrowseItem]
    let ordinal: Int
    let compact: Bool
    @Bindable var model: PlayerSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var hovered = false
    @State private var faceImage: NSImage?
    @State private var faceID: String?
    @State private var floating = false
    private var moving: Bool { !reduceMotion && model.active && !model.lowPower }
    private var taskKey: String { "\(moving)-" + items.map(\.id).joined(separator: ",") }
    var body: some View {
        if !items.isEmpty {
            let item = items[index % items.count]
            Button { model.select(item) } label: {
                GeometryReader { geo in
                    ZStack(alignment: .bottomLeading) {
                        ZStack {
                            BrowseArtwork(address: item.artwork, seed: faceID == item.id ? faceImage : nil)
                                .scaleEffect(floating && moving ? 1.018 : 1)
                                .animation(moving ? .easeInOut(duration: 9).repeatForever(autoreverses: true) : nil, value: floating)
                                .id(item.id)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity.combined(with: .offset(y: -8))))
                        }.clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.04), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                            Text(item.kind == "item" ? "COLLECTION" : item.kind.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.8).opacity(0.7)
                            Text(item.title).font(.system(size: compact ? 26 : 49, weight: .bold)).tracking(compact ? -1 : -1.8).lineLimit(2)
                            if !compact { Text(item.subtitle).font(.system(size: 14, weight: .medium)).lineLimit(1).opacity(0.7) }
                        }.contentTransition(.opacity).padding(compact ? 15 : 25).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                        if hovered {
                            Image(systemName: item.kind == "song" ? "play.fill" : "arrow.up.right")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(.black.opacity(0.25), in: Circle())
                                .position(x: geo.size.width - 26, y: 26)
                        }
                    }.clipped()
                }.contentShape(Rectangle())
            }.buttonStyle(TilePressStyle(reduceMotion: reduceMotion))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(hovered ? 0.16 : 0.06), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                .onHover { hovered = $0 }
                .contextMenu { MusicItemActions(item: item, model: model) }
                .accessibilityLabel("\(item.title), \(item.subtitle)")
                .modifier(MusicArrival(order: ordinal))
                .task(id: taskKey) {
                    floating = moving
                    guard moving, items.count > 1 else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(4500 + ordinal * 1900))
                        while !Task.isCancelled {
                            let nextIndex = (index + 1) % items.count
                            let nextFace = await BrowseArtworkCache.shared.image(items[nextIndex].artwork)
                            try Task.checkCancellation()
                            if let nextFace {
                                withAnimation(MusicMotion.settle) { faceImage = nextFace; faceID = items[nextIndex].id; index = nextIndex }
                            }
                            try await Task.sleep(for: .milliseconds(12500 + ordinal * 1700))
                        }
                    } catch { }
                }
        }
    }
}
private struct TilePressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
