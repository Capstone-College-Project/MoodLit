// MusicEngine.swift
// MoodLit
//
// Manages music playback, crossfading, and scene-tag-driven track switching.
// Accepts a Playlist and a book's SceneTags, then reacts to line changes.

import Foundation
import AVFoundation
import Combine

class MusicEngine: ObservableObject {

    // MARK: - Published State
    @Published var isPlaying: Bool = false
    @Published var currentTrack: MusicFile? = nil
    @Published var currentCategoryName: String? = nil
    @Published var currentMusicPrompt: String? = nil  // shown in reader when streaming

    // MARK: - Private
    private var currentPlayer: AVAudioPlayer?
    private var fadingOutPlayers: [AVAudioPlayer] = []
    private var fadeTimers: [Timer] = []
    private var sceneTags: [SceneTag] = []
    private var playlist: Playlist?
    private var musicSource: MusicSource = .playlist  // current book's mode
    private var activeTagID: UUID? = nil
    private let crossfadeDuration: Float = 1.5
    var volume: Float = 0.7

    // MARK: - Setup

    /// Loads scene tags, playlist, and the book's music source mode.
    /// Call whenever the book changes, the source mode changes, or tags are updated.
    func load(sceneTags: [SceneTag], playlist: Playlist, musicSource: MusicSource = .playlist) {
        self.sceneTags = sceneTags
        self.playlist = playlist
        self.musicSource = musicSource
    }

    // MARK: - Called by LineTracker / detectActiveLine when marker moves

    func onLineChanged(page: Int, line: Int) {
        guard let tag = findTag(page: page, line: line) else {
            if activeTagID != nil { stop() }
            return
        }
        guard tag.id != activeTagID else { return }
        activeTagID = tag.id

        // 1. User-set music override always wins, regardless of mode
        if let override = tag.musicOverride {
            currentCategoryName = playlist?.emotions
                .first { $0.id == tag.emotionCategoryID }?.categoryName
            currentMusicPrompt = nil
            crossfade(to: override)
            return
        }

        // 2. Branch on the book's music source mode
        switch musicSource {
        case .stream:
            handleStreamMode(tag: tag)
        case .playlist:
            handlePlaylistMode(tag: tag)
        }
    }

    // MARK: - Playlist Mode
    //
    // Looks up the scene's emotion category in the playlist and plays the
    // assigned track for that category + intensity.

    private func handlePlaylistMode(tag: SceneTag) {
        guard let playlist else { return }
        guard let category = playlist.emotions.first(where: { $0.id == tag.emotionCategoryID }) else {
            print("MusicEngine: No category found for ID \(tag.emotionCategoryID)")
            return
        }

        currentCategoryName = category.categoryName
        currentMusicPrompt = nil

        let intensity: Intensity
        switch tag.intensityLevel {
        case 1: intensity = category.intensity1
        case 2: intensity = category.intensity2
        default: intensity = category.intensity3
        }

        guard let music = intensity.music else {
            print("MusicEngine: No track assigned for \(category.categoryName) level \(tag.intensityLevel)")
            return
        }

        crossfade(to: music)
    }

    // MARK: - Stream Mode
    //
    // Uses the scene's AI-generated music prompt to stream from LatentScore.
    // For now this is stubbed — the prompt is logged to console and the engine
    // FALLS BACK to the playlist track for the scene's category.
    //
    // When LatentScore is wired up, replace the fallback with the actual
    // streaming call. The fallback will still trigger if a scene has no prompt
    // (e.g. a manually-created tag, or analysis where Pass 3 failed).

    private func handleStreamMode(tag: SceneTag) {
        // Always update the displayed category for badge / debug purposes
        currentCategoryName = playlist?.emotions
            .first { $0.id == tag.emotionCategoryID }?.categoryName

        guard let prompt = tag.musicPrompt, !prompt.isEmpty else {
            // No music prompt for this scene → fall back to playlist track
            print("🎼 STREAM MODE: No prompt for scene → falling back to playlist")
            currentMusicPrompt = nil
            handlePlaylistMode(tag: tag)
            return
        }

        // We have a prompt — store it and stream
        currentMusicPrompt = prompt
        streamFromLatentScore(prompt: prompt, tag: tag)
    }

