// AddChapterSheet.swift
// MoodLit
//
// Sheet for adding chapters to a web novel.
// Two input methods: upload an .epub file (parsed into chapters),
// or paste text directly (split into 25-line pages).
// Opened from BookCard's three-dot menu on web novel entries.

import SwiftUI
import UniformTypeIdentifiers

struct AddChapterSheet: View {
    
    let bookID: UUID

    @ObservedObject private var library = LibraryManager.shared
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var chapterTitle: String = ""   // User-entered title, auto-generates if empty
    @State private var chapterText: String = ""    // Pasted text content, also populated by epub parse
    @State private var showFilePicker: Bool = false // Toggles system file picker for .epub files
    @State private var importError: String? = nil  // Red error text shown below upload button
    @State private var isImporting: Bool = false   // Shows spinner on upload button during epub parsing

    // Computed: always reflects latest book state (e.g. after a chapter was just added)
    private var book: Book? {
        library.books.first { $0.id == bookID }
    }

    // Next chapter number for auto-generated titles (e.g. "Chapter 4" if 3 exist)
    private var nextChapterNumber: Int {
        (book?.chapters.count ?? 0) + 1
    }

    // Add button is disabled until there's actual text content
    // Empty title is fine (auto-generates), but empty text is not
    private var canSave: Bool {
        !chapterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: - Chapter Title Field
                        // Simple text field with dynamic placeholder that updates
                        // as chapters are added (e.g. "e.g. Chapter 4")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Chapter Title")
                                .font(.caption)
                                .foregroundColor(Color.text2)
                            TextField("e.g. Chapter \(nextChapterNumber)", text: $chapterTitle)
                                .font(.subheadline)
                                .foregroundColor(Color.text)
                                .padding(12)
                                .background(Color.surface)
                                .cornerRadius(10)
                        }

                        // MARK: - Import from File
                        // Opens system file picker for .epub files
                        // Parsed epub chapters are added directly to the web novel
                        // Shows spinner while parsing and error text if something fails
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Import from File")
                                .font(.caption)
                                .foregroundColor(Color.text2)

                            Button {
                                showFilePicker = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(Color.gold)
                                        .font(.system(size: 14))
                                    Text("Upload .epub file")
                                        .font(.subheadline)
                                        .foregroundColor(Color.gold)
                                    Spacer()
                                    // Spinner visible during epub parsing
                                    if isImporting {
                                        ProgressView()
                                            .tint(Color.gold)
                                            .scaleEffect(0.7)
                                    }
                                }
                                .padding(12)
                                .background(Color.surface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gold.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isImporting) // Prevent double-tap during parsing

                            Text("The epub will be parsed and its text added as a chapter.")
                                .font(.caption2)
                                .foregroundColor(Color.text2)

