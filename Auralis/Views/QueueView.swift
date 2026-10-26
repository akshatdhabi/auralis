import SwiftUI

struct QueueView: View {
    @Bindable var model: PlayerSession
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("up next").font(.system(size: 52, weight: .bold)).tracking(-2)
                Spacer()
                if model.queueBusy { ProgressView().controlSize(.mini) }
                Button { model.loadQueue() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh YouTube Music queue")
                Button { model.showQueue = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close queue")
            }.padding(.bottom, 8)
            Text("YOUTUBE MUSIC QUEUE").font(.system(size: 7, weight: .medium)).tracking(1.7).foregroundStyle(Color.secondaryInk).padding(.bottom, 24)
            if let queue = model.queue, !queue.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(queue.items) { item in
                            Button { model.playQueue(item) } label: {
                                HStack(spacing: 10) {
                                    BrowseArtwork(address: item.artwork).frame(width: 62, height: 62)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.system(size: 20, weight: item.current ? .bold : .semibold)).foregroundStyle(item.current ? model.accent : Color.warmWhite).lineLimit(2)
                                        Text(item.subtitle).font(.system(size: 14)).foregroundStyle(Color.secondaryInk).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    if item.current { Image(systemName: "speaker.wave.2.fill").font(.system(size: 9)).foregroundStyle(model.accent) }
                                }.padding(.vertical, 11).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Play queued track: \(item.title)")
                        }
                    }
                }.scrollIndicators(.hidden)
            } else {
                Text(model.queueBusy ? "Loading your queue…" : "The website hasn’t exposed a queue on this page yet.")
                    .font(.system(size: 12)).foregroundStyle(Color.secondaryInk).lineSpacing(4)
                Spacer()
            }
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.vertical, 16)
            Button { model.fullQueue() } label: { Label("View full queue in YouTube Music", systemImage: "arrow.up.right") }
                .font(.system(size: 12)).foregroundStyle(Color.secondaryInk).buttonStyle(.plain)
        }.padding(.horizontal, 4).padding(.top, 4).background(Color.ink.opacity(0.72))
    }
}
