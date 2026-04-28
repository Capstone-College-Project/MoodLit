//
//  SceneMapView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/18/26.
// Visual overview of all scene tags in a book.
// Shows emotional fingerprint, timeline, now-playing, and scene list.

import SwiftUI

struct SceneMapView: View {
    let bookID: UUID

    @ObservedObject private var library = LibraryManager.shared
    @ObservedObject private var playlistStore = PlaylistManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var swapTag: SceneTag? = nil
    @State private var navigateToBook: Bool = false

    //gets book to display
    private var book: Book? {
        library.books.first { $0.id == bookID }
    }

    //Searhces for playlist assigned to book and gets its data
    private var playlist: Playlist? {
        guard let pid = book?.assignedPlaylistID else { return nil }
        return playlistStore.playlists.first { $0.id == pid }
    }

    //Sorts all scenes by page, then by start line
    //used to arrage every display of sceneTags on View
    private var sortedTags: [SceneTag] {
        book?.sceneTags.sorted { a, b in
            if a.startPage != b.startPage { return a.startPage < b.startPage }
            return a.startLine < b.startLine
        } ?? []
    }
    
    //Gets the current Scene that user is Reading and Progress
    //If user is in  TimeLine, then this gets the current scene and higlights
    //the bar, same use when user selects a scene in All Scenes section
    private var currentSceneIndex: Int? {
        guard let book else { return nil }
        let currentPage = book.allPages[safe: book.readingProgress.pageIndex]?.number ?? 0
        let currentLine = book.readingProgress.lineIndex
        return sortedTags.firstIndex { $0.contains(page: currentPage, line: currentLine) }
    }

    //Body of the View that Displays All Features of this View
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                if let book {
                    ScrollView {
                        VStack(spacing: 20) {
                            bookInfoCard(book: book)
                            if !sortedTags.isEmpty {
                                emotionalFingerprint
                                emotionTimeline
                            }
                            nowPlayingCard
                            allScenesSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                } else {
                    Text("Book not found")
                        .foregroundColor(Color.text2)
                }
            }
            .navigationTitle("Scene Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            //Allows user to swap tracks in All Scenes
            .sheet(item: $swapTag) { tag in
                TrackSwapSheet(bookID: bookID, tag: tag, playlist: playlist)
            }
            //Fast travel to an specific scene in the book
            .navigationDestination(isPresented: $navigateToBook) {
                if let book {
                    BookReaderView(book: book)
                }
            }
        }
    }

    // MARK: - Navigate to Scene
    //Finds page tag page number, updates pageIndex and lineIndex in readingProgress,
    //BookReaderView.setup() runs, it reads pageIndex to set the TabView page and sets
    //tracker.targetLine from lineIndex so PageView scrolls to the exact line.
    private func goToScene(tag: SceneTag) {
        guard let book else { return }
        if let pageIndex = book.allPages.firstIndex(where: { $0.number == tag.startPage }) {
            var progress = book.readingProgress
            progress.pageIndex = pageIndex
            progress.lineIndex = tag.startLine
            library.updateProgress(for: bookID, progress: progress)
            navigateToBook = true
        }
    }

