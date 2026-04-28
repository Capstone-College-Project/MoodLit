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


// MARK: - Music Source Mode
//
// Determines how scene tags drive the music engine.
//
// .playlist — scenes map to emotion categories, which map to tracks
//             from the assigned Playlist. Pre-existing music files.
//
// .stream   — scenes use AI-generated music prompts (musicPrompt field)
//             sent to a music generator (LatentScore AI) for streaming.
//             Falls back to playlist tracks when a scene has no prompt.
//
// Both modes require an assigned playlist. The user can switch between
// them at any time without re-running AI analysis, because every scene
// stores BOTH the emotion category AND the music prompt.

enum MusicSource: String, Codable, CaseIterable {
    case playlist
    case stream
    
    var displayName: String {
        switch self {
        case .playlist: return "Playlist Tracks"
        case .stream:   return "AI Streaming"
        }
    }
    
    var iconName: String {
        switch self {
        case .playlist: return "music.note.list"
        case .stream:   return "waveform.badge.plus"
        }
    }
    
    var description: String {
        switch self {
        case .playlist:
            return "Scenes play tracks from your assigned playlist based on emotion."
        case .stream:
            return "Scenes stream AI-generated music tailored to each moment. Falls back to playlist tracks when needed."
        }
    }
}



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
    var aiContext: String
    var aiAnalysisStatus: AIAnalysisStatus = .notStarted
    var aiTagsEnabled: Bool = true
    
    // NEW — defaults to .playlist for backwards compatibility
    var musicSource: MusicSource = .playlist             // user toggle: show AI tags or not
    
    
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
        musicSource: MusicSource = .playlist
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
        self.musicSource = musicSource
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
        case lastOpenedDate, readingProgress, aiContext, musicSource
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
        musicSource = try container.decodeIfPresent(MusicSource.self, forKey: .musicSource) ?? .playlist
        
        // NEW — decode AI state fields with fallback defaults for old books
        aiAnalysisStatus = try container.decodeIfPresent(AIAnalysisStatus.self, forKey: .aiAnalysisStatus) ?? .notStarted
        aiTagsEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiTagsEnabled) ?? true
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encodeIfPresent(coverURL, forKey: .coverURL)
        try container.encodeIfPresent(coverImageData, forKey: .coverImageData)
        try container.encode(source, forKey: .source)
        try container.encode(bookType, forKey: .bookType)
        try container.encode(localEPUBPath, forKey: .localEPUBPath)
        try container.encode(chapters, forKey: .chapters)
        try container.encode(sceneTags, forKey: .sceneTags)
        try container.encodeIfPresent(assignedPlaylistID, forKey: .assignedPlaylistID)
        try container.encodeIfPresent(lastOpenedDate, forKey: .lastOpenedDate)
        try container.encode(readingProgress, forKey: .readingProgress)
        try container.encode(aiContext, forKey: .aiContext)
        try container.encode(musicSource, forKey: .musicSource)
        
        // NEW — persist AI state so it survives app restarts
        try container.encode(aiAnalysisStatus, forKey: .aiAnalysisStatus)
        try container.encode(aiTagsEnabled, forKey: .aiTagsEnabled)
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

struct SceneTag: Identifiable, Codable, Equatable {
    let id: UUID
    let startPage: Int
    let startLine: Int
    let endPage: Int
    let endLine: Int
    let emotionCategoryID: UUID
    var intensityLevel: Int
    var musicOverride: MusicFile?
    
    // NEW: AI-generated fields
    var musicPrompt: String?      // Pass 3 output — prompt for LatentScore AI
    var sceneSummary: String?     // Pass 1 output — short description of what happens
    
    init(
        id: UUID = UUID(),
        startPage: Int,
        startLine: Int,
        endPage: Int,
        endLine: Int,
        emotionCategoryID: UUID,
        intensityLevel: Int,
        musicOverride: MusicFile? = nil,
        musicPrompt: String? = nil,
        sceneSummary: String? = nil
    ) {
        self.id = id
        self.startPage = startPage
        self.startLine = startLine
        self.endPage = endPage
        self.endLine = endLine
        self.emotionCategoryID = emotionCategoryID
        self.intensityLevel = intensityLevel
        self.musicOverride = musicOverride
        self.musicPrompt = musicPrompt
        self.sceneSummary = sceneSummary
    }
    
    // MARK: - Range Helpers
    
    /// True if the given (page, line) position falls within this scene's range.
    func contains(page: Int, line: Int) -> Bool {
        if page < startPage || page > endPage { return false }
        if page == startPage && line < startLine { return false }
        if page == endPage && line > endLine { return false }
        return true
    }
    
    /// True if this scene touches the given page at all.
    func touches(page: Int) -> Bool {
        return page >= startPage && page <= endPage
    }
    
    /// Comparable sort key for ordering scenes.
    var startKey: (Int, Int) {
        (startPage, startLine)
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
