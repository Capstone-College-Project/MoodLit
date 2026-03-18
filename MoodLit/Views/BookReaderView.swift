// BookReaderView.swift
// MoodLit
//
// The main reading screen.
// Displays book text with a movable marker that drives music changes.

import SwiftUI
import Combine

// MARK: - BookReaderView

struct BookReaderView: View {
    let bookID: UUID

    private var book: Book? {
        LibraryManager.shared.books.first { $0.id == bookID }
    }

    private var playlist: Playlist? {
        guard let pid = book?.assignedPlaylistID else { return nil }
        return PlaylistStore.shared.playlists.first { $0.id == pid }
    }

    @StateObject private var musicEngine = MusicEngine()
    @StateObject private var tracker: LineTracker
    @ObservedObject private var library = LibraryManager.shared
    @ObservedObject private var settings = ReaderSettings.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var currentPageIndex: Int = 0
    @State private var hasLoaded = false
    @State private var showChapterList = false
    @State private var showReaderSettings = false
    @State private var isTaggingMode: Bool = false

    init(book: Book) {
        self.bookID = book.id
        let engine = MusicEngine()
        _musicEngine = StateObject(wrappedValue: engine)
        _tracker = StateObject(wrappedValue: LineTracker(musicEngine: engine))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            settings.backgroundTheme.backgroundColor.ignoresSafeArea()

            if let book {
                let pages = book.allPages
                if pages.isEmpty {
                    loadingState
                } else {
                    VStack(spacing: 0) {

                        if isTaggingMode {
                            HStack(spacing: 8) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.bg)
                                Text("Tagging Mode — tap any line to add a scene tag")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(Color.bg)
                                Spacer()
                                Button("Done") { isTaggingMode = false }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color.bg)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gold)
                        }

                        TabView(selection: $currentPageIndex) {
                            ForEach(pages.indices, id: \.self) { index in
                                PageView(
                                    page: pages[index],
                                    bookID: bookID,
                                    sceneTags: book.sceneTags,
                                    playlist: playlist,
                                    isTaggingMode: isTaggingMode,
                                    tracker: tracker,
                                    musicEngine: musicEngine,
                                    settings: settings
                                )
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        bottomBar(pages: pages)
                    }
                }
            } else {
                loadingState
            }

            // ── Floating auto-scroll button — bottom left ──
            Button {
                tracker.toggleAutoScroll()
            } label: {
                Image(systemName: tracker.isAutoScrolling ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tracker.isAutoScrolling ? Color.bg : Color.gold)
                    .frame(width: 48, height: 48)
                    .background(
                        tracker.isAutoScrolling
                            ? Color.gold
                            : Color.surface2.opacity(0.9)
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.gold.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .padding(.leading, 20)
            .padding(.bottom, 70)
        }
        .preferredColorScheme(settings.colorScheme == .dark ? .dark : .light)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(book?.title ?? "")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        isTaggingMode.toggle()
                    } label: {
                        Image(systemName: isTaggingMode ? "tag.fill" : "tag")
                            .foregroundColor(isTaggingMode ? Color.gold : Color.text2)
                    }

