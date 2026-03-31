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
    @State private var isAnalyzingAI: Bool = false
    @State private var aiErrorMessage: String? = nil
    @State private var aiSuccessMessage: String? = nil

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
                    Button {
                        Task {
                            await analyzeBookWithAI()
                        }
                    } label: {
                        if isAnalyzingAI {
                            ProgressView()
                                .tint(Color.gold)
                        } else {
                            Image(systemName: "sparkles")
                                .foregroundColor(Color.text2)
                        }
                    }
                    .disabled(isAnalyzingAI)

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
            musicEngine.load(sceneTags: book.sceneTags, playlist: playlist)
            // Force re-evaluation on the current line so the new track plays immediately
            musicEngine.onLineChanged(page: tracker.activePage, line: tracker.activeLine)
        }
        .alert("AI Analysis Error", isPresented: Binding(
            get: { aiErrorMessage != nil },
            set: { if !$0 { aiErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { aiErrorMessage = nil }
        } message: {
            Text(aiErrorMessage ?? "Unknown error")
        }
        .alert("AI Tagging Complete", isPresented: Binding(
            get: { aiSuccessMessage != nil },
            set: { if !$0 { aiSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) { aiSuccessMessage = nil }
        } message: {
            Text(aiSuccessMessage ?? "")
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
    private func setup() {
        guard let book else { return }
        LibraryManager.shared.updateLastOpened(for: book.id) 
        if let playlist { musicEngine.load(sceneTags: book.sceneTags, playlist: playlist) }
        currentPageIndex = book.readingProgress.pageIndex
        let pages = book.allPages
        if currentPageIndex < pages.count {
            tracker.activePage = pages[currentPageIndex].number
        }
        if book.readingProgress.lineIndex > 0 {
            tracker.targetLine = book.readingProgress.lineIndex
        }
        // Parse epub on first open if chapters haven't been loaded yet
        if book.chapters.isEmpty && !hasLoaded && !book.localEPUBPath.isEmpty {
            hasLoaded = true
            Task { await loadEpubContent() }
        }
    }

    //Saves the current Page progress and line to books.reading progress
    //Stops music
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
    @MainActor
    private func analyzeBookWithAI() async {
        guard let book else {
            aiErrorMessage = "Book not found."
            return
        }

        guard let playlist else {
            aiErrorMessage = "Please assign a playlist to this book before using AI tagging."
            return
        }

        isAnalyzingAI = true
        aiErrorMessage = nil
        aiSuccessMessage = nil
        defer { isAnalyzingAI = false }

        do {
            let analyzer = BookAIAnalyzer()
            try await analyzer.analyze(
                book: book,
                playlist: playlist,
                startPageIndex: currentPageIndex
            )
            aiSuccessMessage = "AI tagging finished successfully."
            print("✅ AI analysis completed for \(book.title)")
        } catch {
            aiErrorMessage = error.localizedDescription
            print("❌ AI analysis failed: \(error.localizedDescription)")
        }
    }
    private func tagCountForCurrentPage() -> Int {
        guard let book else { return 0 }
        let pages = book.allPages
        guard currentPageIndex < pages.count else { return 0 }

        let currentPageNumber = pages[currentPageIndex].number
        return book.sceneTags.filter { $0.page == currentPageNumber }.count
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
    //Objects that react to changes
    @ObservedObject var tracker: LineTracker
    @ObservedObject var musicEngine: MusicEngine
    @ObservedObject var settings: ReaderSettings

    //How far is content scrolled vertically
    @State private var scrollOffset: CGFloat = 0
    //Maps index line to the y position on content y coordinate space
    //Works like dictionay where the key is line index and  value is the position on the space
    @State private var lineStaticY: [Int: CGFloat] = [:]

    // Manual scroll — direction locking
    @State private var dragStartOffset: CGFloat = 0
    @State private var dragDirection: DragDirection = .undecided
    //Prevents line jumps form firing more than once
    @State private var hasScrolledToTarget: Bool = false
    
    

    private enum DragDirection {
        case undecided, vertical, horizontal
    }

    //Emits a value 60 times per second,
    //Which helps update on the run State And Published properties,
    //Timer Keeps emiting values even when user is interacting with screen
    private let ticker = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    private let topPadding: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let containerH = geo.size.height
            //Calculates the postion of the marker for screen display
            //Uses ReaderSettings values too
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
                //Allows all areas to be tappable for scrolling
                .contentShape(Rectangle())
                .coordinateSpace(name: "pageContent")
                //Sets where content is displayed and changes as scrollOffset increases
                .offset(y: topPadding - scrollOffset)
                //Fades the top and bottom content
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

            //Marks pages and show trakcs names
            PageMarkerView(
                    markerY: markerY,
                    musicEngine: musicEngine
                )
            }
            //Manual Scrolling with direction locking
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard !tracker.isAutoScrolling else { return }

                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)

                        if dragDirection == .undecided {
                            if scrollOffset > 5 {
                                // When scrolled down: only treat as horizontal
                                // if it's VERY clearly horizontal (3x wider than tall)
                                if horizontal > vertical * 3 {
                                    dragDirection = .horizontal
                                } else {
                                    dragDirection = .vertical
                                    dragStartOffset = scrollOffset
                                }
                            } else {
                                // At the top: normal direction detection
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
                //Multiple apges have their own  timers in memory, this ensures
                //that only current page triggers updating tracker.activeline and scrollOffset
                guard tracker.activePage == page.number else { return }

                //If user changes marker position update tracker with value of position
                tracker.markerY = markerY

                
                // Scroll to target line once lineStaticY is ready
                if !hasScrolledToTarget, let target = tracker.targetLine,
                   let targetY = lineStaticY[target], !lineStaticY.isEmpty {
                    let offset = max(0, targetY + topPadding - markerY)
                    let maxOffset = maxScrollOffset(markerY: markerY)
                    scrollOffset = min(offset, maxOffset)
                    tracker.activeLine = target
                    tracker.targetLine = nil
                    hasScrolledToTarget = true
                }

                //Increments  scrolling (0.5p)  per frame,
                //THis increment allows for continous movement of marker
                if tracker.isAutoScrolling {
                    let pxPerFrame = tracker.scrollSpeed / 60.0
                    scrollOffset += pxPerFrame
                    let maxOffset = maxScrollOffset(markerY: markerY)
                    if scrollOffset >= maxOffset {
                        scrollOffset = maxOffset
                        tracker.isAutoScrolling = false
                    }
                }

                //In every frame Calcualte the closes line to the marker
                detectActiveLine(markerY: markerY)
            }
        }
        .onAppear {
            scrollOffset = 0
            lineStaticY = [:]
            dragDirection = .undecided
            hasScrolledToTarget = false
        }
    }

    //This function computes the maximum amount the content can scroll
    //the point where the very last line sits at the marker position.
    //Basically gets max page offset  by calculating top padding, line postion, marker postion
    private func maxScrollOffset(markerY: CGFloat) -> CGFloat {
        guard let lastY = lineStaticY[page.lines.count - 1] else { return 0 }
        return max(0, lastY + topPadding - markerY)
    }

    //Calcualtes the the closes line to marked
    private func detectActiveLine(markerY: CGFloat) {
        guard tracker.activePage == page.number, !lineStaticY.isEmpty else { return }

        
        var bestIdx = 0
        var bestDist = CGFloat.infinity
        //Calcualtes the the closes line to marked
        //staticY — where the line was laid out
        //scrollOffset — how far the content has moved up (increases as you scroll down)
        //topPadding — the 50pt gap at the top
        for (idx, staticY) in lineStaticY {
            let screenY = staticY - scrollOffset + topPadding
            let dist = abs(screenY - markerY)
            if dist < bestDist {
                bestDist = dist
                bestIdx = idx
            }
        }

        //After Calculating the the closest line(bestIdx)
        // the jump doesnt happen instantly, it steps line by line
        //Problem: Line triggers  lagged behind, or never excecuted at high speed.
        //If line 6 play music, it would lag and play in line 8 but line 8 has a diffrent trigger
        /*Frame 1: bestIdx=8, current=5 → nextLine=6  (step toward 8)
         Frame 2: bestIdx=8, current=6 → nextLine=7  (step toward 8)
         Frame 3: bestIdx=8, current=7 → nextLine=8  (step toward 8)
         Frame 4: bestIdx=8, current=8 → nextLine=8  (arrived, no change)
         If line 6 has a scene tag with "Tension" music, it fires on Frame 1 — exactly when
         the marker reaches line 6. Without the stepping, it would fire on Frame 1 at line 8, making it look like
         the music changed before the marker got there.
         */
        let current = tracker.activeLine
        let nextLine: Int
        if bestIdx > current {
            nextLine = current + 1
        } else if bestIdx < current {
            nextLine = current - 1
        } else {
            nextLine = current
        }

        //Only Changes value if a changed happened
        if nextLine != tracker.activeLine {
            tracker.activeLine = nextLine
        }

        //Calls music engine every frame
        //Music Engine already accounts for every frame and can exit early if its not needed
        musicEngine.onLineChanged(page: tracker.activePage, line: tracker.activeLine)
    }
}

// MARK: - PageMarkerView
//Marks pages and show trakcs names
struct PageMarkerView: View {
    let markerY: CGFloat
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
