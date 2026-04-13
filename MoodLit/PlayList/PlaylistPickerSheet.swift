import SwiftUI

// MARK: - PlaylistPickerSheet
//
// Lets the user assign a playlist to a book. Opened from MusicSourcePickerSheet
// when the user wants to pick or change the playlist.

struct PlaylistPickerSheet: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlaylistStore.shared
    @ObservedObject private var library = LibraryManager.shared
    
    private var currentBook: Book? {
        library.books.first { $0.id == book.id }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                if store.playlists.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.playlists) { playlist in
                                playlistRow(playlist)
                            }
                            
                            if currentBook?.assignedPlaylistID != nil {
                                Button {
                                    library.assignPlaylist(nil, to: book.id)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(Color.text2)
                                        Text("Remove Assignment")
                                            .foregroundColor(Color.text2)
                                    }
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.surface)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("Choose Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.gold)
                }
            }
        }
        .background(Color.bg)
    }
    
    // MARK: - Playlist Row
    
    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        let isSelected = currentBook?.assignedPlaylistID == playlist.id
        
        Button {
            library.assignPlaylist(playlist.id, to: book.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? Color.gold : Color.text2)
                    .frame(width: 36, height: 36)
                    .background(
                        (isSelected ? Color.gold : Color.text2)
                            .opacity(0.12)
                    )
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.text)
                    
                    Text("\(playlist.emotions.count) emotion categories")
                        .font(.caption2)
                        .foregroundColor(Color.text2)
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
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 50))
                .foregroundColor(Color.text2)
            
            Text("No playlists yet")
                .font(.headline)
                .foregroundColor(Color.text)
            
            Text("Create a playlist first to assign it to this book.")
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}