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
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - AI Pipeline Response Models

/// Pass 1 — scene segmentation response
struct AIScenesResponse: Codable {
    let scenes: [AIFlatScene]
}

struct AIFlatScene: Codable {
    let sceneIndex: Int
    let startLine: Int   // global line index within the chapter (not per-page)
    let endLine: Int
    let sceneSummary: String
}

/// Pass 2 — emotion classification response
struct AIClassificationsResponse: Codable {
    let classifications: [AISceneClassification]
}

struct AISceneClassification: Codable {
    let sceneIndex: Int
    let categoryName: String
    let intensityLevel: Int
}

/// Pass 3 — music prompt generation response
struct AIMusicPromptsResponse: Codable {
    let prompts: [AISceneMusicPrompt]
}

struct AISceneMusicPrompt: Codable {
    let sceneIndex: Int
    let musicPrompt: String
}

// MARK: - Ollama Service

final class OllamaService {
    static let shared = OllamaService()

    // Simulator usually works with localhost.
    // For a real iPhone later, replace with your Mac's local IP.
    private let endpoint = URL(string: "http://192.168.40.5:11434/api/generate")!
    private let defaultModel = "llama3.2"

    private init() {}

    // MARK: - Generic Generate Helper
    
    /// Low-level call to Ollama. Takes a system prompt, user prompt, and JSON schema.
    /// Returns the raw JSON string response that can be decoded by the caller.
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
    //
    // Takes a flat numbered list of story lines (metadata already filtered out)
    // and returns scene boundaries as start/end line indices. The caller is
    // responsible for mapping those global indices back to (page, lineInPage) pairs.
    
    func segmentChapterIntoScenes(
        chapterTitle: String,
        chapterProse: String,   // raw prose, no line numbers
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
                            "sceneIndex": .object(["type": .string("integer")]),
                            "openingPhrase": .object(["type": .string("string")]),
                            "sceneSummary": .object(["type": .string("string")])
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
        
        let raw = try await generate(system: systemPrompt, prompt: prompt, schema: schema,model: "mistral-nemo")
        
        guard let data = raw.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try JSONDecoder().decode(AIProseScenesResponse.self, from: data)
    }
    
    // MARK: - Pass 2: Classify Scenes By Emotion
    //
    // Takes a batch of scenes (each with its text excerpt and summary) and returns
    // an emotional category + intensity + reasoning for each.
    
