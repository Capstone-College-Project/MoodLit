// BookReaderView.swift
// MoodLit
//
// The main reading screen.
// Displays book pages, here the marker works to trigger music in
// each scene, music can be changed, user can also change reading preferences.
// Allows for user to scroll or autoscroll

import SwiftUI
import Combine

// MARK: - BookReaderView
//Main Reading view loads all book pages

struct BookReaderView: View {
    let bookID: UUID
    //Find book by id, via computed property, always
    //Reflects lastest changes to book
    private var book: Book? {
        LibraryManager.shared.books.first { $0.id == bookID }
    }

    //gets playlist by id,via computer property, always
    //Reflects lastest changes to playlist
    private var playlist: Playlist? {
        guard let pid = book?.assignedPlaylistID else { return nil }
        return PlaylistStore.shared.playlists.first { $0.id == pid }
    }

    //Has the audio playblack
    @StateObject private var musicEngine = MusicEngine()
    //Tracks all properties needed to change music(page,line,scroll speed ..etc)
    @StateObject private var tracker: LineTracker
    @ObservedObject private var library = LibraryManager.shared
    @ObservedObject private var settings = ReaderSettings.shared

    @Environment(\.scenePhase) private var scenePhase
    //Tracks current page
    @State private var currentPageIndex: Int = 0
    //State that helps prevent double parsing
    @State private var hasLoaded = false
    //Bool vars to call sheet views and other func
    @State private var showChapterList = false
    @State private var showReaderSettings = false
    @State private var isTaggingMode: Bool = false
    // AI state is driven by book.aiAnalysisStatus / book.aiTagsEnabled — no local spinner needed
    @State private var aiErrorMessage: String? = nil
    @State private var showAIChapterPicker = false
    @State private var isAnalysingCurrentChapter = false

