//
//  PlaylistEditorView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.
//Shows which Emotion categories the playlist has,
//Allows  user to  add music  to the category and intensity
//Allows to create a new category

import SwiftUI

struct PlaylistEditorView: View {
    let playlistID: UUID
    var onSave: () -> Void

    @StateObject private var store = PlaylistStore.shared
    @State private var expandedID: UUID? = nil
    //Vars for the creation of new category
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryColor = Color.gold
    @State private var newIntensity1 = "Low intensity"
    @State private var newIntensity2 = "Medium intensity"
    @State private var newIntensity3 = "High intensity"

    //gets the correct playlist by ID
    private var playlistIdx: Int? {
        store.playlists.firstIndex(where: { $0.id == playlistID })
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            //Iterates the emotions categories, changes direcltu affect store.playlists[idx].emotions
            if let idx = playlistIdx {
                List {
                    ForEach(store.playlists[idx].emotions.indices, id: \.self) { eIdx in
                        //Guard check to prevent errors when deleting an  category(outbounds)
                        if eIdx < store.playlists[idx].emotions.count {
                            EmotionCategorySection(
                                emotion: $store.playlists[idx].emotions[eIdx],
                                isExpanded: expandedID == store.playlists[idx].emotions[eIdx].id,
                                //Helps collapse or expand by checking id
                                onTapHeader: {
                                    let id = store.playlists[idx].emotions[eIdx].id
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        expandedID = expandedID == id ? nil : id
                                    }
                                },
                                //Saves modifications
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
                            //Deletes a category by swiping
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
                    //Button that calls the addCategory sheet to create a new
                    //emotion Category
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
                //Checks that Playlist exist
                guard let idx = playlistIdx else { return }
                //Creates new struct categoru
                let cat = EmotionCategory(
                    categoryName: newCategoryName.trimmingCharacters(in: .whitespaces),
                    colorHex: newCategoryColor.toHex() ?? "#888888",
                    intensity1: Intensity(nameDescription: newIntensity1),
                    intensity2: Intensity(nameDescription: newIntensity2),
                    intensity3: Intensity(nameDescription: newIntensity3)
                )
                store.playlists[idx].emotions.append(cat)
                //Persist Changes
                store.save()
                onSave()
                showAddCategory = false
                //Delays dismiss to avoid visual glitches, when dismissing sheet and,
                //adding animation to display new category
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedID = cat.id
                    }
                }
            }
        }
    }
}