                    Button { showChapterList = true } label: {
                        Image(systemName: "list.bullet").foregroundColor(Color.text2)
                    }
                    Button { showReaderSettings = true } label: {
                        Image(systemName: "textformat").foregroundColor(Color.text2)
                    }
                }
            }
        }
        .sheet(isPresented: $showChapterList) {
            if let book { ChapterListView(book: book, currentPageIndex: $currentPageIndex) }
        }
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsSheet(settings: settings, tracker: tracker)
        }
        .onAppear { setup() }
        .onDisappear { saveProgress() }
        .onChange(of: scenePhase) { _ in
            if scenePhase == .background || scenePhase == .inactive { saveProgress() }
        }
        .onChange(of: currentPageIndex) { _ in
            guard let book else { return }
            let pages = book.allPages
            guard currentPageIndex < pages.count else { return }
            let page = pages[currentPageIndex]
            tracker.activePage = page.number
            tracker.activeLine = 0
            tracker.isAutoScrolling = false
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(pages: [BookPage]) -> some View {
        let progress = pages.count > 1
            ? Double(currentPageIndex) / Double(pages.count - 1)
            : 0.0

        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.surface3)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gold)
                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    Circle()
                        .fill(Color.gold)
                        .frame(width: 14, height: 14)
                        .offset(x: (geo.size.width * CGFloat(progress)) - 7)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = (value.location.x / geo.size.width).clamped(to: 0...1)
                            currentPageIndex = Int(ratio * Double(pages.count - 1))
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text("Page \(currentPageIndex + 1) of \(pages.count)")
                    .font(.caption2)
                    .foregroundColor(Color.text2)
                Spacer()
                if let title = currentChapterTitle(pages: pages) {
                    Text(title)
                        .font(.caption2)
                        .foregroundColor(Color.text2)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(settings.backgroundTheme.surfaceColor)
    }

    private func currentChapterTitle(pages: [BookPage]) -> String? {
        guard let book, currentPageIndex < pages.count else { return nil }
        let pageNumber = pages[currentPageIndex].number
        return book.chapters.first {
            $0.pages.contains(where: { $0.number == pageNumber })
        }?.title
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Color.gold).scaleEffect(1.2)
            Text("Loading book…").font(.subheadline).foregroundColor(Color.text2)
        }
    }

    private func setup() {
        guard let book else { return }
        if let playlist { musicEngine.load(sceneTags: book.sceneTags, playlist: playlist) }
        currentPageIndex = book.readingProgress.pageIndex
        let pages = book.allPages
        if currentPageIndex < pages.count {
            tracker.activePage = pages[currentPageIndex].number
        }
    }
    
    private func saveProgress() {
        guard let book else { return }
        musicEngine.stop()
        var progress = book.readingProgress
        progress.pageIndex = currentPageIndex
        LibraryManager.shared.updateProgress(for: book.id, progress: progress)
    }

    private func loadEpubContent() async {
        guard let book, !book.localEPUBPath.isEmpty else { print("❌ no path"); return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = URL(fileURLWithPath: book.localEPUBPath).lastPathComponent
        let url = docs.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ ePub not found — \(fileName)"); return
        }
        do {
            let parser = EpubParser()
            let parsed = try await Task.detached(priority: .userInitiated) {
                try parser.parse(url: url)
            }.value
            print("✅ Loaded \(parsed.chapters.count) chapters")
            await MainActor.run {
                LibraryManager.shared.updateChapters(for: book.id, chapters: parsed.chapters)
            }
        } catch {
            print("❌ Parse error: \(error.localizedDescription)")
        }
    }
}

// MARK: - PageView

struct PageView: View {
    let page: BookPage
    let bookID: UUID
    let sceneTags: [SceneTag]
    let playlist: Playlist?
    let isTaggingMode: Bool
    @ObservedObject var tracker: LineTracker
    @ObservedObject var musicEngine: MusicEngine
    @ObservedObject var settings: ReaderSettings

    @State private var scrollOffset: CGFloat = 0
    @State private var lineStaticY: [Int: CGFloat] = [:]

    // Manual scroll — direction locking
    @State private var dragStartOffset: CGFloat = 0
    @State private var dragDirection: DragDirection = .undecided

    private enum DragDirection {
        case undecided, vertical, horizontal
    }

    private let ticker = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    private let topPadding: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let containerH = geo.size.height
            // Compute marker Y from the saved setting (0.0–1.0 → top to bottom)
            let markerY = topPadding + (containerH - topPadding - 80) * CGFloat(settings.markerPosition)

