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
        case .string(let value): try container.encode(value)
        case .int(let value):    try container.encode(value)
        case .bool(let value):   try container.encode(value)
        case .array(let value):  try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - AI Pipeline Response Models

/// Pass 1 — prose scene segmentation
struct AIProseScenesResponse: Codable {
    let scenes: [AIProseScene]
}

struct AIProseScene: Codable {
    let sceneIndex: Int
    let openingPhrase: String   // verbatim phrase from text where scene starts
    let sceneSummary: String
}

/// Pass 2 — emotion classification (single scene)
struct AISceneClassification: Codable {
    let sceneIndex: Int
    let categoryName: String
    let intensityLevel: Int
}

/// Pass 3 — music prompt generation
struct AIMusicPromptsResponse: Codable {
    let prompts: [AISceneMusicPrompt]
}

struct AISceneMusicPrompt: Codable {
    let sceneIndex: Int
    let musicPrompt: String
}

// MARK: - OllamaService

final class OllamaService {
    static let shared = OllamaService()

    private let endpoint = URL(string: "http://192.168.40.5:11434/api/generate")!
    private let defaultModel = "llama3.2"

    private init() {}

    // MARK: - Generic Generate Helper

    func generate(
        system: String,
        prompt: String,
        schema: JSONValue,
        model: String? = nil
    ) async throws -> String {
        let requestBody = OllamaRequest(
            model: model ?? defaultModel,
            prompt: prompt,
            system: system,
            stream: false,
            format: schema
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let envelope = try JSONDecoder().decode(OllamaResponseEnvelope.self, from: data)
        return envelope.response
    }

    // MARK: - Pass 1: Segment Chapter Into Scenes

    func segmentChapterIntoScenes(
        chapterTitle: String,
        chapterProse: String,
        approximateLineCount: Int
    ) async throws -> AIProseScenesResponse {

        let systemPrompt = """
        You divide a book chapter into scenes. Output ONLY valid JSON.

        A scene is a block of story in one place and time. Start a new scene when the location changes, time jumps, or a different event begins.

        For each scene return:
        - openingPhrase: 6-12 words copied VERBATIM from the text where the scene starts
        - sceneSummary: one sentence — who, what, where (use character names)

        Rules:
        - First scene starts at the beginning of the chapter
        - Produce at least 5 scenes for long chapters (1000+ words)
        - sceneIndex starts at 0
        - openingPhrase must appear word-for-word in the input
        - Never use "..." or placeholder phrases

        {
          "scenes": [
            { "sceneIndex": 0, "openingPhrase": "<verbatim phrase>", "sceneSummary": "<who, what, where>" }
          ]
        }
        """

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "scenes": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "sceneIndex":    .object(["type": .string("integer")]),
                            "openingPhrase": .object(["type": .string("string")]),
                            "sceneSummary":  .object(["type": .string("string")])
                        ]),
                        "required": .array([
                            .string("sceneIndex"),
                            .string("openingPhrase"),
                            .string("sceneSummary")
                        ]),
                        "additionalProperties": .bool(false)
                    ])
                ])
            ]),
            "required": .array([.string("scenes")]),
            "additionalProperties": .bool(false)
        ])

        let prompt = """
        CHAPTER: \(chapterTitle)

        \(chapterProse)

        Divide this chapter into scenes. For each scene, give me a short verbatim opening phrase from the text and a one-sentence summary.
        """

        let raw = try await generate(
            system: systemPrompt,
            prompt: prompt,
            schema: schema,
            model: "mistral-nemo"
        )

        guard let data = raw.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try JSONDecoder().decode(AIProseScenesResponse.self, from: data)
    }

    // MARK: - Pass 2: Classify Single Scene Emotion

    func classifyOneSceneEmotion(
        sceneText: String,
        sceneIndex: Int,
        allowedCategories: [String]
    ) async throws -> AISceneClassification {

        let systemPrompt = """
        You assign ONE emotion category and intensity to a single story scene.

        Allowed categories:
        \(allowedCategories.joined(separator: ", "))

        Intensity levels:
        1 = subtle, background presence
        2 = clearly present, building
        3 = overwhelming, peak

        Rules:
        - Pick the category based on what the reader FEELS in this scene, not the topic.
        - "Talking about a battle" is NOT Battle unless fighting or tension is present.
        - Use Neutral only if no clear emotion (pure exposition, transitions).

        Set sceneIndex to exactly \(sceneIndex). Return ONLY valid JSON.
        """

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "sceneIndex": .object(["type": .string("integer")]),
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
                .string("sceneIndex"),
                .string("categoryName"),
                .string("intensityLevel")
            ]),
            "additionalProperties": .bool(false)
        ])

        let raw = try await generate(
            system: systemPrompt,
            prompt: "Classify this scene:\n\n\(sceneText)",
            schema: schema
        )

        guard let data = raw.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let decoded = try JSONDecoder().decode(AISceneClassification.self, from: data)

        // Force sceneIndex to match what we asked for in case model drifts
        return AISceneClassification(
            sceneIndex: sceneIndex,
            categoryName: decoded.categoryName,
            intensityLevel: decoded.intensityLevel
        )
    }

    // MARK: - Pass 3: Generate Music Prompts

    func generateMusicPromptsForScenes(
        scenesText: String
    ) async throws -> AIMusicPromptsResponse {

        let systemPrompt = """
        You write TWO-WORD vibe descriptions for an AI music generator called LatentScore.
        Each vibe becomes the background music for a single story scene in a reading app.

        ═══════════════════════════════════════
        THE FORMAT — STRICTLY TWO WORDS
        ═══════════════════════════════════════
        Every musicPrompt must be EXACTLY two words. No more, no less.

        EXCELLENT two-word vibes:
        - "warm sunset"
        - "dark forest"
        - "lone candle"
        - "heroic cavalry"
        - "empty throne"
        - "first snowfall"
        - "moonlit duel"
        - "stormy cliff"
        - "gentle mourning"
        - "fierce battle"
        - "celestial light"
        - "creeping dread"
        - "tender warmth"
        - "ancient ruins"
        - "quiet grief"
        - "rising hope"

        BAD vibes — NEVER do these:
        - "warm, gentle piano arpeggios with soft strings" ← too long, lists instruments
        - "sad melancholic music" ← three words, too abstract
        - "battle scene music" ← three words, mentions scene
        - "Arthas feels grief" ← mentions characters

        ═══════════════════════════════════════
        RULES
        ═══════════════════════════════════════
        - EXACTLY two words per vibe — this is the most important rule
        - First word = adjective (the mood/quality)
        - Second word = noun (the image/place/thing)
        - Never list instruments, BPM, or technical audio terms
        - Never mention characters, plot, or proper nouns
        - Match the EMOTION and INTENSITY provided
        - Vary vibes across scenes — never repeat the same two words

        Return ONLY valid JSON. No preamble, no markdown.
        """

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "prompts": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "sceneIndex": .object(["type": .string("integer")]),
                            "musicPrompt": .object([
                                "type": .string("string"),
                                "description": .string("Exactly two words: adjective + noun")
                            ])
                        ]),
                        "required": .array([
                            .string("sceneIndex"),
                            .string("musicPrompt")
                        ]),
                        "additionalProperties": .bool(false)
                    ])
                ])
            ]),
            "required": .array([.string("prompts")]),
            "additionalProperties": .bool(false)
        ])

        let prompt = """
        Write a TWO-WORD vibe for each scene below.
        Remember: EXACTLY two words per vibe (adjective + noun).

        \(scenesText)
        """

        let raw = try await generate(
            system: systemPrompt,
            prompt: prompt,
            schema: schema,
            model: "llama3.2"
        )

        guard let data = raw.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        var decoded = try JSONDecoder().decode(AIMusicPromptsResponse.self, from: data)

        // Safety net — trim any prompts longer than 2 words
        decoded = AIMusicPromptsResponse(prompts: decoded.prompts.map { item in
            let words = item.musicPrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }

            guard words.count > 2 else { return item }

            let truncated = words.prefix(2).joined(separator: " ")
            print("   ⚠️ Trimmed prompt [\(item.sceneIndex)]: '\(item.musicPrompt)' → '\(truncated)'")
            return AISceneMusicPrompt(sceneIndex: item.sceneIndex, musicPrompt: truncated)
        })

        return decoded
    }
}
