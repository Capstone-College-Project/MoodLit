//  Playliststore.swift
//  MoodLit
//  Created by Anthony Chang Martinez on 3/8/26.
//  Handles saving and loading playlists from disk. No class needed.


import SwiftUI
import Combine

class PlaylistStore: ObservableObject {
    @Published var playlists: [Playlist] = []

    static let shared = PlaylistStore()

    private init() {
        load()
    }

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlists.json")
    }

    func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        playlists = decoded
    }

    func add(_ playlist: Playlist) {
        playlists.append(playlist)
        save()
    }

    func delete(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func update(_ playlist: Playlist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx] = playlist
        save()
    }
}

// Keep these free functions for any legacy call sites
func loadPlaylists() -> [Playlist] { PlaylistStore.shared.playlists }
func savePlaylists(_ playlists: [Playlist]) {
    PlaylistStore.shared.playlists = playlists
    PlaylistStore.shared.save()
}
