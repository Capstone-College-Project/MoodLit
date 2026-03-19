//
//  TrackSwapSheet.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/18/26.
//


import SwiftUI
import UniformTypeIdentifiers

struct TrackSwapSheet: View {
    let bookID: UUID
    let tag: SceneTag
    let playlist: Playlist?

    @ObservedObject private var library = LibraryManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false

    // Collect all available tracks from the playlist
    private var availableTracks: [(track: MusicFile, label: String)] {
        guard let playlist else { return [] }
        var tracks: [(track: MusicFile, label: String)] = []

        for category in playlist.emotions {
            if let m = category.intensity1.music {
                tracks.append((m, "\(category.categoryName) · Low"))
            }
            if let m = category.intensity2.music {
                tracks.append((m, "\(category.categoryName) · Medium"))
            }
            if let m = category.intensity3.music {
                tracks.append((m, "\(category.categoryName) · High"))
            }
        }

        // Deduplicate by fileName
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.track.fileName).inserted }
    }

    private var currentTrack: MusicFile? {
        if let override = tag.musicOverride { return override }
        guard let playlist else { return nil }
        guard let category = playlist.emotions.first(where: { $0.id == tag.emotionCategoryID }) else { return nil }
        switch tag.intensityLevel {
        case 1: return category.intensity1.music
        case 2: return category.intensity2.music
        default: return category.intensity3.music
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Current track
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CURRENT TRACK")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color.text2)
                                .tracking(1)

                            HStack(spacing: 10) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.gold)
                                Text(currentTrack?.title ?? "No track assigned")
                                    .font(.subheadline)
                                    .foregroundColor(Color.text)
                                Spacer()
                                if tag.musicOverride != nil {
                                    Text("Override")
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(Color.gold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.gold.opacity(0.12))
                                        .cornerRadius(6)
                                }
                            }
                            .padding(12)
                            .background(Color.surface)
                            .cornerRadius(10)
                        }

                        // Playlist tracks
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FROM PLAYLIST")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color.text2)
                                .tracking(1)

                            if availableTracks.isEmpty {
                                Text("No tracks in this playlist yet.")
                                    .font(.caption)
                                    .foregroundColor(Color.text2)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.surface)
                                    .cornerRadius(10)
                            } else {
                                ForEach(availableTracks, id: \.track.fileName) { item in
                                    let isSelected = currentTrack?.fileName == item.track.fileName
                                    Button {
                                        applyOverride(item.track)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 12))
                                                .foregroundColor(isSelected ? Color.gold : Color.text2)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.track.title)
                                                    .font(.subheadline)
                                                    .foregroundColor(Color.text)
                                                Text(item.label)
                                                    .font(.caption2)
                                                    .foregroundColor(Color.text2)
                                            }
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(Color.gold)
                                            }
                                        }
                                        .padding(12)
                                        .background(isSelected ? Color.gold.opacity(0.08) : Color.surface)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Color.gold.opacity(0.3) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Upload custom
                        VStack(alignment: .leading, spacing: 8) {
                            Text("UPLOAD CUSTOM")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color.text2)
                                .tracking(1)

                            Button {
                                showFilePicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundColor(Color.gold)
                                        .font(.system(size: 13))
                                    Text("Upload a different track")
                                        .font(.subheadline)
                                        .foregroundColor(Color.gold)
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color.surface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gold.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Remove override
                        if tag.musicOverride != nil {
                            Button {
                                removeOverride()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 12))
                                    Text("Reset to playlist default")
                                        .font(.subheadline)
                                }
                                .foregroundColor(Color.text2)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.surface)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Swap Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
        }
    }

    // MARK: - Actions

    private func applyOverride(_ track: MusicFile) {
        var updated = tag
        updated.musicOverride = track
        SceneTagEngine.save(updated, to: bookID)
        dismiss()
    }

    private func removeOverride() {
        var updated = tag
        updated.musicOverride = nil
        SceneTagEngine.save(updated, to: bookID)
        dismiss()
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let musicDir = docs.appendingPathComponent("Music")
            try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
            let dest = musicDir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.copyItem(at: url, to: dest)
            }
            let track = MusicFile(
                title: url.deletingPathExtension().lastPathComponent,
                fileName: url.lastPathComponent
            )
            applyOverride(track)
        } catch {
            print("❌ Track import: \(error)")
        }
    }
}
