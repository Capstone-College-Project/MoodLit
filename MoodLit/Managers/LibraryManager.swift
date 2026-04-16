// LibraryManager.swift
// MoodLit
//
// Singleton that owns the book library.
// Handles importing ePubs, persisting to disk, and removing books.

import Foundation
import Combine
import UserNotifications

class LibraryManager: ObservableObject {

    static let shared = LibraryManager()
    private init() { load() }

    // MARK: - Published State
    @Published var books: [Book] = []
    @Published var isImporting: Bool = false
    @Published var importError: String? = nil

    // MARK: - Storage
    // Documents directory — safer than UserDefaults for large data
    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("books.json")
    }
    
    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Add / Remove

    func addBook(_ book: Book) {
        // For Gutenberg books check by filename, for local check by path
        let isDuplicate = books.contains { existing in
            existing.localEPUBPath == book.localEPUBPath ||
            (!existing.localEPUBPath.isEmpty &&
             existing.localEPUBPath.lastPathComponent == book.localEPUBPath.lastPathComponent)
        }
        guard !isDuplicate else {
            print("⚠️ Duplicate book, skipping: \(book.title)")
            return
        }
        books.append(book)
        save()
    }

    func removeBook(_ book: Book) {
        books.removeAll { $0.id == book.id }
        save()
    }

    func hasBook(epubPath: String) -> Bool {
        books.contains(where: { $0.localEPUBPath == epubPath })
    }

    
    func addWebNovel(_ novel: Book) {
        books.append(novel)
        save()
    }

    func addChapter(_ chapter: Chapter, to bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].chapters.append(chapter)
        save()
    }
    
    
    
    
    // MARK: - Import ePub from file picker URL

    func importEpub(from url: URL) async {
        await MainActor.run { isImporting = true }
        do {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            // Copy the epub into Documents so we own it permanently
            let fileName = url.lastPathComponent
            let destURL = documentsURL.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.copyItem(at: url, to: destURL)
            }

            let parsed = try await Task.detached(priority: .utility) {
                try EpubParser().parse(url: destURL)
            }.value

            print("✅ Parsed: \(parsed.title) — \(parsed.chapters.count) chapters")

            // Store only the filename, never the full path
            let book = Book.fromLocalEpub(parsed: parsed, localEPUBPath: fileName)

            await MainActor.run {
                self.addBook(book)
                self.isImporting = false
            }
            
        } catch {
            print("❌ Import error: \(error)")
            await MainActor.run {
                self.importError = error.localizedDescription
                self.isImporting = false
            }
            
        }
        
    }

    func setAITagsEnabled(_ enabled: Bool, for bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].aiTagsEnabled = enabled
        save()
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    private func sendAnalysisCompleteNotification(bookTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "AI Analysis Complete"
        content.body = "\"\(bookTitle)\" is ready — open it to enable AI mood tags."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "ai-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
    }
    
    
    
    
    
    

    // MARK: - Update Progress

    func updateProgress(for bookID: UUID, progress: ReadingProgress) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].readingProgress = progress
        save()
    }

    // MARK: - Update Scene Tags

    func updateSceneTags(for bookID: UUID, tags: [SceneTag]) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].sceneTags = tags
        save()
    }
    
    func assignPlaylist(_ playlistID: UUID?, to bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].assignedPlaylistID = playlistID
        save()
    }
    

    func updateChapters(for bookID: UUID, chapters: [Chapter]) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].chapters = chapters
        save()
    }

    // MARK: - Persistence

    public func save() {
        do {
            let data = try JSONEncoder().encode(books)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("LibraryManager: save failed — \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            books = try JSONDecoder().decode([Book].self, from: data)
        } catch {
            print("LibraryManager: load failed — \(error)")
        }
    }
    
    func updateLastOpened(for bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].lastOpenedDate = Date()
        save()
    }
    
    func updateAIContext(for bookID: UUID, context: String) {
        if let idx = books.firstIndex(where: { $0.id == bookID }) {
            books[idx].aiContext = context
            save()
        }
    }
    
    func setMusicSource(_ source: MusicSource, for bookID: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].musicSource = source
        save()
    }
    
}




private extension String {
    var lastPathComponent: String {
        URL(fileURLWithPath: self).lastPathComponent
    }
    
}
