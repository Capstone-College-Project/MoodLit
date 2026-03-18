//
//  PlaylistEditorView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.


import SwiftUI

struct PlaylistEditorView: View {
    let playlistID: UUID
    var onSave: () -> Void

    @StateObject private var store = PlaylistStore.shared
    @State private var expandedID: UUID? = nil
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryColor = Color.gold
    @State private var newIntensity1 = "Low intensity"
    @State private var newIntensity2 = "Medium intensity"
    @State private var newIntensity3 = "High intensity"

    private var playlistIdx: Int? {
        store.playlists.firstIndex(where: { $0.id == playlistID })
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            if let idx = playlistIdx {
                List {
                    ForEach(store.playlists[idx].emotions.indices, id: \.self) { eIdx in
                        if eIdx < store.playlists[idx].emotions.count {
                            EmotionCategorySection(
                                emotion: $store.playlists[idx].emotions[eIdx],
                                isExpanded: expandedID == store.playlists[idx].emotions[eIdx].id,
                                onTapHeader: {
                                    let id = store.playlists[idx].emotions[eIdx].id
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        expandedID = expandedID == id ? nil : id
                                    }
                                },
                                onSave: {
                                    store.save()
                                    onSave()
                                }
                            )
                            .padding()
                            .background(Color.surface)
                            .cornerRadius(12)
                            .listRowBackground(Color.bg)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if expandedID == store.playlists[idx].emotions[eIdx].id {
                                        expandedID = nil
                                    }
                                    store.playlists[idx].emotions.remove(at: eIdx)
                                    store.save()
                                    onSave()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    Button {
                        newCategoryName = ""
                        newCategoryColor = Color.gold
                        newIntensity1 = "Low intensity"
                        newIntensity2 = "Medium intensity"
                        newIntensity3 = "High intensity"
                        showAddCategory = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color.gold)
                                .font(.system(size: 18))
                            Text("Add Category")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color.gold)
                            Spacer()
                        }
                        .padding(28)
                        .background(Color.surface)
                        .cornerRadius(12)
                    }
                    .listRowBackground(Color.bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .scrollContentBackground(.hidden)
                .background(Color.bg)
            }
        }
        .navigationTitle(store.playlists.first(where: { $0.id == playlistID })?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.bg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showAddCategory) {
            AddCategorySheet(
                name: $newCategoryName,
                color: $newCategoryColor,
                intensity1: $newIntensity1,
                intensity2: $newIntensity2,
                intensity3: $newIntensity3
            ) {
                guard let idx = playlistIdx else { return }
                let cat = EmotionCategory(
                    categoryName: newCategoryName.trimmingCharacters(in: .whitespaces),
                    colorHex: newCategoryColor.toHex() ?? "#888888",
                    intensity1: Intensity(nameDescription: newIntensity1),
                    intensity2: Intensity(nameDescription: newIntensity2),
                    intensity3: Intensity(nameDescription: newIntensity3)
                )
                store.playlists[idx].emotions.append(cat)
                store.save()
                onSave()
                showAddCategory = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedID = cat.id
                    }
                }
            }
        }
    }
}