    // MARK: - Book Info Card
    //View That Displays Info of the book and user progress
    private func bookInfoCard(book: Book) -> some View {
        HStack(spacing: 14) {
            //Displays Cover image according to the origins of the book:
            //User's upload, free domain, or webnovel
            Group {
                if let data = book.coverImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = book.coverURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default:
                            Color.surface2.overlay(
                                Image(systemName: "book.closed")
                                    .foregroundColor(Color.text2)
                            )
                        }
                    }
                } else {
                    Color.surface2.overlay(
                        Image(systemName: book.isWebNovel ? "doc.text.fill" : "book.closed")
                            .font(.system(size: 24))
                            .foregroundColor(Color.text2)
                    )
                }
            }
            .frame(width: 65, height: 85)
            .cornerRadius(8)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.headline)
                    .foregroundColor(Color.text)
                    .lineLimit(2)

                Text("\(book.author) · \(sortedTags.count) scenes detected")
                    .font(.caption)
                    .foregroundColor(Color.text2)

                HStack {
                    Text("Ch. \(currentChapterIndex(book: book)) of \(book.chapters.count)")
                        .font(.caption)
                        .foregroundColor(Color.text2)
                    Spacer()
                    Text("\(Int(book.progressPercent * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color.text2)
                }
            }
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
    }

    //Gets the current Chapter that the user is reading,
    //Searches the page by comparing each chapters page wtih current page from Progress
    private func currentChapterIndex(book: Book) -> Int {
        let pageIndex = book.readingProgress.pageIndex
        guard let currentPage = book.allPages[safe: pageIndex] else { return 1 }
        for (idx, chapter) in book.chapters.enumerated() {
            if chapter.pages.contains(where: { $0.number == currentPage.number }) {
                return idx + 1
            }
        }
        return 1
    }

    // MARK: - Emotional Fingerprint
    //Show the emotioal distribution of all scenes
    //Basically if an emotions appears in 30% of the book this section will display it
    private var emotionalFingerprint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EMOTIONAL FINGERPRINT")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.text2)
                .tracking(1)

            //Get orderly list of categories
            let stats = emotionStats()

            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stats, id: \.categoryID) { stat in
                        if let category = resolveCategory(stat.categoryID) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(category.color)
                                .frame(width: max(4, geo.size.width * CGFloat(stat.percent)))
                        }
                    }
                }
            }
            .frame(height: 10)
            .cornerRadius(5)

            HStack(spacing: 0) {
                ForEach(stats.prefix(4), id: \.categoryID) { stat in
                    if let category = resolveCategory(stat.categoryID) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 6, height: 6)
                            Text("\(category.categoryName) \(Int(stat.percent * 100))%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(category.color)
                        }
                        if stat.categoryID != stats.prefix(4).last?.categoryID {
                            Spacer()
                        }
                    }
                }
            }

            HStack {
                Text("Start").font(.caption2).foregroundColor(Color.text2)
                Spacer()
                Text("End").font(.caption2).foregroundColor(Color.text2)
            }
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
    }

    // MARK: - Emotion Timeline
    //Displays the emotions in sections according to how much they appear in the book,
    // each scene is an indivdual verical bar, User can tap bar to directly to that scene tag in book
    private var emotionTimeline: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                //Assigns  width to bar  evenly
                //(totalwidth - gaps/ bar count)
                let barWidth = max(4, (geo.size.width - CGFloat(sortedTags.count - 1) * 2) / CGFloat(max(sortedTags.count, 1)))

                
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(sortedTags.enumerated()), id: \.element.id) { idx, tag in
                        if let category = resolveCategory(tag.emotionCategoryID) {
                            //get height by calculating intensity level
                            let height = CGFloat(tag.intensityLevel) / 3.0
                            let isCurrentScene = idx == currentSceneIndex

                            RoundedRectangle(cornerRadius: 3)
                                .fill(category.color.opacity(isCurrentScene ? 1.0 : 0.7))
                                //Assigns a height to bar according to the intensity level
                                .frame(width: barWidth, height: 20 + height * 60)
                                .overlay(
                                    isCurrentScene ?
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.gold, lineWidth: 2) : nil
                                )
                                .onTapGesture {
                                    //Direclty takes you to the scene that user is taps
                                    goToScene(tag: tag)
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 80)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
    }

    // MARK: - Now Playing Card
    //Displays a music track and its information
    // it shows when user selects an scene in scene map, from
    // all scenes or emtional timeline
    @ViewBuilder
    private var nowPlayingCard: some View {
        if let idx = currentSceneIndex {
            let tag = sortedTags[idx]
            let category = resolveCategory(tag.emotionCategoryID)
            let track = resolveTrack(for: tag)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                            .foregroundColor(Color.gold)
                        Text(track?.title ?? "No track")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color.text)
                    }

                    Text("\(category?.categoryName ?? "Unknown") · Scene \(idx + 1)")
                        .font(.caption)
                        .foregroundColor(Color.text2)
                }

            }
            .padding(14)
            .background(Color.surface)
            .cornerRadius(14)
        }
    }

    // MARK: - All Scenes
    //Shows a list of All scene  tags in the book
    private var allScenesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALL SCENES")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.text2)
                .tracking(1)
            
            //fetch list of scene tags displays it
            ForEach(Array(sortedTags.enumerated()), id: \.element.id) { idx, tag in
                sceneRow(tag: tag, index: idx)
            }

            if sortedTags.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 30))
                        .foregroundColor(Color.text2)
                    Text("No scenes tagged yet")
                        .font(.subheadline)
                        .foregroundColor(Color.text2)
                    Text("Open the reader and use tagging mode to add scenes.")
                        .font(.caption)
                        .foregroundColor(Color.text2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
    }

    //Helper function to display info regarding each scene and navigate to that
    //specific scene in the book
    private func sceneRow(tag: SceneTag, index: Int) -> some View {
        let category = resolveCategory(tag.emotionCategoryID)
        let track = resolveTrack(for: tag)
        let isNowReading = index == currentSceneIndex
        let title = sceneTitle(for: tag)

        return HStack(spacing: 0) {
            // Tappable left side — navigates to scene
            Button {
                goToScene(tag: tag)
            } label: {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(category?.color ?? Color.text2)
                        .frame(width: 4)
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Scene \(index + 1)")
                                .font(.caption)
                                .foregroundColor(Color.text2)

                            if isNowReading {
                                Text("· Now reading")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(Color.gold)
                            }
                        }

                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.text)
                            .lineLimit(1)

                        if let category {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(category.color)
                                    .frame(width: 6, height: 6)
                                Text(category.categoryName)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(category.color)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(category.color.opacity(0.12))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.leading, 12)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Right side — track info + swap button
            VStack(alignment: .trailing, spacing: 6) {
                Text(track?.title ?? "No track")
                    .font(.caption)
                    .foregroundColor(Color.text2)
                    .lineLimit(1)
                
                //Button to swap track with another one
                Button {
                    swapTag = tag
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Swap")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(Color.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gold.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gold.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(isNowReading ? Color.gold.opacity(0.06) : Color.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isNowReading ? Color.gold.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Helpers
    //Gets an emotion categroy by Id
    private func resolveCategory(_ categoryID: UUID) -> EmotionCategory? {
        playlist?.emotions.first { $0.id == categoryID }
    }

    //Checks for an overide music, otherwise get music from playlist
    private func resolveTrack(for tag: SceneTag) -> MusicFile? {
        if let override = tag.musicOverride { return override }
        guard let category = resolveCategory(tag.emotionCategoryID) else { return nil }
        switch tag.intensityLevel {
        case 1: return category.intensity1.music
        case 2: return category.intensity2.music
        default: return category.intensity3.music
        }
    }
    //Helper function that creates a title for the scene.
    //It picks the first line in scene and  picks it as title
    private func sceneTitle(for tag: SceneTag) -> String {
        guard let book else { return "Scene" }
        if let page = book.allPages.first(where: { $0.number == tag.startPage }) {
            if tag.startLine < page.lines.count {
                let line = page.lines[tag.startLine].trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    let maxLength = 35
                    if line.count > maxLength {
                        return String(line.prefix(maxLength)) + "…"
                    }
                    return line
                }
            }
        }
        return "Page \(tag.startPage), Line \(tag.startLine)"
    }

    //Stores emotion id and the percentage that the emotion appears in
    // the book in respect to the others
    private struct EmotionStat {
        let categoryID: UUID
        let percent: Double
    }

    //Helps Count the categories and find which ones have the largest presence in the book
    // Returns array if EmotionStats
    private func emotionStats() -> [EmotionStat] {
        guard !sortedTags.isEmpty else { return [] }
        var counts: [UUID: Int] = [:]
        for tag in sortedTags {
            counts[tag.emotionCategoryID, default: 0] += 1
        }
        let total = Double(sortedTags.count)
        return counts.map { EmotionStat(categoryID: $0.key, percent: Double($0.value) / total) }
            .sorted { $0.percent > $1.percent }
    }
}

// MARK: - Safe Array Access

//Helps Prevents Out out bound errors by returning nil if
//an element is not in the array
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
