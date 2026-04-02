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
    private let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")!

    private init() {}

    // MARK: - Analyze one page
    // Wrapper around the 10-page/block version.

    func analyzePage(
        page: BookPage,
        playlist: Playlist,
        model: String = "llama3.2"
    ) async throws -> AITagResponse {
        try await analyzePages(
            pages: [page],
            playlist: playlist,
            model: model
        )
    }

    // MARK: - Analyze multiple pages (recommended)

    func analyzePages(
        pages: [BookPage],
        playlist: Playlist,
        model: String = "llama3.2"
    ) async throws -> AITagResponse {

        let allowedCategories = playlist.emotions.map { $0.categoryName }

        // Build the page block text using page INDEXES, not page.number
        let pageBlockText = pages.map { page in
            let numberedLines = page.lines.enumerated().map { lineOffset, line in
                "\(lineOffset): \(line)"
            }.joined(separator: "\n")

            return """
            PAGE_NUMBER: \(page.number)
            \(numberedLines)
            """
        }.joined(separator: "\n\n")

        let systemPrompt = """
        You are an AI scene tagger for a reading-and-music app.

        Your job:
        - Read the provided pages carefully
        - Detect emotional segments in the story
        - Use exactly one categoryName from the allowed list
        - Use exactly one intensityLevel: 1, 2, or 3
        - Use PAGE_NUMBER exactly as the page field in the JSON
        - Create at least one tag for every story page in the analyzed block
        - Do not skip a page unless it is clearly non-story content
        - If a page is story content, it must receive at least one tag
        - Prefer broad tags that together cover the full story passage
        - If emotion is neutral or transitional, still assign the closest fitting category at low intensity
        - Ignore front matter, metadata, title pages, table of contents, and Gutenberg/license text
        - startLine must be less than or equal to endLine
        - If a segment covers one line, use the same value for startLine and endLine
        - Keep line numbers within the actual line count of the page

        Return only valid JSON matching the schema.
        """

        let prompt = """
        Allowed categories:
        \(allowedCategories.joined(separator: ", "))

        Intensity guide:
        1 = low
        2 = medium
        3 = high

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
                            "page": .object([
                                "type": .string("integer")
                            ]),
                            "startLine": .object([
                                "type": .string("integer")
                            ]),
                            "endLine": .object([
                                "type": .string("integer")
                            ]),
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
                ])
            ]),
            "required": .array([.string("tags")]),
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
