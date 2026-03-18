//
//  PlaylistListView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.

import SwiftUI
import Combine

struct PlaylistListView: View {
    @StateObject private var store = PlaylistStore.shared
    @State private var editingPlaylist: Playlist? = nil
    @State private var showNameSheet = false
    @State private var showEditor = false
    @State private var newName = ""
    @State private var deleteTarget: Playlist? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                if store.playlists.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newName = ""
                        showNameSheet = true
                    } label: {
                        Image(systemName: "plus").foregroundColor(Color.gold)
                    }
                }
            }
            .sheet(isPresented: $showNameSheet, onDismiss: {
                if editingPlaylist != nil { showEditor = true }
            }) {
                PlaylistNameSheet(name: $newName, title: "New Playlist") {
                    let p = Playlist(name: newName.trimmingCharacters(in: .whitespaces))
                    store.add(p)
                    editingPlaylist = p
                    showNameSheet = false
                }
            }
            .navigationDestination(isPresented: $showEditor) {
                if let id = editingPlaylist?.id {
                    PlaylistEditorView(playlistID: id) {
                        store.save()
                    }
                    .onDisappear {
                        store.save()
                        editingPlaylist = nil
                    }
                }
            }
            .confirmationDialog(
                "Delete \"\(deleteTarget?.name ?? "")\"?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let t = deleteTarget { store.delete(t) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(store.playlists.indices, id: \.self) { idx in
                Button {
                    editingPlaylist = store.playlists[idx]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showEditor = true
                    }
                } label: {
                    PlaylistRow(playlist: store.playlists[idx])
                        .padding(12)
                        .background(Color.surface)
                        .cornerRadius(12)
                }
                .listRowBackground(Color.bg)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = store.playlists[idx]
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        newName = store.playlists[idx].name
                        editingPlaylist = store.playlists[idx]
                        showNameSheet = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 52))
                .foregroundColor(Color.text2)

            Text("No Playlists Yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(Color.text)

            Text("Create a playlist to pair music\nwith your reading experience.")
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)

            Button {
                newName = ""
                showNameSheet = true
            } label: {
                Label("Create Playlist", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.bg)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.gold)
                    .cornerRadius(22)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    PlaylistListView()
}