    /// STUB: Will eventually call LatentScore AI to stream music for the prompt.
    private func streamFromLatentScore(prompt: String, tag: SceneTag) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎼 LATENTSCORE STREAM — \(prompt.prefix(80))")
        print("   🎭 Category: \(currentCategoryName ?? "Unknown")")
        print("   📊 Intensity: \(tag.intensityLevel)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            do {
                let audioURL = try await LatentScoreService.shared.audioURL(for: prompt)
                
                await MainActor.run {
                    // Check we're still on the same tag — user may have scrolled past
                    guard self.activeTagID == tag.id else {
                        print("🎼 Scene changed while streaming — dropping this audio")
                        return
                    }
                    
                    guard let player = try? AVAudioPlayer(contentsOf: audioURL) else {
                        print("🎼 Could not create player from streamed audio — falling back to playlist")
                        self.handlePlaylistMode(tag: tag)
                        return
                    }
                    
                    let streamedFile = MusicFile(
                        title: "AI: \(self.currentCategoryName ?? "Stream")",
                        fileName: audioURL.lastPathComponent
                    )
                    self.currentTrack = streamedFile
                    self.startCrossfade(with: player, instant: false)
                }
            } catch {
                print("🎼 Stream failed: \(error.localizedDescription) — falling back to playlist")
                await MainActor.run {
                    guard self.activeTagID == tag.id else { return }
                    self.handlePlaylistMode(tag: tag)
                }
            }
        }
    }

    // MARK: - Playback Controls

    func pause() {
        currentPlayer?.pause()
        isPlaying = false
    }

    func resume() {
        currentPlayer?.play()
        isPlaying = true
    }

    func stop() {
        for timer in fadeTimers { timer.invalidate() }
        fadeTimers.removeAll()
        for player in fadingOutPlayers { player.stop() }
        fadingOutPlayers.removeAll()
        currentPlayer?.stop()
        currentPlayer = nil
        isPlaying = false
        currentTrack = nil
        activeTagID = nil
        currentCategoryName = nil
        currentMusicPrompt = nil
    }

    func setVolume(_ value: Float) {
        volume = value.clamped(to: 0...1)
        currentPlayer?.volume = volume
    }

    // MARK: - Private Helpers

    private func findTag(page: Int, line: Int) -> SceneTag? {
        sceneTags.first { $0.contains(page: page, line: line) }
    }

    private func crossfade(to music: MusicFile) {
        if currentTrack?.fileName == music.fileName { return }

        guard let url = music.fileURL else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        
        currentTrack = music
        startCrossfade(with: player, instant: true)  // ← instant on scene change
    }

    private func startCrossfade(with newPlayer: AVAudioPlayer,
                                 instant: Bool = false) {  // ← ADD
        for timer in fadeTimers { timer.invalidate() }
        fadeTimers.removeAll()
        for player in fadingOutPlayers { player.stop() }
        fadingOutPlayers.removeAll()

        if let old = currentPlayer {
            fadingOutPlayers.append(old)
            if instant {
                // Scene change — cut old track immediately
                old.stop()
                fadingOutPlayers.removeAll()
            } else {
                fadeOut(player: old)
            }
        }

        newPlayer.volume = instant ? volume : 0
        newPlayer.numberOfLoops = -1
        newPlayer.play()
        isPlaying = true
        if instant {
            // No fade in — starts immediately at full volume
            newPlayer.volume = volume
        } else {
            fadeIn(player: newPlayer, to: volume)
        }
        currentPlayer = newPlayer
    }

    private func fadeIn(player: AVAudioPlayer, to target: Float) {
        let steps: Float = 30
        let stepVolume = target / steps
        let interval = Double(crossfadeDuration) / Double(steps)
        var current: Float = 0
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            current += stepVolume
            player.volume = min(current, target)
            if current >= target { timer.invalidate() }
        }
        fadeTimers.append(timer)
    }

    private func fadeOut(player: AVAudioPlayer?) {
        guard let player else { return }
        let startVolume = player.volume
        let steps: Float = 30
        let stepVolume = startVolume / steps
        let interval = Double(crossfadeDuration) / Double(steps)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            player.volume = max(player.volume - stepVolume, 0)
            if player.volume <= 0 {
                player.stop()
                timer.invalidate()
                self?.fadingOutPlayers.removeAll { $0 === player }
                self?.fadeTimers.removeAll { $0 === timer }
            }
        }
        fadeTimers.append(timer)
    }
    
    
}