    init(book: Book) {
        self.bookID = book.id
        let engine = MusicEngine()
        _musicEngine = StateObject(wrappedValue: engine)
        _tracker = StateObject(wrappedValue: LineTracker(musicEngine: engine))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            settings.backgroundTheme.backgroundColor.ignoresSafeArea()

            //Checks if books is not empty and pages are not empty and loads
            //a state or view according to the results if statements
            if let book {
                let pages = book.allPages
                if pages.isEmpty {
                    loadingState
                } else {
                    VStack(spacing: 0) {
                        //Changes top to goldbard to show that
                        //Taggin mode is on
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

                        //Checks the currentIndex Page to and displays it.
                        //Its used for changing pages
                        TabView(selection: $currentPageIndex) {
                            ForEach(pages.indices, id: \.self) { index in
                                // Only show AI scene tags when the user has them enabled.
                                // Manual tags (with a musicOverride) are always visible.
                                let visibleTags = book.aiTagsEnabled
                                    ? book.sceneTags
                                    : book.sceneTags.filter { $0.musicOverride != nil }
                                PageView(
                                    page: pages[index],
                                    bookID: bookID,
                                    sceneTags: visibleTags,
                                    playlist: playlist,
                                    isTaggingMode: isTaggingMode,
                                    tracker: tracker,
                                    musicEngine: musicEngine,
                                    settings: settings
                                )
                                .tag(index)
                            }
                        } //Gives horizontal swipe behavior without dots.
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        bottomBar(pages: pages)
                    }
                }
            } else {
                loadingState
            }

            //Auto-Scroll Button
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
        
        
        //Btn to use the different features to read,navigate or edit book.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 4) {
                    // AI tags button — behaviour depends on analysis status
                    aiToolbarButton

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

        
        //Shows a list of all chapters the book has
        .sheet(isPresented: $showChapterList) {
            if let book { ChapterListView(book: book, currentPageIndex: $currentPageIndex) }
        }//Allows User to change  the  reding settings
        .sheet(isPresented: $showAIChapterPicker) { AIChapterPickerSheet(bookID: bookID) }
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsSheet(settings: settings, tracker: tracker)
        }//Calls the setup on Appear
        .onAppear { setup() }
        //Saves the current page progress
        .onDisappear { saveProgress() }
        //reloads the music engine whenever tags are added or removed,
        //so newly created tags take effect immediately without leaving the reader.
        .onChange(of: scenePhase) { oldValue, newValue in
            if newValue == .background || newValue == .inactive { saveProgress() }
        }
        .onChange(of: currentPageIndex) { oldValue, newValue in
            guard let book else { return }
            let pages = book.allPages
            guard newValue < pages.count else { return }
            let page = pages[newValue]
            tracker.activePage = page.number
            tracker.activeLine = 0
            tracker.isAutoScrolling = false
            musicEngine.stop()
        }
        .onChange(of: book?.sceneTags) { oldValue, newValue in
            guard let book, let playlist else { return }
            // Respect the AI toggle when reloading
            let activeTags = book.aiTagsEnabled
                ? book.sceneTags
                : book.sceneTags.filter { $0.musicOverride != nil }
            musicEngine.load(
                sceneTags: book.sceneTags,
                playlist: playlist,
                musicSource: book.musicSource
            )
            musicEngine.onLineChanged(page: tracker.activePage, line: tracker.activeLine)
        }
        // Bug 3 fix: reload music immediately when user flips the AI tags toggle
        .onChange(of: book?.aiTagsEnabled) { _, _ in
            guard let book, let playlist else { return }
            let activeTags = book.aiTagsEnabled
                ? book.sceneTags
                : book.sceneTags.filter { $0.musicOverride != nil }
            musicEngine.load(
                sceneTags: book.sceneTags,
                playlist: playlist,
                musicSource: book.musicSource
            )
            musicEngine.onLineChanged(page: tracker.activePage, line: tracker.activeLine)
        }
        .onChange(of: book?.musicSource) { _, _ in
            guard let book, let playlist else { return }
            let activeTags = book.aiTagsEnabled
                ? book.sceneTags
                : book.sceneTags.filter { $0.musicOverride != nil }
            musicEngine.load(sceneTags: activeTags, playlist: playlist, musicSource: book.musicSource)
            musicEngine.onLineChanged(page: tracker.activePage, line: tracker.activeLine)
        }
        .alert("AI Error", isPresented: Binding(
            get: { aiErrorMessage != nil },
            set: { if !$0 { aiErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { aiErrorMessage = nil }
        } message: {
            Text(aiErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - AI Toolbar Button
    
    @ViewBuilder
    private var aiToolbarButton: some View {
        switch book?.aiAnalysisStatus ?? .notStarted {

        case .completed:
           
            Menu {
                Button {
                    analyseCurrentChapter()
                } label: {
                    Label("Re-analyse This Chapter",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                
                Button {
                    showAIChapterPicker = true
                } label: {
                    Label("Analyse Other Chapters…",
                          systemImage: "list.bullet.rectangle")
                }
            } label: {
                Image(systemName: "sparkles")
                    .foregroundColor(Color.gold)  // always gold when completed
            }

        case .inProgress:
            ProgressView()
                .tint(Color.gold)
                .scaleEffect(0.85)

        case .failed:
            Menu {
                Button {
                    analyseCurrentChapter()
                } label: {
                    Label("Retry This Chapter",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                
                Button {
                    showAIChapterPicker = true
                } label: {
                    Label("Pick Chapters…",
                          systemImage: "list.bullet.rectangle")
                }
            } label: {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundColor(.orange)
            }

        case .notStarted:
            Menu {
                Button {
                    analyseCurrentChapter()
                } label: {
                    Label("Analyse This Chapter", systemImage: "sparkles")
                }
                
                Button {
                    showAIChapterPicker = true
                } label: {
                    Label("Pick Chapters…",
                          systemImage: "list.bullet.rectangle")
                }
            } label: {
                Image(systemName: "sparkles")
                    .foregroundColor(Color.text2.opacity(0.4))
            }
        }
    }
    // MARK: - Bottom Bar
    //Bottom progress bar and page counter
    //Allows user to see their current progress in the book and
    //the number pages, allows for page changes
    private func bottomBar(pages: [BookPage]) -> some View {
        //Compute current progress
        let progress = pages.count > 1
            ? Double(currentPageIndex) / Double(pages.count - 1)
            : 0.0

        return VStack(spacing: 6) {
            //Creates  golden bar that user can  drag left or right to
            //traverse the book very fast
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

            //Shows  total pages and current page
            HStack {
                Text("Page \(currentPageIndex + 1) of \(pages.count)")
                    .font(.caption2)
                    .foregroundColor(Color.text2)

                Text("• \(tagCountForCurrentPage()) tag(s)")
                    .font(.caption2)
                    .foregroundColor(Color.gold)

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

    //Helper function to display the current page that the user is in
    private func currentChapterTitle(pages: [BookPage]) -> String? {
        guard let book, currentPageIndex < pages.count else { return nil }
        let pageNumber = pages[currentPageIndex].number
        return book.chapters.first {
            $0.pages.contains(where: { $0.number == pageNumber })
        }?.title
    }

    //Shows the user loading state that tells them the book is loading
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Color.gold).scaleEffect(1.2)
            Text("Loading book…").font(.subheadline).foregroundColor(Color.text2)
        }
    }

    //Stamps  date the book is opened,loads scene tags,
    //Loads last page user saw, and sets tracker.
    //If user is coming from Scene map this direclty redirects to the specific
    //Line that the user is pick in Scene Map
    //Parse Online Books that havent been parsed
    @MainActor
    private func setup() {
        guard let book else { return }
        LibraryManager.shared.updateLastOpened(for: book.id)
        
        if let playlist {
            musicEngine.load(
                sceneTags: book.sceneTags,
                playlist: playlist,
                musicSource: book.musicSource
            )
        }
        
        currentPageIndex = book.readingProgress.pageIndex
        let pages = book.allPages
        if currentPageIndex < pages.count {
            tracker.activePage = pages[currentPageIndex].number
        }
        if book.readingProgress.lineIndex > 0 {
            tracker.targetLine = book.readingProgress.lineIndex
        }
        
        //rigger music for current position on open
        // detectActiveLine will fire once lineStaticY populates
        // but this handles the case where we already know the line
        musicEngine.onLineChanged(
            page: tracker.activePage,
            line: tracker.activeLine
        )
        
        if book.chapters.isEmpty && !hasLoaded && !book.localEPUBPath.isEmpty {
            hasLoaded = true
            Task { await loadEpubContent() }
        }
    }
    
    /// Analyses only the chapter the user is currently reading.
    @MainActor
    private func analyseCurrentChapter() {
        guard let book else { return }
        guard let playlist else {
            aiErrorMessage = "Assign a playlist first."
            return
        }
        guard !isAnalysingCurrentChapter else { return }
        
        let pages = book.allPages
        guard currentPageIndex < pages.count else { return }
        let currentPageNumber = pages[currentPageIndex].number
        
        guard let chapterIndex = book.chapters.firstIndex(where: {
            $0.pages.contains(where: { $0.number == currentPageNumber })
        }) else {
            aiErrorMessage = "Could not determine current chapter."
            return
        }
        
        isAnalysingCurrentChapter = true
  
        if let idx = library.books.firstIndex(where: { $0.id == bookID }) {
            library.books[idx].aiAnalysisStatus = .inProgress
            library.save()
        }
        
        let capturedBookID = bookID
        let capturedPlaylist = playlist
        let capturedChapterIndex = chapterIndex
        
        Task {
            let analyzer = ChapterAnalyzer()
            do {
                guard let freshBook = LibraryManager.shared.books
                    .first(where: { $0.id == capturedBookID }) else {
                    await MainActor.run { isAnalysingCurrentChapter = false }
                    return
                }
                
                try await analyzer.analyze(
                    book: freshBook,
                    playlist: capturedPlaylist,
                    chapterIndex: capturedChapterIndex
                )
                
                await MainActor.run {
                    if let idx = LibraryManager.shared.books
                        .firstIndex(where: { $0.id == capturedBookID }) {
                        LibraryManager.shared.books[idx].aiAnalysisStatus = .completed
                        LibraryManager.shared.save()
                    }
                    isAnalysingCurrentChapter = false
                }
                
            } catch {
                print("❌ Analysis failed: \(error.localizedDescription)")
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                    if let idx = LibraryManager.shared.books
                        .firstIndex(where: { $0.id == capturedBookID }) {
                        LibraryManager.shared.books[idx].aiAnalysisStatus = .failed
                        LibraryManager.shared.save()
                    }
                    isAnalysingCurrentChapter = false
                }
            }
        }
    }

    //Saves the current Page progress and line to books.reading progress
    //Stops music
    @MainActor
    private func saveProgress() {
        guard let book else { return }
        musicEngine.stop()
        var progress = book.readingProgress
        progress.pageIndex = currentPageIndex
        progress.lineIndex = tracker.activeLine
        LibraryManager.shared.updateProgress(for: book.id, progress: progress)
    }

    //Parses book from Documents and add the chapters to book
    //Only Runs for books with no chapters(Online Free Domain)
    private func loadEpubContent() async {
        guard let book, !book.localEPUBPath.isEmpty else { print("❌ no path"); return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = URL(fileURLWithPath: book.localEPUBPath).lastPathComponent
        let url = docs.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ ePub not found — \(fileName)"); return
        }
        let bookID = book.id
        do {
            let parsed = try await Task.detached(priority: .userInitiated) {
                try EpubParser().parse(url: url)
            }.value
            print("✅ Loaded \(parsed.chapters.count) chapters")
            await MainActor.run {
                LibraryManager.shared.updateChapters(for: bookID, chapters: parsed.chapters)
            }
        } catch {
            print("❌ Parse error: \(error.localizedDescription)")
        }
    }

    private func tagCountForCurrentPage() -> Int {
        guard let book else { return 0 }
        let pages = book.allPages
        guard currentPageIndex < pages.count else { return 0 }

        let currentPageNumber = pages[currentPageIndex].number
        // A scene "covers" this page if the page falls within its range
        return book.sceneTags.filter { tag in
            currentPageNumber >= tag.startPage && currentPageNumber <= tag.endPage
        }.count
    }
}

// MARK: - LineFrameKey PreferenceKey (add at top level, after imports)

struct LineFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - PageView
//Shows the formated text in page layout for user to read
//Renders lines,scroll offsets,takes care of reader marker
//manual scroll,autoscroll,line detection
//Scene Map jump to specific line
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
    // Keep original onAppear‑based dictionary for scrolling (fast, always available)
    @State private var lineStaticY: [Int: CGFloat] = [:]
    // Use preference‑based dictionary for accurate detection (complete after layout)
    @State private var lineFrames: [Int: CGRect] = [:]
    
    @State private var dragStartOffset: CGFloat = 0
    @State private var dragDirection: DragDirection = .undecided
    @State private var hasScrolledToTarget: Bool = false
    
    private enum DragDirection {
        case undecided, vertical, horizontal
    }
    
    private let ticker = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    private let topPadding: CGFloat = 50
    
    var body: some View {
        GeometryReader { geo in
            let containerH = geo.size.height
            let markerY = topPadding + (containerH - topPadding - 80) * CGFloat(settings.markerPosition)
            
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(page.lines.enumerated()), id: \.offset) { idx, text in
                        SceneTagLineWrapper(
                            page: page.number,
                            lineIndex: idx,
                            sceneTags: sceneTags,
                            playlist: playlist,
                            bookID: bookID,
                            isTaggingMode: isTaggingMode,
                            isActive: tracker.activePage == page.number && tracker.activeLine == idx
                        ) {
                            Text(text)
                                .font(settings.readerFont.font(size: settings.fontSize))
                                .foregroundColor(
                                    isTaggingMode && tracker.activePage == page.number && tracker.activeLine == idx
                                        ? settings.backgroundTheme.textColor(scheme: settings.colorScheme)
                                        : settings.backgroundTheme.mutedTextColor(scheme: settings.colorScheme)
                                )
                                .background(
                                    isTaggingMode && tracker.activePage == page.number && tracker.activeLine == idx
                                        ? Color.gold.opacity(0.1) : Color.clear
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(
                            GeometryReader { lineGeo in
                                Color.clear
                                    .onAppear {
                                        // Keep lineStaticY for immediate scrolling
                                        let midY = lineGeo.frame(in: .named("pageContent")).midY
                                        lineStaticY[idx] = midY
                                    }
                                    .preference(
                                        key: LineFrameKey.self,
                                        value: [idx: lineGeo.frame(in: .named("pageContent"))]
                                    )
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, topPadding)
                .padding(.bottom, containerH * 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .coordinateSpace(name: "pageContent")
                .offset(y: topPadding - scrollOffset)
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Color.clear, Color.black], startPoint: .top, endPoint: .bottom).frame(height: 40)
                        Rectangle()
                        LinearGradient(colors: [Color.black, Color.clear], startPoint: .top, endPoint: .bottom).frame(height: 40)
                    }
                )
                .onPreferenceChange(LineFrameKey.self) { frames in
                    // Store complete frames for accurate line detection
                    lineFrames = frames
                }
                
                PageMarkerView(markerY: markerY, tagMode: isTaggingMode, musicEngine: musicEngine)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard !tracker.isAutoScrolling else { return }
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        
                        if dragDirection == .undecided {
                            if scrollOffset > 5 {
                                if horizontal > vertical * 3 {
                                    dragDirection = .horizontal
                                } else {
                                    dragDirection = .vertical
                                    dragStartOffset = scrollOffset
                                }
                            } else {
                                if vertical > horizontal {
                                    dragDirection = .vertical
                                    dragStartOffset = scrollOffset
                                } else {
                                    dragDirection = .horizontal
                                }
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
                tracker.markerY = markerY
                
                // Scroll to target line using lineStaticY (already populated)
                if !hasScrolledToTarget, let target = tracker.targetLine,
                   let targetY = lineStaticY[target], !lineStaticY.isEmpty {
                    let offset = max(0, targetY + topPadding - markerY)
                    let maxOffset = maxScrollOffset(markerY: markerY)
                    scrollOffset = min(offset, maxOffset)
                    tracker.activeLine = target
                    tracker.targetLine = nil
                    hasScrolledToTarget = true
                }
                
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
            lineFrames = [:]
            dragDirection = .undecided
            hasScrolledToTarget = false
        }
    }
    
    private func maxScrollOffset(markerY: CGFloat) -> CGFloat {
        // Use lineStaticY for scrolling (always available as lines appear)
        guard let lastY = lineStaticY[page.lines.count - 1] else { return 0 }
        return max(0, lastY + topPadding - markerY)
    }
    
    private func detectActiveLine(markerY: CGFloat) {
        guard tracker.activePage == page.number else { return }

        var bestIdx = 0
        var bestDist = CGFloat.infinity

        if !lineFrames.isEmpty {
            for (idx, rect) in lineFrames {
                let screenY = rect.midY - scrollOffset + topPadding
                let dist = abs(screenY - markerY)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = idx
                }
            }
        } else if !lineStaticY.isEmpty {
            for (idx, y) in lineStaticY {
                let screenY = y - scrollOffset + topPadding
                let dist = abs(screenY - markerY)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = idx
                }
            }
        } else {
            return
        }

        //  Update activeLine only when changed
        if bestIdx != tracker.activeLine {
            tracker.activeLine = bestIdx
        }

        //Always call — MusicEngine guards against re-trigger via activeTagID
        // This ensures music starts on page load even if bestIdx == activeLine
        musicEngine.onLineChanged(
            page: tracker.activePage,
            line: bestIdx
        )
    }
}
    
    // MARK: - PageMarkerView
    //Marks pages and show trakcs names
    struct PageMarkerView: View {
        let markerY: CGFloat
        let tagMode: Bool
        @ObservedObject var musicEngine: MusicEngine
        
        var body: some View {
            ZStack(alignment: .topTrailing) {
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
                
                if tagMode, let track = musicEngine.currentTrack {
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
    //Allow user to change the format of the text, and background of page,
    //Change marker postion and speed of auto scroll
    struct ReaderSettingsSheet: View {
        @ObservedObject var settings: ReaderSettings
        @ObservedObject var tracker: LineTracker
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationStack {
                List {
                    
                    //Allows user to select a type of font
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
                                .onChange(of: settings.fontSize) { oldValue, newValue in settings.save() }
                            Text("A").font(.system(size: 22, design: .serif)).foregroundColor(Color.text2)
                        }
                        .padding(.vertical, 4)
                        
                        Text("The old castle stood silent in the mist.")
                            .font(settings.readerFont.font(size: settings.fontSize))
                            .foregroundColor(Color.text)
                            .padding(.vertical, 4)
                            .listRowBackground(Color.surface)
                    }
                    
                    //Changes Background Color
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
                    
                    //Allows for the position fo the reading marker to be changed
                    Section("Reading Marker") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Marker Position").font(.subheadline).foregroundColor(Color.text)
                            HStack(spacing: 8) {
                                Text("Top")
                                    .font(.caption2)
                                    .foregroundColor(Color.text2)
                                Slider(value: $settings.markerPosition, in: 0...1)
                                    .accentColor(Color.gold)
                                    .onChange(of: settings.markerPosition) { oldValue, newValue in settings.save() }
                                Text("Bottom")
                                    .font(.caption2)
                                    .foregroundColor(Color.text2)
                            }
                            
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.backgroundTheme.backgroundColor)
                                    .frame(height: 80)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.surface3, lineWidth: 1)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(0..<5) { i in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.text2.opacity(0.2))
                                            .frame(width: CGFloat([120, 150, 90, 140, 110][i]), height: 3)
                                    }
                                }
                                .padding(.leading, 12)
                                .padding(.vertical, 10)
                                
                                Rectangle()
                                    .fill(Color.gold.opacity(0.6))
                                    .frame(height: 1.5)
                                    .offset(y: -40 + 80 * CGFloat(settings.markerPosition))
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.surface)
                        
                        //Changes reading speed for autocroll
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
    //Shows a list of all the book chapters
    struct ChapterListView: View {
        let book: Book
        @Binding var currentPageIndex: Int
        @Environment(\.dismiss) private var dismiss
        
        // Compute which chapter the current page belongs to
        private var currentChapterID: UUID? {
            let pages = book.allPages
            guard currentPageIndex < pages.count else { return nil }
            let pageNumber = pages[currentPageIndex].number
            return book.chapters.first {
                $0.pages.contains(where: { $0.number == pageNumber })
            }?.id
        }
        
        var body: some View {
            NavigationStack {
                List {
                    ForEach(book.chapters) { chapter in
                        let isCurrent = chapter.id == currentChapterID
                        
                        Button {
                            if let firstPage = chapter.pages.first,
                               let index = book.allPages.firstIndex(where: { $0.id == firstPage.id }) {
                                currentPageIndex = index
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                // Active indicator bar
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isCurrent ? Color.gold : Color.clear)
                                    .frame(width: 3, height: 20)
                                
                                Text(chapter.title)
                                    .foregroundColor(isCurrent ? Color.gold : Color.text)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                
                                Spacer()
                                
                                if isCurrent {
                                    Text("Current")
                                        .font(.caption2)
                                        .foregroundColor(Color.gold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.gold.opacity(0.12))
                                        .cornerRadius(6)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color.text2)
                            }
                        }
                        .listRowBackground(
                            isCurrent ? Color.gold.opacity(0.08) : Color.surface
                        )
                    }
                }
                .listStyle(.insetGrouped)       // fixes first row clipping
                .scrollContentBackground(.hidden)
                .background(Color.bg)
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

