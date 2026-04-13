import SwiftUI

// MARK: - MusicSourcePickerSheet
//
// Lets the user choose how a book plays music:
//   • Playlist  — uses tracks from an assigned Playlist
//   • Stream    — uses AI-generated music prompts via LatentScore (stubbed for now)
//
// Both modes require an assigned playlist. Stream mode falls back to playlist
// tracks when a scene has no AI-generated music prompt.

struct MusicSourcePickerSheet: View {
    let bookID: UUID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = LibraryManager.shared
    
    @State private var showPlaylistPicker = false
    
    private var book: Book? {
        library.books.first { $0.id == bookID }
    }
    
    private var assignedPlaylist: Playlist? {
        guard let pid = book?.assignedPlaylistID else { return nil }
        return PlaylistStore.shared.playlists.first { $0.id == pid }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        headerSection
                        
                        // ── Music Source Cards ──
                        VStack(spacing: 12) {
                            sourceCard(.playlist)
                            sourceCard(.stream)
                        }
                        
                        // ── Assigned Playlist Section ──
                        playlistSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Music Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.gold)
                }
            }
            .sheet(isPresented: $showPlaylistPicker) {
                if let book {
                    PlaylistPickerSheet(book: book)
                }
            }
        }
        .background(Color.bg)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How should this book play music?")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color.text)
            
            Text("You can switch between modes anytime — your AI analysis works for both.")
                .font(.caption)
                .foregroundColor(Color.text2)
        }
    }
    
    // MARK: - Source Card
    
    @ViewBuilder
    private func sourceCard(_ source: MusicSource) -> some View {
        let isSelected = book?.musicSource == source
        
        Button {
            guard let book else { return }
            if book.musicSource != source {
                library.setMusicSource(source, for: bookID)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: source.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? Color.gold : Color.text2)
                        .frame(width: 36, height: 36)
                        .background(
                            (isSelected ? Color.gold : Color.text2)
                                .opacity(0.12)
                        )
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.text)
                        
                        if source == .stream {
                            Text("Coming soon")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(Color.gold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gold.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.gold)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 20))
                            .foregroundColor(Color.text2.opacity(0.4))
                    }
                }
                
                Text(source.description)
                    .font(.caption)
                    .foregroundColor(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Stream mode shows a placeholder note
                if source == .stream && isSelected {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.gold)
                        Text("LatentScore integration is coming. Scenes will use playlist tracks until streaming is enabled.")
                            .font(.caption2)
                            .foregroundColor(Color.text2)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gold.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.gold.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Playlist Section
    
    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 12))
                    .foregroundColor(Color.text2)
                Text("ASSIGNED PLAYLIST")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.text2)
                    .tracking(1)
            }
            
            if let playlist = assignedPlaylist {
                Button {
                    showPlaylistPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundColor(Color.gold)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color.text)
                            Text("\(playlist.emotions.count) emotion categories")
                                .font(.caption2)
                                .foregroundColor(Color.text2)
                        }
                        
                        Spacer()
                        
                        Text("Change")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.gold)
                    }
                    .padding(14)
                    .background(Color.surface)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showPlaylistPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No playlist assigned")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color.text)
                            Text("Tap to choose one — required for both modes")
                                .font(.caption2)
                                .foregroundColor(Color.text2)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color.text2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Helper text below the playlist row
            Text(playlistHelperText)
                .font(.caption2)
                .foregroundColor(Color.text2)
                .padding(.horizontal, 4)
        }
    }
    
    private var playlistHelperText: String {
        guard let book else { return "" }
        switch book.musicSource {
        case .playlist:
            return "AI scenes will play tracks from this playlist based on emotion."
        case .stream:
            return "Scenes without AI music prompts will fall back to this playlist."
        }
    }
}