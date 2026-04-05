//
//  OllamaService.swift
//  MoodLit
//
//  Created by Mayra Trochez on 3/20/26.
//
import Foundation

// MARK: - Request / Response Models

private struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let system: String
    let stream: Bool
    let format: JSONValue?
}

private struct OllamaResponseEnvelope: Decodable {
    let response: String
}

// MARK: - JSONValue Helper
// Lets us build JSON schema objects cleanly.

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Ollama Service

final class OllamaService {
    static let shared = OllamaService()

    // Simulator usually works with localhost.
    // For a real iPhone later, replace with your Mac's local IP.
    private let endpoint = URL(string: "http://192.168.40.5:11434/api/generate")!

    private init() {}

    // MARK: - Analyze one page
    // Wrapper around the 10-page/block version.

    func analyzePage(
        page: BookPage,
        playlist: Playlist,
        context: String = "",
        model: String = "llama3.2"
    ) async throws -> AITagResponse {
        try await analyzePages(
            pages: [page],
            playlist: playlist,
            context: context,
            model: model
        )
    }

    // MARK: - Analyze multiple pages (recommended)

    func analyzePages(
        pages: [BookPage],
        playlist: Playlist,
        context: String = "",
        model: String = "llama3.2"
    ) async throws -> AITagResponse {

        let allowedCategories = playlist.emotions.map { $0.categoryName }

        let pageBlockText = pages.map { page in
            let numberedLines = page.lines.enumerated().map { lineOffset, line in
                "\(lineOffset): \(line)"
            }.joined(separator: "\n")

            return """
            PAGE_NUMBER: \(page.number)
            TOTAL_LINES: \(page.lines.count) (line 0 to \(page.lines.count - 1))
            \(numberedLines)
            """
        }.joined(separator: "\n\n")

        let systemPrompt = """
        You are an AI scene tagger for a reading-and-music app. Your job is to assign emotional music categories to sections of story text so that background music matches what the READER FEELS while reading.

        ═══════════════════════════════════════
        WHAT TO SKIP (never tag these):
        ═══════════════════════════════════════
        - Book/chapter titles, section headers, author names, publisher info
        - "Also by", dedications, table of contents, copyright, ISBN
        - Project Gutenberg text, license text, page numbers, footnotes
        - Epigraphs or short quotes before a chapter (under 3 lines)
        - Any metadata that is NOT story narration, dialogue, or description

        ONLY tag actual story content — narration, dialogue, action, description.

        ═══════════════════════════════════════
        HOW TO CHOOSE THE RIGHT CATEGORY
        ═══════════════════════════════════════
        DO NOT match keywords. Match the EMOTIONAL TONE of the scene as experienced by the reader.

        Ask yourself these questions IN ORDER:
        1. WHO is the point-of-view character right now? What are THEY feeling?
        2. What is the NARRATIVE TONE — is the author building dread? warmth? tension? absurdity?
        3. What would a film composer score this moment as?

        COMMON MISTAKES TO AVOID:
        - A conversation ABOUT a battle is not "Battle / Rage" — it might be "Tension / Thriller" or "Sad / Mourning".
        - Children sneaking somewhere dangerous is NOT "Epic / Heroic" — it's likely "Tension / Thriller" or "Mystery / Scary".
        - A kingdom falling discussed by indifferent characters is NOT "Sad / Mourning" — tag what the POV character feels.
        - Travel is NOT automatically "Epic / Heroic" — a quiet walk is "Calm / Nature", a fearful escape is "Tension / Thriller".
        - "Epic / Heroic" requires genuine triumph or courage FROM THE POV CHARACTER.

        GUIDING PRINCIPLE: Tag the emotion the scene EVOKES, not the topic the scene DISCUSSES.

        ═══════════════════════════════════════
        INTENSITY LEVELS
        ═══════════════════════════════════════
        1 = subtle, understated, simmering
        2 = clearly present, building
        3 = peak, overwhelming, fully realized

        ═══════════════════════════════════════
        CONTEXT AWARENESS
        ═══════════════════════════════════════
        Use the CONTEXT provided to understand who the characters are, what the current arc is, and whether emotion is continuing or shifting from the previous page. If a mood carries over with no change, continue the same category — don't force variety.

        ═══════════════════════════════════════
        STRUCTURAL RULES
        ═══════════════════════════════════════
        - EVERY story line must be covered. No gaps between tags.
        - The first tag MUST start at the first story line (skip headers/titles).
        - The last tag MUST end at the last story line on the page.
        - Split into multiple tags ONLY when emotion or intensity genuinely shifts.
        - If the whole page has one mood, use ONE tag covering all story lines.
        - startLine must be ≤ endLine
        - Use PAGE_NUMBER exactly as the page field value provided.

        ═══════════════════════════════════════
        CONTEXT SUMMARY (required)
        ═══════════════════════════════════════
        You MUST include a "contextSummary" field in your response.
        Write 2-3 sentences describing:
        - WHO is present in the scene and what they are doing
        - What EMOTIONAL STATE the POV character is in
        - What MOOD should carry forward to the next page
        This will be your only memory — write what would help you tag the next pages correctly.

        Return only valid JSON matching the schema.
        """

        let contextBlock: String
        if context.isEmpty {
            contextBlock = """
            No previous context — this is the start of the book or a new chapter.
            - Let the TEXT ITSELF establish the mood. Read the full page before tagging.
            - Be conservative with intensity — start at 1 or 2 unless the opening is extreme.
            - Do NOT default to "Epic / Heroic" for openings. Most books open with "Calm / Nature", "Mystery / Scary", or "Tension / Thriller".
            - If the page is mostly scene-setting or introduction, default to "Calm / Nature" intensity 1.
            """
        } else {
            contextBlock = context
        }

        let prompt = """
        CONTEXT FROM PREVIOUS PAGES:
        \(contextBlock)

        ALLOWED CATEGORIES (use exactly as written):
        \(allowedCategories.joined(separator: ", "))

        Analyze these pages:

        \(pageBlockText)
        """

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "bookID": .object([
                    "type": .string("string")
                ]),
                "tags": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "page": .object(["type": .string("integer")]),
                            "startLine": .object(["type": .string("integer")]),
                            "endLine": .object(["type": .string("integer")]),
                            "categoryName": .object([
                                "type": .string("string"),
                                "enum": .array(allowedCategories.map { .string($0) })
                            ]),
                            "intensityLevel": .object([
                                "type": .string("integer"),
                                "enum": .array([.int(1), .int(2), .int(3)])
                            ])
                        ]),
                        "required": .array([
                            .string("page"),
                            .string("startLine"),
                            .string("endLine"),
                            .string("categoryName"),
                            .string("intensityLevel")
                        ]),
                        "additionalProperties": .bool(false)
                    ])
                ]),
                // ── NEW: context summary field ──
                "contextSummary": .object([
                    "type": .string("string"),
                    "description": .string("2-3 sentence summary of who is present, their emotional state, and what mood carries forward")
                ])
            ]),
            "required": .array([.string("tags"), .string("contextSummary")]),  // ← added contextSummary
            "additionalProperties": .bool(false)
        ])
        let requestBody = OllamaRequest(
            model: model,
            prompt: prompt,
            system: systemPrompt,
            stream: false,
            format: schema
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let envelope = try JSONDecoder().decode(OllamaResponseEnvelope.self, from: data)

        guard let jsonData = envelope.response.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        return try JSONDecoder().decode(AITagResponse.self, from: jsonData)
    }
}
