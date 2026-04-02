//
//  Home.swift
//  MoodLit
//
//  Created on 3/8/26.
//
//Home feature helps user navigate the different features that the app has

import SwiftUI

struct Home: View {
    @ObservedObject private var library = LibraryManager.shared
    @ObservedObject private var settings = ReaderSettings.shared

    // Books sorted by most recently read by checking date
    private var readBooks: [Book] {
        library.books
            .filter { $0.readingProgress.pageIndex > 0 }
            .sorted { ($0.lastOpenedDate ?? .distantPast) > ($1.lastOpenedDate ?? .distantPast) }
    }

    private var continueReadingBook: Book? {
        readBooks.first
    }

    private var recentBooks: [Book] {
        Array(readBooks.dropFirst().prefix(6))
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    welcomeSection
                        .padding(.top, 8)

                    if let book = continueReadingBook {
                        continueReadingCard(book: book)
                    }

                    navButtons

                    if !recentBooks.isEmpty {
                        recentBooksSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Welcome

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.title2.weight(.semibold))
                .foregroundColor(Color.text)

            if library.books.isEmpty {
                Text("Add a book to get started with MoodLit.")
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
            } else if continueReadingBook != nil {
                Text("Pick up where you left off.")
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
            } else {
                Text("Start reading something new today.")
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Continue Reading

    private func continueReadingCard(book: Book) -> some View {
        NavigationLink(destination: BookReaderView(book: book)) {
            HStack(spacing: 14) {
                // Cover
                Group {
                    if let data = book.coverImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else if let urlString = book.coverURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: coverPlaceholder(book: book)
                            }
                        }
                    } else {
                        coverPlaceholder(book: book)
                    }
                }
                .frame(width: 55, height: 75)
                .cornerRadius(8)
                .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    Text("CONTINUE READING")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color.gold)
                        .tracking(0.8)

                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.text)
                        .lineLimit(2)

                    Text(book.author)
                        .font(.caption)
                        .foregroundColor(Color.text2)
                        .lineLimit(1)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.text2.opacity(0.15))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gold)
                                .frame(width: geo.size.width * book.progressPercent, height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(Int(book.progressPercent * 100))% complete")
                        .font(.caption2)
                        .foregroundColor(Color.text2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.gold)
            }
            .padding(14)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.gold.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nav Buttons

    private var navButtons: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: Library()) {
                navButton(icon: "books.vertical", label: "Library")
            }
            .buttonStyle(.plain)

            NavigationLink(destination: PlaylistListView()) {
                navButton(icon: "music.note.list", label: "Playlists")
            }
            .buttonStyle(.plain)

            NavigationLink(destination: SettingsView()) {
                navButton(icon: "gearshape", label: "Settings")
            }
            .buttonStyle(.plain)
        }
    }

    private func navButton(icon: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color.gold)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(Color.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.surface3, lineWidth: 1)
        )
    }

    // MARK: - Recent Books

    private var recentBooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENTLY READ")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.text2)
                .tracking(1)

            ForEach(recentBooks) { book in
                NavigationLink(destination: BookReaderView(book: book)) {
                    recentBookRow(book: book)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recentBookRow(book: Book) -> some View {
        HStack(spacing: 12) {
            // Cover
            Group {
                if let data = book.coverImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = book.coverURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: coverPlaceholder(book: book)
                        }
                    }
                } else {
                    coverPlaceholder(book: book)
                }
            }
            .frame(width: 40, height: 55)
            .cornerRadius(6)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color.text)
                    .lineLimit(1)

                Text(book.author)
                    .font(.caption)
                    .foregroundColor(Color.text2)
                    .lineLimit(1)
            }

            Spacer()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.surface3, lineWidth: 3)
                    .frame(width: 32, height: 32)
                Circle()
                    .trim(from: 0, to: book.progressPercent)
                    .stroke(Color.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(book.progressPercent * 100))%")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color.text2)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Color.text2)
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func coverPlaceholder(book: Book) -> some View {
        Color.surface2
            .overlay(
                Image(systemName: book.isWebNovel ? "doc.text.fill" : "book.closed")
                    .font(.system(size: 16))
                    .foregroundColor(Color.text2)
            )
    }
}

// MARK: - Settings (placeholder)

struct SettingsView: View {
    @ObservedObject private var settings = ReaderSettings.shared
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // User info
                if let user = auth.currentUser {
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(Color.gold)

                        Text(user.fullName)
                            .font(.headline)
                            .foregroundColor(Color.text)

                        Text(user.email)
                            .font(.caption)
                            .foregroundColor(Color.text2)

                        Text(user.authProvider)
                            .font(.caption2)
                            .foregroundColor(Color.gold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.gold.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .padding(.bottom, 30)
                }

                Text("More settings coming soon.")
                    .font(.subheadline)
                    .foregroundColor(Color.text2)

                Spacer()

                // Log Out button
                Button {
                    auth.logOut()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Log Out")
                    }
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#Preview {
    Home()
}
