//
//  AITagResponse.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/11/26.
//


// SceneTagParser.swift
// MoodLit
//
// Parses AI-returned JSON into [SceneTag], resolving category names
// against the active playlist. Unresolved tags are flagged separately.

import Foundation

// MARK: - AI Response Shape

struct AITagResponse: Codable {
    let bookID: String?
    let tags: [AITag]
}

struct AITag: Codable {
    let page: Int
    let startLine: Int
    let endLine: Int
    let categoryName: String
    let intensityLevel: Int
}

// MARK: - Parse Result

struct SceneTagParseResult {
    let resolved: [SceneTag]          // successfully matched to playlist category
    let unresolved: [UnresolvedTag]   // no matching category found
}

struct UnresolvedTag: Identifiable {
    let id: UUID = UUID()
    let aiTag: AITag
    let reason: String
}

// MARK: - Parser

struct SceneTagParser {
    static func parse(data: Data, against playlist: Playlist) throws -> SceneTagParseResult {
        let response = try JSONDecoder().decode(AITagResponse.self, from: data)
        return parse(response: response, against: playlist)
    }

    static func parse(json: String, against playlist: Playlist) throws -> SceneTagParseResult {
        guard let data = json.data(using: .utf8) else {
            throw SceneTagParserError.invalidJSON
        }
        return try parse(data: data, against: playlist)
    }

    // MARK: - Private

    private static func parse(response: AITagResponse, against playlist: Playlist) -> SceneTagParseResult {
        var resolved: [SceneTag] = []
        var unresolved: [UnresolvedTag] = []

        for aiTag in response.tags {
            // Validate line range
            guard aiTag.startLine <= aiTag.endLine else {
                unresolved.append(UnresolvedTag(
                    aiTag: aiTag,
                    reason: "Invalid range: startLine \(aiTag.startLine) > endLine \(aiTag.endLine)"
                ))
                continue
            }

            // Validate intensity
            guard (1...3).contains(aiTag.intensityLevel) else {
                unresolved.append(UnresolvedTag(
                    aiTag: aiTag,
                    reason: "Invalid intensity level: \(aiTag.intensityLevel) — must be 1, 2, or 3"
                ))
                continue
            }

            // Match category name against playlist (case-insensitive)
            let match = playlist.emotions.first {
                $0.categoryName.lowercased() == aiTag.categoryName.lowercased()
            }

            guard let category = match else {
                unresolved.append(UnresolvedTag(
                    aiTag: aiTag,
                    reason: "No playlist category matches \"\(aiTag.categoryName)\""
                ))
                continue
            }

            let tag = SceneTag(
                page: aiTag.page,
                startLine: aiTag.startLine,
                endLine: aiTag.endLine,
                emotionCategoryID: category.id,
                intensityLevel: aiTag.intensityLevel
            )
            resolved.append(tag)
        }

        print("✅ SceneTagParser: \(resolved.count) resolved, \(unresolved.count) unresolved")
        if !unresolved.isEmpty {
            unresolved.forEach { print("  ⚠️ \($0.reason) — page \($0.aiTag.page) line \($0.aiTag.startLine)") }
        }

        return SceneTagParseResult(resolved: resolved, unresolved: unresolved)
    }
}

// MARK: - Errors

enum SceneTagParserError: LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Could not convert string to JSON data"
        }
    }
}
