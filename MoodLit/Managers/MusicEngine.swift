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

    // MARK: - Private
    private var currentPlayer: AVAudioPlayer?
    private var fadingOutPlayers: [AVAudioPlayer] = []
    private var fadeTimers: [Timer] = []
    private var sceneTags: [SceneTag] = []
    private var playlist: Playlist?
    private var activeTagID: UUID? = nil
    private let crossfadeDuration: Float = 1.5
    var volume: Float = 0.7

    // MARK: - Setup

    func load(sceneTags: [SceneTag], playlist: Playlist) {
        self.sceneTags = sceneTags
        self.playlist = playlist
    }

    // MARK: - Called by LineTracker / detectActiveLine when marker moves

    func onLineChanged(page: Int, line: Int) {
        guard let tag = findTag(page: page, line: line) else {
            if activeTagID != nil { stop() }
            return
        }
        guard tag.id != activeTagID else { return }
        activeTagID = tag.id

        // 1. Check for per-scene music override first
        if let override = tag.musicOverride {
            currentCategoryName = playlist?.emotions
                .first { $0.id == tag.emotionCategoryID }?.categoryName
            crossfade(to: override)
            return
        }

        // 2. Fall back to playlist track for this emotion + intensity
        guard let playlist else { return }

        guard let category = playlist.emotions.first(where: { $0.id == tag.emotionCategoryID })
        else {
            print("MusicEngine: No category found for ID \(tag.emotionCategoryID)")
            return
        }

        currentCategoryName = category.categoryName

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
        // Kill all timers first — prevents ghost audio
        for timer in fadeTimers {
            timer.invalidate()
        }
        fadeTimers.removeAll()

        // Hard-stop everything
        for player in fadingOutPlayers {
            player.stop()
        }
        fadingOutPlayers.removeAll()

        currentPlayer?.stop()
        currentPlayer = nil
        isPlaying = false
        currentTrack = nil
        activeTagID = nil
        currentCategoryName = nil
    }

    func setVolume(_ value: Float) {
        volume = value.clamped(to: 0...1)
        currentPlayer?.volume = volume
    }

    // MARK: - Private

    private func findTag(page: Int, line: Int) -> SceneTag? {
        sceneTags.first {
            $0.page == page &&
            line >= $0.startLine &&
            line <= $0.endLine
        }
    }

    private func crossfade(to music: MusicFile) {
        // Don't restart if already playing this file
        if currentTrack?.fileName == music.fileName { return }

        guard let url = music.fileURL else {
            print("MusicEngine: File not found — \(music.fileName)")
            return
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            print("MusicEngine: Could not create player for \(music.fileName)")
            return
        }
        currentTrack = music
        startCrossfade(with: player)
    }

    private func startCrossfade(with newPlayer: AVAudioPlayer) {
        // 1. Kill ALL pending fade timers — prevents ghost audio stacking
        for timer in fadeTimers {
            timer.invalidate()
        }
        fadeTimers.removeAll()

        // 2. Hard-stop any players still fading out
        for player in fadingOutPlayers {
            player.stop()
        }
        fadingOutPlayers.removeAll()

        // 3. Fade out current player
        if let old = currentPlayer {
            fadingOutPlayers.append(old)
            fadeOut(player: old)
        }

        // 4. Start new player
        newPlayer.volume = 0
        newPlayer.numberOfLoops = -1
        newPlayer.play()
        isPlaying = true
        fadeIn(player: newPlayer, to: volume)
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
