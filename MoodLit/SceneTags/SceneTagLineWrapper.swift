//
//  SceneTagLineWrapper.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/11/26.

import SwiftUI

// MARK: - SceneTagLineWrapper

struct SceneTagLineWrapper<Content: View>: View {
    let content: Content
    let page: Int
    let lineIndex: Int
    let sceneTags: [SceneTag]
    let playlist: Playlist?
    let bookID: UUID
    let isTaggingMode: Bool

    @State private var showCreateEditor = false
    @State private var showEditEditor = false

    init(
        page: Int,
        lineIndex: Int,
        sceneTags: [SceneTag],
        playlist: Playlist?,
        bookID: UUID,
        isTaggingMode: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.page = page
        self.lineIndex = lineIndex
        self.sceneTags = sceneTags
        self.playlist = playlist
        self.bookID = bookID
        self.isTaggingMode = isTaggingMode
        self.content = content()
    }

    private var activeTag: SceneTag? {
        SceneTagEngine.activeTag(page: page, line: lineIndex, in: sceneTags)
    }

    private var activeCategory: EmotionCategory? {
        guard let tag = activeTag, let playlist else { return nil }
        return playlist.emotions.first { $0.id == tag.emotionCategoryID }
    }

    private var isTagStart: Bool {
        activeTag?.startLine == lineIndex
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                // Colored left border — visible when inside a tag
                Rectangle()
                    .fill(activeCategory?.color ?? Color.clear)
                    .frame(width: 3)
                    .cornerRadius(1.5)
                    .padding(.vertical, 2)

                ZStack(alignment: .topLeading) {
                    content

                    // Badge on first line of a tag — always tappable to edit
                    if isTagStart, let category = activeCategory, let tag = activeTag {
                        SceneTagBadge(
                            category: category,
                            intensityLevel: tag.intensityLevel
                        ) {
                            showEditEditor = true
                        }
                        .offset(x: 4, y: -10)
                    }
                }
                .padding(.leading, 6)
            }

            // Tagging mode hint — + icon on lines without a tag
            if isTaggingMode && activeTag == nil {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundColor(Color.gold.opacity(0.6))
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
            }
        }
        // Tap to create tag when in tagging mode and line has no existing tag
        .contentShape(Rectangle())
        .onTapGesture {
            guard isTaggingMode, activeTag == nil else { return }
            showCreateEditor = true
        }
        // Long press always works to create a new tag
        .onLongPressGesture {
            guard activeTag == nil else { return }
            showCreateEditor = true
        }
        .sheet(isPresented: $showCreateEditor) {
            if let playlist {
                SceneTagEditorSheet(
                    bookID: bookID,
                    page: page,
                    startLine: lineIndex,
                    endLine: lineIndex,
                    playlist: playlist
                )
            }
        }
        .sheet(isPresented: $showEditEditor) {
            if let playlist, let tag = activeTag {
                SceneTagEditorSheet(
                    bookID: bookID,
                    page: page,
                    startLine: tag.startLine,
                    endLine: tag.endLine,
                    playlist: playlist,
                    existingTag: tag
                )
            }
        }
    }
}

// MARK: - SceneTagBadge

struct SceneTagBadge: View {
    let category: EmotionCategory
    let intensityLevel: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(category.color)
                    .frame(width: 6, height: 6)

                Text(category.categoryName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.text)
                    .lineLimit(1)

                HStack(spacing: 2) {
                    ForEach(0..<3) { dot in
                        Circle()
                            .fill(dot < intensityLevel ? category.color : Color.surface3)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.surface2)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(category.color.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
