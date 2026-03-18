//
//  GutenbergSearchViewModel.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/1/26.
//

import SwiftUI
import Combine

@MainActor
class GutenbergSearch: ObservableObject {
    @Published var books: [GutenbergBook] = []
    @Published var isSearching = false
    @Published var downloadingBookId: Int? = nil
    @Published var errorMessage: String? = nil

    private let api = GutenbergAPI.shared

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        books = []

        do {
            let response = try await api.search(query: query)
            books = response.results
            if books.isEmpty {
                errorMessage = "No books found for \"\(query)\""
            }
        } catch {
            errorMessage = "Search failed. Check your connection and try again."
        }

        isSearching = false
    }

    func download(book: GutenbergBook) async {
        guard let epubURL = book.epubURL else {
            errorMessage = "No EPUB available for this book."
            return
        }

        downloadingBookId = book.id
        errorMessage = nil

        do {
            let localPath = try await api.downloadEPUB(from: epubURL, book: book)
            let newBook = Book.fromGutenberg(book, localEPUBPath: localPath.lastPathComponent)
            LibraryManager.shared.addBook(newBook)
        } catch {
            errorMessage = "Download failed for \"\(book.title)\""
        }

        downloadingBookId = nil
    }
}

// MARK: - Main View

struct GutenbergSearchView: View {
    @StateObject private var viewModel = GutenbergSearch()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    contentArea
                }
            }
            .navigationTitle("Find Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.text2)
                .font(.system(size: 15))

            TextField("Search by title or author...", text: $query)
                .autocorrectionDisabled()
                .foregroundColor(Color.text)
                .tint(Color.gold)
                .onSubmit {
                    Task { await viewModel.search(query: query) }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    viewModel.books = []
                    viewModel.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.text2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.surface2)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.text2.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isSearching {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.gold)
                    .scaleEffect(1.2)
                Text("Searching…")
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
            }
            Spacer()
        } else if let error = viewModel.errorMessage {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(Color.text2)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        } else if !viewModel.books.isEmpty {
            bookList
        } else {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 40))
                    .foregroundColor(Color.text2)
                Text("Search for a book or author above")
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
            }
            Spacer()
        }
    }

    // MARK: - Book List

    private var bookList: some View {
        List(viewModel.books) { book in
            BookRow(
                book: book,
                isDownloading: viewModel.downloadingBookId == book.id,
                isDownloaded: GutenbergAPI.shared.isDownloaded(bookId: book.id)
            ) {
                Task { await viewModel.download(book: book) }
            }
            .listRowBackground(Color.surface)
            .listRowSeparatorTint(Color.text2.opacity(0.15))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bg)
    }
}

// MARK: - Book Row

struct BookRow: View {
    let book: GutenbergBook
    let isDownloading: Bool
    let isDownloaded: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            coverImage
            bookInfo
            Spacer()
            downloadButton
        }
        .padding(.vertical, 8)
    }

    private var coverImage: some View {
        AsyncImage(url: URL(string: book.coverURL ?? "")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                Color.surface2
                    .overlay(ProgressView().tint(Color.text2).scaleEffect(0.7))
            default:
                Color.surface2
                    .overlay(
                        Image(systemName: "book.closed")
                            .foregroundColor(Color.text2)
                    )
            }
        }
        .frame(width: 50, height: 72)
        .cornerRadius(6)
        .clipped()
    }

    private var bookInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(book.title)
                .font(.headline)
                .foregroundColor(Color.text)
                .lineLimit(2)
            Text(book.authorNames)
                .font(.subheadline)
                .foregroundColor(Color.text2)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if isDownloading {
            ProgressView()
                .tint(Color.gold)
                .frame(width: 28, height: 28)
        } else if isDownloaded {
            Button(action: onDownload) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.sage)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        } else if book.epubURL != nil {
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(Color.gold)
            }
            .buttonStyle(.plain)
        }
    }
}
