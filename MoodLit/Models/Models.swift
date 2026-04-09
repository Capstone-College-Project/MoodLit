// Models.swift
// MoodLit

import Foundation

// MARK: - BookSource

enum BookSource: String, Codable {
    case gutenberg
    case local
}

enum AIAnalysisStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
    case failed
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
    var aiContext: String  // rolling AI summary
    var aiAnalysisStatus: AIAnalysisStatus  // tracks background analysis state
    var aiTagsEnabled: Bool                 // user toggle: show AI tags or not

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
        lastOpenedDate: Date? = nil,
        aiContext: String = "",
        aiAnalysisStatus: AIAnalysisStatus = .notStarted,
        aiTagsEnabled: Bool = true
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
        self.aiContext = aiContext
        self.aiAnalysisStatus = aiAnalysisStatus
        self.aiTagsEnabled = aiTagsEnabled
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

    // MARK: - Custom Decoding
    
    enum CodingKeys: String, CodingKey {
        case id, title, author, coverURL, coverImageData, source, bookType
        case localEPUBPath, chapters, sceneTags, assignedPlaylistID
        case lastOpenedDate, readingProgress, aiContext
        case aiAnalysisStatus, aiTagsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        coverImageData = try container.decodeIfPresent(Data.self, forKey: .coverImageData)
        source = try container.decode(BookSource.self, forKey: .source)
        bookType = try container.decode(BookType.self, forKey: .bookType)
        localEPUBPath = try container.decode(String.self, forKey: .localEPUBPath)
        chapters = try container.decode([Chapter].self, forKey: .chapters)
        sceneTags = try container.decode([SceneTag].self, forKey: .sceneTags)
        assignedPlaylistID = try container.decodeIfPresent(UUID.self, forKey: .assignedPlaylistID)
        lastOpenedDate = try container.decodeIfPresent(Date.self, forKey: .lastOpenedDate)
        readingProgress = try container.decode(ReadingProgress.self, forKey: .readingProgress)
        aiContext = try container.decodeIfPresent(String.self, forKey: .aiContext) ?? ""
        aiAnalysisStatus = try container.decodeIfPresent(AIAnalysisStatus.self, forKey: .aiAnalysisStatus) ?? .notStarted
        aiTagsEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiTagsEnabled) ?? true
    }
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
