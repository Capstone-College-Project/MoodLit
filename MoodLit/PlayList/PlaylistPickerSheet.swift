//
//  PlaylistPickerSheet.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/11/26.
//
//Called from Library, BookCard. This feature assigns a playlist to a book
//it also allows for removing playlist for book

import SwiftUI

struct PlaylistPickerSheet: View {
    let book: Book

    @ObservedObject private var store = PlaylistStore.shared
    @ObservedObject private var library = LibraryManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                if store.playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(Color.text2)
                        Text("No playlists yet")
                            .font(.headline)
                            .foregroundColor(Color.text)
                        Text("Create a playlist first.")
                            .font(.subheadline)
                            .foregroundColor(Color.text2)
                    }
                } else {
                    //Show list of playlist
                    List {
                        ForEach(store.playlists) { playlist in
                            Button {
                                //Adds Playlist to book,(with playlist id)
                                library.assignPlaylist(playlist.id, to: book.id)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(Color.text)
                                        Text("\(playlist.emotions.count) categories")
                                            .font(.caption)
                                            .foregroundColor(Color.text2)
                                    }
                                    Spacer()
                                    if book.assignedPlaylistID == playlist.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color.gold)
                                    }
                                }
                                .padding(12)
                                .background(
                                    book.assignedPlaylistID == playlist.id
                                        ? Color.gold.opacity(0.08) : Color.surface
                                )
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            book.assignedPlaylistID == playlist.id
                                                ? Color.gold.opacity(0.3) : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .listRowBackground(Color.bg)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }

                        //If Book assigned playlist is not empty, the allow user to remove it
                        if book.assignedPlaylistID != nil {
                            Button {
                                library.assignPlaylist(nil, to: book.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text("Remove Playlist")
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color.surface)
                                .cornerRadius(12)
                            }
                            .listRowBackground(Color.bg)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Assign Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
            }
        }
    }
}
