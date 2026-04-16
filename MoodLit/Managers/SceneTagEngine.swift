//
//  SceneTagEngine.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/11/26.
//


// SceneTagEngine.swift
// MoodLit
//
// Handles all CRUD for SceneTags on a Book.
// Works with LibraryManager to persist changes.
// Also resolves which tag is active for a given page/line.

import Foundation

struct SceneTagEngine {

    // MARK: - Apply AI Tags

    /// Apply scene tags to a book, replacing any existing tags that overlap
    /// the new tags' ranges.
    static func applyAITags(_ tags: [SceneTag], to bookID: UUID) {
        guard var book = LibraryManager.shared.books.first(where: { $0.id == bookID }) else {
            print("❌ SceneTagEngine: Book not found")
            return
        }

        for newTag in tags {
            book.sceneTags.removeAll { existing in
                scenesOverlap(existing, newTag)
            }
            book.sceneTags.append(newTag)
        }

        book.sceneTags.sort(by: scenesInOrder)

        LibraryManager.shared.updateSceneTags(for: bookID, tags: book.sceneTags)
        print("✅ SceneTagEngine: Applied \(tags.count) scenes to book")
    }

    // MARK: - Add / Update Single Tag

    /// Add a new scene tag or replace an existing one with the same ID.
    /// Other scenes that overlap the saved tag's range are removed.
    static func save(_ tag: SceneTag, to bookID: UUID) {
        guard var book = LibraryManager.shared.books.first(where: { $0.id == bookID }) else { return }

        // Remove overlapping scenes (except the one we're updating)
        book.sceneTags.removeAll { existing in
            existing.id != tag.id && scenesOverlap(existing, tag)
        }

        if let idx = book.sceneTags.firstIndex(where: { $0.id == tag.id }) {
            book.sceneTags[idx] = tag
        } else {
            book.sceneTags.append(tag)
        }

        book.sceneTags.sort(by: scenesInOrder)

        LibraryManager.shared.updateSceneTags(for: bookID, tags: book.sceneTags)
    }

    // MARK: - Delete

    static func delete(tagID: UUID, from bookID: UUID) {
        guard var book = LibraryManager.shared.books.first(where: { $0.id == bookID }) else { return }
        book.sceneTags.removeAll { $0.id == tagID }
        LibraryManager.shared.updateSceneTags(for: bookID, tags: book.sceneTags)
    }

    static func deleteAll(from bookID: UUID) {
        LibraryManager.shared.updateSceneTags(for: bookID, tags: [])
    }

    // MARK: - Query

    /// Returns the scene tag whose range contains the given (page, line).
    static func activeTag(page: Int, line: Int, in tags: [SceneTag]) -> SceneTag? {
        tags.first { $0.contains(page: page, line: line) }
    }

    /// All scenes that touch a given page, sorted by start position.
    static func tags(onPage page: Int, in tags: [SceneTag]) -> [SceneTag] {
        tags
            .filter { $0.startPage <= page && $0.endPage >= page }
            .sorted(by: scenesInOrder)
    }

    /// True if the given (page, line) is the very first line of a scene.
    /// Used to decide where to draw the scene badge in the reader.
    static func isTagStart(page: Int, line: Int, in tags: [SceneTag]) -> Bool {
        tags.contains { $0.startPage == page && $0.startLine == line }
    }

    // MARK: - Helpers

    /// True if two scenes overlap at any (page, line) position.
    private static func scenesOverlap(_ a: SceneTag, _ b: SceneTag) -> Bool {
        let aStart = (a.startPage, a.startLine)
        let aEnd = (a.endPage, a.endLine)
        let bStart = (b.startPage, b.startLine)
        let bEnd = (b.endPage, b.endLine)
        return !positionIsAfter(aStart, bEnd) && !positionIsAfter(bStart, aEnd)
    }

    /// True if lhs comes strictly after rhs when compared as (page, line) tuples.
    private static func positionIsAfter(_ lhs: (Int, Int), _ rhs: (Int, Int)) -> Bool {
        if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
        return lhs.1 > rhs.1
    }

    /// Sort comparator — orders scenes by (startPage, startLine) ascending.
    private static func scenesInOrder(_ a: SceneTag, _ b: SceneTag) -> Bool {
        if a.startPage != b.startPage { return a.startPage < b.startPage }
        return a.startLine < b.startLine
    }
}
