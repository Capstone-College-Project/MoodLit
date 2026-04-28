//  Library.swift
//  MoodLit
//
// Created on 3/1/26.
//
//Library View, show list of books that user currently has
//Allows user to look for books online or upload their own,
//Allow user to assign a  playlist to book, see the books emotianal map.

import SwiftUI
import UniformTypeIdentifiers

struct Library: View {
    @State private var searchGutenberg: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var showCreateWebNovel: Bool = false
    @ObservedObject private var library = LibraryManager.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg
                    .ignoresSafeArea()

                VStack {
                    topBar
                        .padding(.horizontal, 15)

                    if library.isImporting {
                        HStack(spacing: 8) {
                            ProgressView().tint(Color.gold).scaleEffect(0.8)
                            Text("Importing…").font(.subheadline).foregroundColor(Color.text2)
                        }
                        .padding(10)
                        .background(Color.surface2)
                        .cornerRadius(12)
                    }

                    if library.books.isEmpty {
                        emptyState
                    } else {
                        bookGrid
                    }

                    Spacer()
                }
            }
            .sheet(isPresented: $searchGutenberg) {
                GutenbergSearchView()
            }
            .sheet(isPresented: $showCreateWebNovel) {
                CreateWebNovelSheet()
            }
            // Triggers when  user pick a file from  user's device and add it to library
            //Calls library.importEpub to parse it and add it to library
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.epub],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await library.importEpub(from: url) }
                }
            }
            .alert("Import Failed",
                   isPresented: Binding(
                    get: { library.importError != nil },
                    set: { if !$0 { library.importError = nil } }
                   )
            ) {
                Button("OK", role: .cancel) { library.importError = nil }
            } message: {
                Text(library.importError ?? "")
            }
        }
    }

    // MARK: - Top Bar
    //Shows Title of the view, Allow user  see btn to upload and find Books,
    //As well as creating webnovels
    
    @ViewBuilder
    private var topBar: some View {
        HStack {
            Text("Library")
                .font(.largeTitle)
                .foregroundColor(Color.text)

            Spacer()

            Menu {
                Button {
                    searchGutenberg = true
                } label: {
                    Label("Find Books", systemImage: "magnifyingglass")
                }

                Button {
                    showFilePicker = true
                } label: {
                    Label("Upload ePub", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button {
                    showCreateWebNovel = true
                } label: {
                    Label("New Web Novel", systemImage: "doc.text.fill")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.gold)
                    .frame(width: 40, height: 40)
                    .background(Color.surface2)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Book Grid
    //Shows list of books in grid layout
    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(library.books) { book in
                    NavigationLink(destination: BookReaderView(book: book)) {
                        BookCard(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 10)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 50))
                .foregroundColor(Color.text2)
            Text("Your library is empty")
                .font(.headline)
                .foregroundColor(Color.text)
            Text("Add books or create a web novel to get started")
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

// MARK: - Book Card
//Show Info about a book in the form aof card layout
struct BookCard: View {
    let book: Book
    @ObservedObject private var library = LibraryManager.shared
    @State private var showDeleteConfirm: Bool = false
    @State private var showMusicSourcePicker = false
    @State private var showAddChapter: Bool = false
    @State private var showSceneMap: Bool = false
    @State private var showAIChapterPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    coverImage

                    // Web novel badge
                    if book.isWebNovel {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 8))
                            Text("\(book.chapters.count) ch")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.gold.opacity(0.85))
                        .cornerRadius(6)
                        .padding(6)
                    }
                }
                //Shows  btns to navigate books properties
                menuButton

                // AI status badge — top-left corner of cover
                VStack {
                    HStack {
                        aiStatusBadge
                            .padding(6)
                        Spacer()
                    }
                    Spacer()
                }
            }

            Text(book.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(Color.text)
                .lineLimit(2)

            Text(book.author)
                .font(.caption2)
                .foregroundColor(Color.text2)
                .lineLimit(1)

            if book.progressPercent > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.text2.opacity(0.15))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gold)
                            .frame(width: geo.size.width * book.progressPercent, height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .confirmationDialog(
            "Remove \"\(book.title)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                library.removeBook(book)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the book from your library.")
        }
        .sheet(isPresented: $showMusicSourcePicker) {
            MusicSourcePickerSheet(bookID: book.id)
        }
        .sheet(isPresented: $showAddChapter) {
            AddChapterSheet(bookID: book.id)
        }
        .sheet(isPresented: $showSceneMap) {
            SceneMapView(bookID: book.id)
        }
        .sheet(isPresented: $showAIChapterPicker) {
            AIChapterPickerSheet(bookID: book.id)
        }
    }

    // MARK: - AI Status Badge
    // Small icon overlaid on the top-left of the book cover.
    @ViewBuilder
    private var aiStatusBadge: some View {
        switch book.aiAnalysisStatus {
        case .inProgress:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color.gold))
                .scaleEffect(0.6)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        case .completed:
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.gold)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        case .notStarted:
            EmptyView()
        }
    }

    // MARK: - Cover Image
    //Show cover image for book depending on  origing of the book:
    //Upload with Image,URL Image from Free Domain, Or Webnovel
    @ViewBuilder
    private var coverImage: some View {
        Group {
            if let data = book.coverImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let urlString = book.coverURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        Color.surface2
                            .overlay(ProgressView().tint(Color.text2))
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                if book.isWebNovel {
                    webNovelPlaceholder
                } else {
                    placeholder
                }
            }
        }
        .frame(height: 140)
        .cornerRadius(8)
        .clipped()
    }

    private var placeholder: some View {
        Color.surface2
            .overlay(
                Image(systemName: "book.closed")
                    .foregroundColor(Color.text2)
            )
    }

    private var webNovelPlaceholder: some View {
        Color.surface2
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.gold.opacity(0.6))
                    Text("Novel")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.text2)
                }
            )
    }

    // MARK: - Three-dot Menu
    //Menu that allows the user to trigger differnet features for  books
    private var menuButton: some View {
        Menu {
            Button {
                showSceneMap = true
            } label: {
                Label("Scene Map", systemImage: "map")
            }

            Button {
                showMusicSourcePicker = true
            } label: {
                Label("Music Source", systemImage: "speaker.wave.2.fill")
            }

            // Show AI analysis option unless it's already running
            if book.aiAnalysisStatus != .inProgress {
                Button {
                    showAIChapterPicker = true
                } label: {
                    switch book.aiAnalysisStatus {
                    case .completed:
                        Label("Re-analyse Chapters…", systemImage: "arrow.triangle.2.circlepath")
                    case .failed:
                        Label("Retry AI Analysis…", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    default:
                        Label("Analyse Chapters…", systemImage: "sparkles")
                    }
                }
            }

            if book.isWebNovel {
                Button {
                    showAddChapter = true
                } label: {
                    Label("Add Chapter", systemImage: "plus.doc.on.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Remove Book", systemImage: "trash")
            }

        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(7)
                .background(Color.black.opacity(0.45))
                .clipShape(Circle())
                .padding(6)
        }
    }
}

// MARK: - AI Chapter Picker Sheet
// Lets the user choose which chapters to analyse instead of the whole book.
struct AIChapterPickerSheet: View {
    let bookID: UUID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = LibraryManager.shared

    // Live book — always reflects latest chapters
    private var book: Book? {
        library.books.first { $0.id == bookID }
    }

    private var chapters: [Chapter] {
        book?.chapters ?? []
    }

    // Tracks which chapters are selected and which are currently being analysed
    @State private var selectedChapters: Set<Int> = []
    @State private var analysingChapters: Set<Int> = []
    @State private var doneChapters: Set<Int> = []
    @State private var errorMessage: String? = nil

    private var playlist: Playlist? {
        guard let pid = book?.assignedPlaylistID else { return nil }
        return PlaylistManager.shared.playlists.first { $0.id == pid }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                if chapters.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 40))
                            .foregroundColor(Color.text2)
                        Text("No chapters loaded yet.")
                            .foregroundColor(Color.text2)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Playlist warning
                        if playlist == nil {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Assign a playlist first to enable AI analysis.")
                                    .font(.caption)
                                    .foregroundColor(Color.text2)
                            }
                            .padding(12)
                            .background(Color.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Select all / deselect all
                        HStack {
                            Button {
                                if selectedChapters.count == chapters.count {
                                    selectedChapters = []
                                } else {
                                    selectedChapters = Set(chapters.indices)
                                }
                            } label: {
                                Text(selectedChapters.count == chapters.count
                                     ? "Deselect All" : "Select All")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color.gold)
                            }
                            Spacer()
                            Text("\(selectedChapters.count) selected")
                                .font(.caption2)
                                .foregroundColor(Color.text2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        List {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { idx, chapter in
                                HStack(spacing: 12) {
                                    // Status icon
                                    ZStack {
                                        if analysingChapters.contains(idx) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .frame(width: 22, height: 22)
                                        } else if doneChapters.contains(idx) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 18))
                                        } else {
                                            Image(systemName: selectedChapters.contains(idx)
                                                  ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedChapters.contains(idx)
                                                                 ? Color.gold : Color.text2)
                                                .font(.system(size: 18))
                                        }
                                    }
                                    .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                            .font(.subheadline)
                                            .foregroundColor(Color.text)
                                        Text("\(chapter.pages.count) page(s)")
                                            .font(.caption2)
                                            .foregroundColor(Color.text2)
                                    }

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !analysingChapters.contains(idx),
                                          !doneChapters.contains(idx) else { return }
                                    if selectedChapters.contains(idx) {
                                        selectedChapters.remove(idx)
                                    } else {
                                        selectedChapters.insert(idx)
                                    }
                                }
                                .listRowBackground(Color.surface)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Color.bg)

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }

                        // Analyse button
                        Button {
                            startAnalysis()
                        } label: {
                            HStack(spacing: 8) {
                                if !analysingChapters.isEmpty {
                                    ProgressView().tint(Color.bg).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(analysingChapters.isEmpty
                                     ? "Analyse \(selectedChapters.count) Chapter(s)"
                                     : "Analysing…")
                            }
                            .font(.headline)
                            .foregroundColor(Color.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedChapters.isEmpty || playlist == nil
                                        ? Color.gold.opacity(0.4) : Color.gold)
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .disabled(selectedChapters.isEmpty || playlist == nil || !analysingChapters.isEmpty)
                    }
                }
            }
            .navigationTitle("Analyse Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.gold)
                }
            }
        }
        .background(Color.bg)
        .onAppear {
            // Gutenberg books load chapters lazily on first open.
            // If the picker is opened before the book was ever read,
            // chapters will be empty — so we parse the epub right now.
            guard let book, book.chapters.isEmpty, !book.localEPUBPath.isEmpty else { return }
            Task {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileName = URL(fileURLWithPath: book.localEPUBPath).lastPathComponent
                let url = docs.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                do {
                    let parsed = try await Task.detached(priority: .userInitiated) {
                        try EpubParser().parse(url: url)
                    }.value
                    await MainActor.run {
                        LibraryManager.shared.updateChapters(for: book.id, chapters: parsed.chapters)
                    }
                } catch {
                    print("❌ Chapter picker parse error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startAnalysis() {
        guard let book else { errorMessage = "Book not found."; return }
        guard let playlist else { errorMessage = "Assign a playlist first."; return }
        errorMessage = nil

        let chaptersToAnalyse = selectedChapters.sorted()
        analysingChapters = Set(chaptersToAnalyse)

        if let idx = library.books.firstIndex(where: { $0.id == bookID }) {
            library.books[idx].aiAnalysisStatus = .inProgress
            library.save()
        }

        let capturedBookID = bookID
        let capturedPlaylist = playlist
        let capturedChapters = chaptersToAnalyse

        Task {
            await runAnalysisLoop(
                bookID: capturedBookID,
                playlist: capturedPlaylist,
                chapterIndices: capturedChapters
            )
        }
    }

    @MainActor
    private func runAnalysisLoop(
        bookID: UUID,
        playlist: Playlist,
        chapterIndices: [Int]
    ) async {
        let analyzer = ChapterAnalyzer()
        var anyFailed = false

        for chapterIdx in chapterIndices {
            guard let freshBook = LibraryManager.shared.books.first(where: { $0.id == bookID }) else {
                continue
            }

            do {
                try await analyzer.analyze(
                    book: freshBook,
                    playlist: playlist,
                    chapterIndex: chapterIdx
                )
                analysingChapters.remove(chapterIdx)
                doneChapters.insert(chapterIdx)
                selectedChapters.remove(chapterIdx)
            } catch {
                print("❌ Chapter \(chapterIdx) failed: \(error.localizedDescription)")
                anyFailed = true
                analysingChapters.remove(chapterIdx)
            }
        }

        if let idx = LibraryManager.shared.books.firstIndex(where: { $0.id == bookID }) {
            LibraryManager.shared.books[idx].aiAnalysisStatus = anyFailed ? .failed : .completed
            LibraryManager.shared.save()
        }
    }
}

#Preview {
    Library()
}