            ZStack(alignment: .topTrailing) {

                // ── Content lines ──
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(page.lines.enumerated()), id: \.offset) { idx, text in
                        SceneTagLineWrapper(
                            page: page.number,
                            lineIndex: idx,
                            sceneTags: sceneTags,
                            playlist: playlist,
                            bookID: bookID,
                            isTaggingMode: isTaggingMode
                        ) {
                            Text(text)
                                .font(settings.readerFont.font(size: settings.fontSize))
                                .foregroundColor(
                                    tracker.activePage == page.number && tracker.activeLine == idx
                                        ? settings.backgroundTheme.textColor(scheme: settings.colorScheme)
                                        : settings.backgroundTheme.mutedTextColor(scheme: settings.colorScheme)
                                )
                                .background(
                                    tracker.activePage == page.number && tracker.activeLine == idx
                                        ? Color.gold.opacity(0.1) : Color.clear
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(
                            GeometryReader { lineGeo in
                                Color.clear.onAppear {
                                    let midY = lineGeo.frame(in: .named("pageContent")).midY
                                    lineStaticY[idx] = midY
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, topPadding)
                .padding(.bottom, containerH * 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(name: "pageContent")
                .offset(y: topPadding - scrollOffset)
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [Color.clear, Color.black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 40)
                        Rectangle()
                        LinearGradient(
                            colors: [Color.black, Color.clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 40)
                    }
                )

                // ── Page marker (display only) ──
                PageMarkerView(
                    markerY: markerY,
                    musicEngine: musicEngine
                )
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onChanged { value in
                        guard !tracker.isAutoScrolling else { return }

                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)

                        if dragDirection == .undecided {
                            if vertical > horizontal {
                                dragDirection = .vertical
                                dragStartOffset = scrollOffset
                            } else {
                                dragDirection = .horizontal
                            }
                        }

                        guard dragDirection == .vertical else { return }

                        let proposed = dragStartOffset - value.translation.height
                        let maxOffset = maxScrollOffset(markerY: markerY)
                        scrollOffset = proposed.clamped(to: 0...maxOffset)
                    }
                    .onEnded { _ in
                        dragDirection = .undecided
                    }
            )
            .onReceive(ticker) { _ in
                guard tracker.activePage == page.number else { return }

                // Keep tracker.markerY in sync with settings
                tracker.markerY = markerY

                if tracker.isAutoScrolling {
                    let pxPerFrame = tracker.scrollSpeed / 60.0
                    scrollOffset += pxPerFrame
                    let maxOffset = maxScrollOffset(markerY: markerY)
                    if scrollOffset >= maxOffset {
                        scrollOffset = maxOffset
                        tracker.isAutoScrolling = false
                    }
                }

                detectActiveLine(markerY: markerY)
            }
        }
        .onAppear {
            scrollOffset = 0
            lineStaticY = [:]
            dragDirection = .undecided
        }
    }

    private func maxScrollOffset(markerY: CGFloat) -> CGFloat {
        guard let lastY = lineStaticY[page.lines.count - 1] else { return 0 }
        return max(0, lastY + topPadding - markerY)
    }

    private func detectActiveLine(markerY: CGFloat) {
        guard tracker.activePage == page.number, !lineStaticY.isEmpty else { return }

        var bestIdx = 0
        var bestDist = CGFloat.infinity

        for (idx, staticY) in lineStaticY {
            let screenY = staticY - scrollOffset + topPadding
            let dist = abs(screenY - markerY)
            if dist < bestDist {
                bestDist = dist
                bestIdx = idx
            }
        }

        if bestIdx != tracker.activeLine {
            tracker.activeLine = bestIdx
            musicEngine.onLineChanged(page: tracker.activePage, line: bestIdx)
        }
    }
}

// MARK: - PageMarkerView
// Display-only marker — position controlled by settings.

struct PageMarkerView: View {
    let markerY: CGFloat
    @ObservedObject var musicEngine: MusicEngine

    var body: some View {
        ZStack(alignment: .topTrailing) {

            // Marker line + dot
            HStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.gold.opacity(0.0), Color.gold.opacity(0.55)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)

                Circle()
                    .fill(Color.gold)
                    .frame(width: 16, height: 16)
                    .shadow(color: Color.gold.opacity(0.6), radius: 5)
                    .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity)
            .offset(y: markerY)

            // Current track label
            if let track = musicEngine.currentTrack {
                HStack(spacing: 5) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundColor(Color.gold)
                    Text(track.title)
                        .font(.caption2)
                        .foregroundColor(Color.text2)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.surface2.opacity(0.9))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gold.opacity(0.2), lineWidth: 1))
                .padding(.trailing, 28)
                .offset(y: max(10, markerY - 32))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Reader Settings Sheet

