//
//  Library.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/1/26.
//

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
struct BookCard: View {
    let book: Book
    @ObservedObject private var library = LibraryManager.shared
    @State private var showDeleteConfirm: Bool = false
    @State private var showPlaylistPicker: Bool = false
    @State private var showAddChapter: Bool = false
    @State private var showSceneMap: Bool = false

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

                menuButton
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
        .sheet(isPresented: $showPlaylistPicker) {
            PlaylistPickerSheet(book: book)
        }
        .sheet(isPresented: $showAddChapter) {
            AddChapterSheet(bookID: book.id)
        }
        .sheet(isPresented: $showSceneMap) {
            SceneMapView(bookID: book.id)
        }
    }

    // MARK: - Cover Image
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

    private var menuButton: some View {
        Menu {
            Button {
                showSceneMap = true
            } label: {
                Label("Scene Map", systemImage: "map")
            }

            Button {
                showPlaylistPicker = true
            } label: {
                Label("Assign Playlist", systemImage: "music.note.list")
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

#Preview {
    Library()
}