                            // Error message (permission denied, parse failure, etc.)
                            if let error = importError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        // MARK: - Paste Text
                        // Alternative to file upload — user pastes or types text directly
                        // Line count updates in real time as user types
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Or Paste Text")
                                    .font(.caption)
                                    .foregroundColor(Color.text2)
                                Spacer()
                                // Live line count
                                if !chapterText.isEmpty {
                                    Text("\(chapterText.components(separatedBy: .newlines).count) lines")
                                        .font(.caption2)
                                        .foregroundColor(Color.text2)
                                }
                            }

                            TextEditor(text: $chapterText)
                                .font(.system(size: 14))
                                .foregroundColor(Color.text)
                                .scrollContentBackground(.hidden) // Removes default white bg
                                .padding(10)
                                .frame(minHeight: 200)
                                .background(Color.surface)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Add Chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel — dismisses without saving
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
                // Add — processes pasted text via saveChapter()
                // Gold when enabled, gray when disabled (no text content)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        saveChapter()
                    }
                    .foregroundColor(canSave ? Color.gold : Color.text2)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            // System file picker — only accepts .epub files, single selection
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.epub],
                allowsMultipleSelection: false
            ) { result in
                handleEpubImport(result)
            }
        }
    }

    // MARK: - Save from Pasted Text
    // Processes the text in the TextEditor into a Chapter with paginated BookPages.
    // Flow: resolve title → split text into lines → chunk into 25-line pages → save
    private func saveChapter() {
        // Use typed title, or auto-generate "Chapter N" if empty
        let title = chapterTitle.trimmingCharacters(in: .whitespaces)
        let finalTitle = title.isEmpty ? "Chapter \(nextChapterNumber)" : title

        let text = chapterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Split on newlines, preserving empty lines as "" for paragraph spacing
        let allLines = text.components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    return [""]
                }
                return [line]
            }

        // Paginate: chunk lines into pages of 25
        // Page numbers continue from the book's existing total so they're globally unique
        // (SceneTag.page references page numbers, so they can't collide across chapters)
        let linesPerPage = 25
        var pages: [BookPage] = []
        let existingPageCount = book?.allPages.count ?? 0

        for startIdx in stride(from: 0, to: allLines.count, by: linesPerPage) {
            let endIdx = min(startIdx + linesPerPage, allLines.count)
            let pageLines = Array(allLines[startIdx..<endIdx])
            let pageNumber = existingPageCount + pages.count + 1
            pages.append(BookPage(number: pageNumber, lines: pageLines))
        }

        // Safety fallback — if stride produced nothing, dump everything into one page
        if pages.isEmpty {
            pages.append(BookPage(number: existingPageCount + 1, lines: allLines))
        }

        // Create chapter, append to book via LibraryManager, dismiss
        // LibraryManager.addChapter() persists to disk automatically
        let chapter = Chapter(title: finalTitle, pages: pages)
        library.addChapter(chapter, to: bookID)
        dismiss()
    }

    // MARK: - ePub Import
    // Handles the result from the system file picker.
    // Flow: get file access → copy to Documents → parse with EpubParser →
    //       loop through parsed chapters → renumber pages → add each to web novel
    //
    // Key difference from Library's full-book import:
    // Library import creates a NEW Book. This adds chapters to an EXISTING web novel.
    // The epub is treated as content to feed into the novel, not a standalone book.
    private func handleEpubImport(_ result: Result<[URL], Error>) {
        importError = nil

        // Unwrap the file URL from the result
        guard case .success(let urls) = result, let url = urls.first else {
            importError = "Could not access file."
            return
        }

        // Request temporary read permission from iOS
        // The file lives outside the app's sandbox (Files, iCloud, etc.)
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Permission denied."
            return
        }

        isImporting = true // Show spinner on upload button

        Task {
            // defer ensures cleanup runs on success OR failure:
            // - Release security-scoped file access
            // - Hide the loading spinner
            defer {
                url.stopAccessingSecurityScopedResource()
                Task { @MainActor in isImporting = false }
            }

            do {
                // Copy epub to app's Documents directory so we own it permanently
                // The security-scoped URL is temporary — without copying,
                // the app couldn't read the file after this scope ends
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destURL = docs.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.copyItem(at: url, to: destURL)
                }

                // Parse on background thread — epub parsing can take a moment
                // (extracting HTML, splitting chapters, cleaning text)
                let parser = EpubParser()
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try parser.parse(url: destURL)
                }.value

                // Back on main thread — required for @Published and @State updates
                await MainActor.run {
                    let existingPageCount = book?.allPages.count ?? 0

                    if parsed.chapters.isEmpty {
                        importError = "No readable content found in this epub."
                        return
                    }

                    // Loop through every chapter the parser found
                    // An epub might have 1 chapter or 20 — all get added
                    for (idx, parsedChapter) in parsed.chapters.enumerated() {
                        // Renumber pages to continue from existing page count
                        // so page numbers don't collide with previous chapters
                        let renumberedPages = parsedChapter.pages.enumerated().map { pageIdx, page in
                            BookPage(
                                number: existingPageCount + pageIdx + 1,
                                lines: page.lines
                            )
                        }

                        // Use parser's chapter title if meaningful,
                        // otherwise auto-generate "Chapter N"
                        let chapterTitle: String
                        if !parsedChapter.title.isEmpty && parsedChapter.title != "Chapter" {
                            chapterTitle = parsedChapter.title
                        } else {
                            chapterTitle = "Chapter \(nextChapterNumber + idx)"
                        }

                        // Append each chapter to the web novel
                        let chapter = Chapter(title: chapterTitle, pages: renumberedPages)
                        library.addChapter(chapter, to: bookID)
                    }

                    // Auto-fill the title field from the epub's metadata
                    // (only if user left it empty)
                    if chapterTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        chapterTitle = parsed.title
                    }

                    dismiss()
                }
            } catch {
                // Parse failure — show error below upload button
                await MainActor.run {
                    importError = "Failed to parse epub: \(error.localizedDescription)"
                }
            }
        }
    }
}