struct ReaderSettingsSheet: View {
    @ObservedObject var settings: ReaderSettings
    @ObservedObject var tracker: LineTracker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Font") {
                    ForEach(ReaderFont.allCases, id: \.rawValue) { font in
                        Button {
                            settings.readerFont = font
                            settings.save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(font.displayName)
                                        .font(font.font(size: 16))
                                        .foregroundColor(Color.text)
                                    Text("The old castle stood silent in the mist.")
                                        .font(font.font(size: 13))
                                        .foregroundColor(Color.text2)
                                }
                                Spacer()
                                if settings.readerFont == font {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color.gold)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(settings.readerFont == font ? Color.gold.opacity(0.08) : Color.surface)
                    }
                }

                Section("Font Size") {
                    HStack(spacing: 12) {
                        Text("A").font(.system(size: 13, design: .serif)).foregroundColor(Color.text2)
                        Slider(value: $settings.fontSize, in: 12...28, step: 1)
                            .accentColor(Color.gold)
                            .onChange(of: settings.fontSize) { _ in settings.save() }
                        Text("A").font(.system(size: 22, design: .serif)).foregroundColor(Color.text2)
                    }
                    .padding(.vertical, 4)

                    Text("The old castle stood silent in the mist.")
                        .font(settings.readerFont.font(size: settings.fontSize))
                        .foregroundColor(Color.text)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.surface)
                }

                Section("Appearance") {
                    HStack(spacing: 10) {
                        ForEach(ReaderColorScheme.allCases, id: \.rawValue) { scheme in
                            Button {
                                settings.colorScheme = scheme
                                settings.save()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: scheme.icon)
                                    Text(scheme.displayName).font(.subheadline)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(settings.colorScheme == scheme ? Color.gold.opacity(0.2) : Color.surface2)
                                .foregroundColor(settings.colorScheme == scheme ? Color.gold : Color.text2)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(settings.colorScheme == scheme ? Color.gold : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.surface)
                }

                Section("Background") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(ReaderBackground.allCases, id: \.rawValue) { theme in
                            Button {
                                settings.backgroundTheme = theme
                                settings.save()
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(theme.backgroundColor)
                                        .frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(Color.gold.opacity(0.3), lineWidth: 1))
                                    Text(theme.displayName).font(.subheadline).foregroundColor(Color.text)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(settings.backgroundTheme == theme ? Color.gold.opacity(0.12) : Color.surface2)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(settings.backgroundTheme == theme ? Color.gold : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.surface)
                }

                Section("Reading Marker") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Marker Position").font(.subheadline).foregroundColor(Color.text)
                        HStack(spacing: 8) {
                            Text("Top")
                                .font(.caption2)
                                .foregroundColor(Color.text2)
                            Slider(value: $settings.markerPosition, in: 0...1)
                                .accentColor(Color.gold)
                                .onChange(of: settings.markerPosition) { _ in settings.save() }
                            Text("Bottom")
                                .font(.caption2)
                                .foregroundColor(Color.text2)
                        }

                        // Mini preview
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.backgroundTheme.backgroundColor)
                                .frame(height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.surface3, lineWidth: 1)
                                )

                            // Fake text lines
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(0..<5) { i in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.text2.opacity(0.2))
                                        .frame(width: CGFloat([120, 150, 90, 140, 110][i]), height: 3)
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.vertical, 10)

                            // Marker line preview
                            Rectangle()
                                .fill(Color.gold.opacity(0.6))
                                .frame(height: 1.5)
                                .offset(y: -40 + 80 * CGFloat(settings.markerPosition))
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.surface)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auto-scroll Speed").font(.subheadline).foregroundColor(Color.text)
                        HStack(spacing: 8) {
                            Image(systemName: "tortoise.fill").font(.system(size: 12)).foregroundColor(Color.text2)
                            Slider(value: $tracker.sliderValue, in: 0...1).accentColor(Color.gold)
                            Image(systemName: "hare.fill").font(.system(size: 12)).foregroundColor(Color.text2)
                        }
                        Text("\(Int(tracker.scrollSpeed)) pts/sec").font(.caption2).foregroundColor(Color.text2)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Color.gold)
                }
            }
        }
        .background(Color.bg)
    }
}

// MARK: - Chapter List Sheet

struct ChapterListView: View {
    let book: Book
    @Binding var currentPageIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(book.chapters) { chapter in
                    Button {
                        if let firstPage = chapter.pages.first,
                           let index = book.allPages.firstIndex(where: { $0.id == firstPage.id }) {
                            currentPageIndex = index
                        }
                        dismiss()
                    } label: {
                        HStack {
                            Text(chapter.title).foregroundColor(Color.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(Color.text2)
                        }
                    }
                    .listRowBackground(Color.surface)
                }
            }
            .listStyle(.plain)
            .background(Color.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Color.gold)
                }
            }
        }
        .background(Color.bg)
    }
}
