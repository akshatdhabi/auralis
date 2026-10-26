import AppKit
import MediaPlayer

/// macOS arbitrates media-key ownership with the browser and other active players.
@MainActor final class SystemMediaController {
    private weak var model: PlayerSession?
    private let center = MPRemoteCommandCenter.shared()
    private var targets: [(MPRemoteCommand, Any)] = []
    init(model: PlayerSession) {
        self.model = model
        bind(center.playCommand, action: .play)
        bind(center.pauseCommand, action: .pause)
        bind(center.nextTrackCommand, action: .nexttrack)
        bind(center.previousTrackCommand, action: .previoustrack)
        let toggle = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Self.onMain {
                guard let model = self?.model, model.fresh, model.supports(model.isPlaying ? .pause : .play) else { return .noSuchContent }
                model.togglePlayback(); return .success
            }
        }
        targets.append((center.togglePlayPauseCommand, toggle))
        let seek = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            Self.onMain {
                guard let event = event as? MPChangePlaybackPositionCommandEvent,
                      let model = self?.model, model.supports(.seekto) else { return .commandFailed }
                model.command(.seekto, seekTime: event.positionTime); return .success
            }
        }
        targets.append((center.changePlaybackPositionCommand, seek))
        clear()
    }
    nonisolated private static func onMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated { body() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
    }
    private func bind(_ command: MPRemoteCommand, action: PlaybackAction) {
        let target = command.addTarget { [weak self] _ in
            Self.onMain {
                guard let model = self?.model, model.supports(action) else { return .noSuchContent }
                model.command(action); return .success
            }
        }
        targets.append((command, target))
    }
    func update(snapshot: PlaybackSnapshot, position: Double?, artwork: NSImage?) {
        var info: [String: Any] = [MPMediaItemPropertyTitle: snapshot.title, MPMediaItemPropertyArtist: snapshot.artist,
                                 MPMediaItemPropertyAlbumTitle: snapshot.album,
                                 MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? (snapshot.rate) : 0,
                                 MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if let duration = snapshot.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let position { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position }
        if let artwork { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snapshot.title.isEmpty ? .unknown : (snapshot.isPlaying ? .playing : .paused)
        center.playCommand.isEnabled = snapshot.actions.contains("play")
        center.pauseCommand.isEnabled = snapshot.actions.contains("pause")
        center.togglePlayPauseCommand.isEnabled = snapshot.actions.contains(snapshot.isPlaying ? "pause" : "play")
        center.nextTrackCommand.isEnabled = snapshot.actions.contains("nexttrack")
        center.previousTrackCommand.isEnabled = snapshot.actions.contains("previoustrack")
        center.changePlaybackPositionCommand.isEnabled = snapshot.actions.contains("seekto") && snapshot.duration != nil
    }
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        targets.forEach { $0.0.isEnabled = false }
    }
    func shutdown() {
        clear()
        targets.forEach { $0.0.removeTarget($0.1) }
        targets.removeAll()
    }
}
