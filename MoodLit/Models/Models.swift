// Models.swift
// MoodLit

import Foundation

// MARK: - BookSource

enum BookSource: String, Codable {
    case gutenberg
    case local
}

// MARK: - BookType

enum BookType: String, Codable {
    case book      
    case webNovel
}

// MARK: - Book

struct Book: Identifiable, Codable {
    let id: UUID
    var title: String
    var author: String
    var coverURL: String?
    var coverImageData: Data?
    var source: BookSource
    var bookType: BookType
    var localEPUBPath: String
    var chapters: [Chapter]
    var sceneTags: [SceneTag]
    var assignedPlaylistID: UUID?
    var lastOpenedDate: Date?
    var readingProgress: ReadingProgress

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        coverURL: String? = nil,
        coverImageData: Data? = nil,
        source: BookSource = .local,
        bookType: BookType = .book,
        localEPUBPath: String = "",
        chapters: [Chapter] = [],
        sceneTags: [SceneTag] = [],
        assignedPlaylistID: UUID? = nil,
        lastOpenedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.coverImageData = coverImageData
        self.source = source
        self.bookType = bookType
        self.localEPUBPath = localEPUBPath
        self.chapters = chapters
        self.sceneTags = sceneTags
        self.assignedPlaylistID = assignedPlaylistID
        self.lastOpenedDate = lastOpenedDate
        self.readingProgress = ReadingProgress()
        
    }

    // MARK: - Factory Methods

    static func fromGutenberg(_ gutenbergBook: GutenbergBook, localEPUBPath: String) -> Book {
        Book(
            title: gutenbergBook.title,
            author: gutenbergBook.authorNames,
            coverURL: gutenbergBook.coverURL,
            source: .gutenberg,
            bookType: .book,
            localEPUBPath: localEPUBPath
        )
    }

    static func fromLocalEpub(parsed: EpubParser.ParsedBook, localEPUBPath: String) -> Book {
        Book(
            title: parsed.title,
            author: parsed.author,
            coverImageData: parsed.coverImageData,
            source: .local,
            bookType: .book,
            localEPUBPath: localEPUBPath,
            chapters: parsed.chapters
        )
    }

    static func newWebNovel(title: String, author: String = "") -> Book {
        Book(
            title: title,
            author: author.isEmpty ? "Unknown" : author,
            source: .local,
            bookType: .webNovel
        )
    }

    // MARK: - Computed

    var allPages: [BookPage] {
        chapters.flatMap { $0.pages }
    }

    var totalLines: Int {
        allPages.reduce(0) { $0 + $1.lines.count }
    }

    var progressPercent: Double {
        guard totalLines > 0 else { return 0 }
        let linesRead = allPages
            .prefix(readingProgress.pageIndex)
            .reduce(0) { $0 + $1.lines.count }
        return Double(linesRead) / Double(totalLines)
    }

    var isWebNovel: Bool { bookType == .webNovel }
}

// MARK: - Chapter

struct Chapter: Identifiable, Codable {
    let id: UUID
    var title: String
    var pages: [BookPage]

    init(id: UUID = UUID(), title: String, pages: [BookPage]) {
        self.id = id
        self.title = title
        self.pages = pages
    }
}

// MARK: - BookPage

struct BookPage: Identifiable, Codable {
    let id: UUID
    let number: Int
    let lines: [String]

    init(id: UUID = UUID(), number: Int, lines: [String]) {
        self.id = id
        self.number = number
        self.lines = lines
    }
}

// MARK: - SceneTag

struct SceneTag: Identifiable, Codable,Equatable {
    let id: UUID
    let page: Int
    let startLine: Int
    let endLine: Int
    let emotionCategoryID: UUID
    let intensityLevel: Int
    var musicOverride: MusicFile?

    init(
        id: UUID = UUID(),
        page: Int,
        startLine: Int,
        endLine: Int,
        emotionCategoryID: UUID,
        intensityLevel: Int,
        musicOverride: MusicFile? = nil
    ) {
        self.id = id
        self.page = page
        self.startLine = startLine
        self.endLine = endLine
        self.emotionCategoryID = emotionCategoryID
        self.intensityLevel = intensityLevel.clamped(to: 1...3)
        self.musicOverride = musicOverride
    }
}

// MARK: - ReadingProgress

struct ReadingProgress: Codable {
    var pageIndex: Int = 0
    var lineIndex: Int = 0
    var markerSpeed: Double = 30.0
    var isAutoScrolling: Bool = false
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
