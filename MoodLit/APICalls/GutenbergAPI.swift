//
//  GutenbergAPI.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/1/26.
//


import Foundation

class GutenbergAPI {
    static let shared = GutenbergAPI()
    private let baseURL = "https://gutendex.com/books"

    // MARK: - Search
    func search(query: String, page: Int = 1) async throws -> GutendexResponse {
        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "search", value: query)
        ]
        if page > 1 {
            queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(GutendexResponse.self, from: data)
    }

    // MARK: - Download
    func downloadEPUB(from urlString: String, book: GutenbergBook) async throws -> URL {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let localURL = localEPUBPath(for: book.id)

        if !FileManager.default.fileExists(atPath: localURL.path) {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: tempURL, to: localURL)
        }

        
        let libraryBook = Book.fromGutenberg(book, localEPUBPath: localURL.path)
        await MainActor.run { LibraryManager.shared.addBook(libraryBook) }

        return localURL
    }

    // MARK: - Helpers
    func isDownloaded(bookId: Int) -> Bool {
        FileManager.default.fileExists(atPath: localEPUBPath(for: bookId).path)
    }

    func localEPUBPath(for bookId: Int) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(bookId).epub")
    }
}
