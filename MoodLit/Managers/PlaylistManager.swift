//
//  PlaylistManager.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 4/27/26.
//


import SwiftUI
import Combine

@MainActor
class PlaylistManager: ObservableObject {

    static let shared = PlaylistManager()
    private init() { load() }

    @Published var playlists: [Playlist] = []

    // MARK: - CRUD

    func add(_ playlist: Playlist) {
        playlists.append(playlist)
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = name
        save()
    }

    func update(_ playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i] = playlist
        save()
    }

    func delete(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }
    
    func delete(_ playlist: Playlist) {
        delete(playlist.id)
    }

    func delete(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        save()
    }

    func playlist(for id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    // MARK: - Persistence

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playlists.json")
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("❌ PlaylistManager save error: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        playlists = decoded
        print("✅ Loaded \(playlists.count) playlists")
    }
}