    func classifySceneEmotions(
        scenesText: String,
        allowedCategories: [String]
    ) async throws -> AIClassificationsResponse {
       
        
        let systemPrompt = """
        You assign an emotion category and intensity to each scene of a story.

        Allowed categories:
        \(allowedCategories.joined(separator: ", "))

        Intensity levels:
        1 = subtle, background presence
        2 = clearly present, building
        3 = overwhelming, peak

        Rules:
        - Pick ONE category per scene based on what the reader FEELS, not the topic.
          Example: "They talked about a battle" is NOT Battle unless there's tension in the scene itself.
        - Evaluate each scene independently. Do NOT carry emotion from previous scenes.
        - Use Neutral only if no emotion is present (pure exposition, transitions).

        Scene Index Rule:
        Each scene has a SCENE INDEX number. Copy that number exactly into sceneIndex.
        Never reuse an index. Never invent one.

        Return ONLY valid JSON matching the expected schema. No preamble, no reasoning text.
        """
        
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "classifications": .object([
                    "type": .string("array"),
                    "items": .object([
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
                ])
            ]),
            "required": .array([.string("classifications")]),
            "additionalProperties": .bool(false)
        ])
        
        let prompt = """
        Classify each scene below.
        
        \(scenesText)
        """
        
        let raw = try await generate(system: systemPrompt, prompt: prompt, schema: schema)
        
        guard let data = raw.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try JSONDecoder().decode(AIClassificationsResponse.self, from: data)
    }
    
    // MARK: - Pass 3: Generate Music Prompts For Scenes
    //
    // Takes all classified scenes from a chapter and returns a short music generation
    // prompt for each one. These prompts are designed to be fed into LatentScore AI
    // or a similar music generator — they describe sonic characteristics, not emotions.
    
    func generateMusicPromptsForScenes(
        scenesText: String        // pre-formatted: scene index + summary + emotion + intensity
    ) async throws -> AIMusicPromptsResponse {
        
        let systemPrompt = """
        You write short "vibe" descriptions for an AI music generator called LatentScore. Each vibe becomes the background music for a single story scene in a reading app.

        ═══════════════════════════════════════
        HOW LATENTSCORE WORKS
        ═══════════════════════════════════════
        LatentScore does NOT understand plot or narrative. It maps your vibe description to a specific combination of these musical parameters:

        Tempo: very slow, slow, medium, fast, very fast
        Density: 2, 3, 4, 5, 6 (sparse → dense)
        Motion: static, slow, medium, fast, chaotic
        Brightness: very dark, dark, medium, bright, very bright
        Reverb: dry, small, medium, large, vast
        Mode: major, minor, dorian, mixolydian

        Instrument styles it can produce:
        - Bass: drone, sustained, pulsing, walking, sub pulse, octave, arp bass
        - Pad: warm slow, dark sustained, cinematic, ambient drift, stacked fifths, bright open
        - Melody: contemplative, rising, falling, minimal, ornamental, heroic, call response
        - Rhythm: none, minimal, heartbeat, soft four, electronic, military, kit light, kit medium, brush
        - Texture: none, shimmer, vinyl crackle, breath, stars, glitch, noise wash, crystal, pad whisper
        - Accent: none, bells, pluck, chime, brass hit, wind

        ═══════════════════════════════════════
        HOW TO WRITE A VIBE
        ═══════════════════════════════════════
        A good vibe is 4-12 words that describe a mood, atmosphere, or setting the scene evokes. Think of it as describing a place or feeling, not as a shopping list of instruments.

        EXCELLENT VIBES (what LatentScore loves):
        - "warm sunset over water"
        - "lone candle in a cold cathedral"
        - "dark forest at midnight, distant wolves"
        - "heroic cavalry charge at dawn"
        - "empty throne room after a funeral"
        - "first snowfall in a quiet village"
        - "moonlit duel on a rooftop"
        - "mourning a lost homeland"
        - "jazz cafe at midnight"
        - "stormy cliff overlooking the sea"

        BAD VIBES (avoid these):
        - "Slow melancholic strings with sparse piano, distant reverb, 60 BPM" (lists instruments — LatentScore picks those itself)
        - "Music for when Arthas learns Stormwind fell" (plot, not mood)
        - "Sad scene with building tension" (too abstract)
        - "Sad" (too short, not evocative)

        ═══════════════════════════════════════
        MATCHING EMOTION AND INTENSITY
        ═══════════════════════════════════════
        The scene's emotion category and intensity hint at what the music should feel like:

        INTENSITY 1 (subtle): Use words like "distant", "quiet", "alone", "still", "soft", "first light"
        INTENSITY 2 (clear): Use words like "rising", "gathering", "deepening", "steady", "approaching"  
        INTENSITY 3 (peak): Use words like "overwhelming", "crashing", "burning", "shattered", "final"

        Category examples (not rules — write what fits the scene):
        - Battle → "cavalry charge", "swords clashing in rain"
        - Sadness → "empty cathedral", "widow at the grave"
        - Fear → "footsteps behind locked doors"
        - Joy → "children running through wildflowers"
        - Tension → "knife hidden under the table"
        - Calm → "morning tea by the window"
        - Romance → "first kiss in candlelight"
        - Magic → "spell ignites in empty air"
        - Heroic → "banner raised on a hilltop"
        - Death → "snow falling on a still body"
        - Mystery → "footprints leading into fog"
        - Wonder → "comet over a silent city"
        - Loneliness → "lighthouse in endless sea"

        ═══════════════════════════════════════
        RULES
        ═══════════════════════════════════════
        - 4-12 words per vibe. Shorter is usually better.
        - Use evocative imagery, not technical audio terms.
        - Never list instruments or BPM — LatentScore picks those.
        - Never mention plot, characters, or proper nouns.
        - Match the EMOTION and INTENSITY provided, not the scene summary's plot.
        - Vary vibes across scenes — don't repeat the same imagery.

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
                            "musicPrompt": .object(["type": .string("string")])
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
        Generate a music prompt for each scene below. Each prompt should describe the SOUND a music AI should produce.
        
        \(scenesText)
        """
        
        let raw = try await generate(system: systemPrompt, prompt: prompt, schema: schema, model: "mistral-nemo")
        
        guard let data = raw.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try JSONDecoder().decode(AIMusicPromptsResponse.self, from: data)
    }
    
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
        
        let prompt = """
        Classify this scene:
        
        \(sceneText)
        """
        
        let raw = try await generate(system: systemPrompt, prompt: prompt, schema: schema)
        
        guard let data = raw.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        // The schema forces a single object, so decode directly (not an array)
        let decoded = try JSONDecoder().decode(AISceneClassification.self, from: data)
        
        // Defensive: force sceneIndex to match what we asked for
        // (in case the model still puts the wrong number)
        return AISceneClassification(
            sceneIndex: sceneIndex,
            categoryName: decoded.categoryName,
            intensityLevel: decoded.intensityLevel
        )
    }
}
