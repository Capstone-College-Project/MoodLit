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

    /// Apply parsed AI tags to a book, merging with existing tags.
    /// Existing tags in the same line range are replaced.
    /// - Parameters:
    ///   - tags: Resolved tags from SceneTagParser
    ///   - bookID: Target book
    static func applyAITags(_ tags: [SceneTag], to bookID: UUID) {
        guard var book = LibraryManager.shared.books.first(where: { $0.id == bookID }) else {
            print("❌ SceneTagEngine: Book not found")
            return
        }

        for newTag in tags {
            // Remove any existing tag that overlaps on the same page
            book.sceneTags.removeAll { existing in
                existing.page == newTag.page &&
                rangesOverlap(
                    existing.startLine...existing.endLine,
                    newTag.startLine...newTag.endLine
                )
            }
            book.sceneTags.append(newTag)
        }

        // Keep tags sorted by page then startLine
        book.sceneTags.sort { a, b in
            a.page != b.page ? a.page < b.page : a.startLine < b.startLine
        }

        LibraryManager.shared.updateSceneTags(for: bookID, tags: book.sceneTags)
        print("✅ SceneTagEngine: Applied \(tags.count) tags to book")
    }

    // MARK: - Add / Update Single Tag

    /// Add a new tag or replace an existing one with the same ID.
    static func save(_ tag: SceneTag, to bookID: UUID) {
        guard var book = LibraryManager.shared.books.first(where: { $0.id == bookID }) else { return }

        // Remove overlapping tags on same page before inserting
        book.sceneTags.removeAll { existing in
            existing.id != tag.id &&
            existing.page == tag.page &&
            rangesOverlap(
                existing.startLine...existing.endLine,
                tag.startLine...tag.endLine
            )
        }

        // Replace if same ID exists, otherwise append
        if let idx = book.sceneTags.firstIndex(where: { $0.id == tag.id }) {
            book.sceneTags[idx] = tag
        } else {
            book.sceneTags.append(tag)
        }

        book.sceneTags.sort { a, b in
            a.page != b.page ? a.page < b.page : a.startLine < b.startLine
        }

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

    /// Returns the active SceneTag for a given page and line, if any.
    static func activeTag(page: Int, line: Int, in tags: [SceneTag]) -> SceneTag? {
        tags.first {
            $0.page == page &&
            line >= $0.startLine &&
            line <= $0.endLine
        }
    }

    /// All tags on a given page, sorted by startLine.
    static func tags(onPage page: Int, in tags: [SceneTag]) -> [SceneTag] {
        tags.filter { $0.page == page }.sorted { $0.startLine < $1.startLine }
    }

    /// Returns true if a line is the first line of a tag (where the badge appears).
    static func isTagStart(page: Int, line: Int, in tags: [SceneTag]) -> Bool {
        tags.contains { $0.page == page && $0.startLine == line }
    }

    // MARK: - Helpers

    private static func rangesOverlap(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> Bool {
        a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound
    }
}
