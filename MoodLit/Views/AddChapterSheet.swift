//
//  AddChapterSheet.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/14/26.
//


import SwiftUI
import UniformTypeIdentifiers

struct AddChapterSheet: View {
    let bookID: UUID

    @ObservedObject private var library = LibraryManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var chapterTitle: String = ""
    @State private var chapterText: String = ""
    @State private var showFilePicker: Bool = false
    @State private var importError: String? = nil
    @State private var isImporting: Bool = false

    private var book: Book? {
        library.books.first { $0.id == bookID }
    }

    private var nextChapterNumber: Int {
        (book?.chapters.count ?? 0) + 1
    }

    private var canSave: Bool {
        !chapterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Chapter title
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

                        // Import from file
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
                            .disabled(isImporting)

                            Text("The epub will be parsed and its text added as a chapter.")
                                .font(.caption2)
                                .foregroundColor(Color.text2)

                            if let error = importError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        // Or paste text
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Or Paste Text")
                                    .font(.caption)
                                    .foregroundColor(Color.text2)
                                Spacer()
                                if !chapterText.isEmpty {
                                    Text("\(chapterText.components(separatedBy: .newlines).count) lines")
                                        .font(.caption2)
                                        .foregroundColor(Color.text2)
                                }
                            }

                            TextEditor(text: $chapterText)
                                .font(.system(size: 14))
                                .foregroundColor(Color.text)
                                .scrollContentBackground(.hidden)
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        saveChapter()
                    }
                    .foregroundColor(canSave ? Color.gold : Color.text2)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.epub],
                allowsMultipleSelection: false
            ) { result in
                handleEpubImport(result)
            }
        }
    }

    // MARK: - Save from pasted text

    private func saveChapter() {
        let title = chapterTitle.trimmingCharacters(in: .whitespaces)
        let finalTitle = title.isEmpty ? "Chapter \(nextChapterNumber)" : title

        let text = chapterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let allLines = text.components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    return [""]
                }
                return [line]
            }

        let linesPerPage = 25
        var pages: [BookPage] = []
        let existingPageCount = book?.allPages.count ?? 0

        for startIdx in stride(from: 0, to: allLines.count, by: linesPerPage) {
            let endIdx = min(startIdx + linesPerPage, allLines.count)
            let pageLines = Array(allLines[startIdx..<endIdx])
            let pageNumber = existingPageCount + pages.count + 1
            pages.append(BookPage(number: pageNumber, lines: pageLines))
        }

        if pages.isEmpty {
            pages.append(BookPage(number: existingPageCount + 1, lines: allLines))
        }

        let chapter = Chapter(title: finalTitle, pages: pages)
        library.addChapter(chapter, to: bookID)
        dismiss()
    }

    // MARK: - ePub Import

    private func handleEpubImport(_ result: Result<[URL], Error>) {
        importError = nil

        guard case .success(let urls) = result, let url = urls.first else {
            importError = "Could not access file."
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            importError = "Permission denied."
            return
        }

        isImporting = true

        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                Task { @MainActor in isImporting = false }
            }

            do {
                // Copy to Documents first
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destURL = docs.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.copyItem(at: url, to: destURL)
                }

                let parser = EpubParser()
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try parser.parse(url: destURL)
                }.value

                await MainActor.run {
                    let existingPageCount = book?.allPages.count ?? 0

                    if parsed.chapters.isEmpty {
                        importError = "No readable content found in this epub."
                        return
                    }

                    // Add each parsed chapter to the web novel
                    for (idx, parsedChapter) in parsed.chapters.enumerated() {
                        // Renumber pages to continue from existing pages
                        let renumberedPages = parsedChapter.pages.enumerated().map { pageIdx, page in
                            BookPage(
                                number: existingPageCount + pageIdx + 1,
                                lines: page.lines
                            )
                        }

                        let chapterTitle: String
                        if !parsedChapter.title.isEmpty && parsedChapter.title != "Chapter" {
                            chapterTitle = parsedChapter.title
                        } else {
                            chapterTitle = "Chapter \(nextChapterNumber + idx)"
                        }

                        let chapter = Chapter(title: chapterTitle, pages: renumberedPages)
                        library.addChapter(chapter, to: bookID)
                    }

                    // Auto-fill title from epub if empty
                    if chapterTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        chapterTitle = parsed.title
                    }

                    dismiss()
                }
            } catch {
                await MainActor.run {
                    importError = "Failed to parse epub: \(error.localizedDescription)"
                }
            }
        }
    }
}
