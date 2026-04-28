//  PlaylistListView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.
//Shows  a list of  all the playlist the user has created

import SwiftUI
import Combine

struct PlaylistListView: View {
    @StateObject private var store = PlaylistManager.shared
    @State private var editingPlaylist: Playlist? = nil
    @State private var showNameSheet = false
    @State private var showEditor = false
    @State private var newName = ""
    @State private var deleteTarget: Playlist? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                //Checks if playlist is empty or not
                if store.playlists.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            //Creates the plus button to add a new playlist
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
                //Calls sheet to create playlist
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
    //Shows  the list of  playlist the user has created
    private var list: some View {
        List {
            //Iterate by index since swipe action would remove ro modify by index
            ForEach(store.playlists.indices, id: \.self) { idx in
                Button {
                    editingPlaylist = store.playlists[idx]
                    //Adds a delay in tapping, to avoid missing the value in editingPlaylist in
                    //navigationDestination
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showEditor = true
                    }
                } label: {
                    //Shows information regarding each playlist
                    PlaylistRow(playlist: store.playlists[idx])
                        .padding(12)
                        .background(Color.surface)
                        .cornerRadius(12)
                }
                .listRowBackground(Color.bg)
                //When user swipe shows to btn:
                //A delete btn and rename btn
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
    //Shows Tells user if there is a playlist
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
        }
        .padding(.horizontal, 40)
    }
}

#Preview {
    PlaylistListView()
}
