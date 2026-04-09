//
//  BookAIAnalyzer.swift
//  MoodLit
//
//  Processes one chapter at a time through a 3-step pipeline:
//
//  For each chapter:
//    STEP 1 – Segment: find scene boundaries within the chapter
//    STEP 2 – Classify: assign an emotion category + intensity to each scene
//    STEP 3 – Apply: convert to SceneTags and save immediately
//
//  Tags are written to the book after every chapter, so the user can
//  open the book and start reading with music while analysis is still running.

import Foundation

// MARK: - Errors

enum BookAIAnalyzerError: LocalizedError {
    case noPages
    case noResolvedTags

    var errorDescription: String? {
        switch self {
        case .noPages:        return "This book has no pages to analyse."
        case .noResolvedTags: return "AI finished but produced no valid tags."
        }
    }
}

// MARK: - Internal pipeline models

private struct SceneSegment: Codable {
    let chapterIndex: Int
    let sceneIndex: Int
    let startPage: Int
    let startLine: Int
    let endPage: Int
    let endLine: Int
    let sceneSummary: String
}

private struct SegmentationResponse: Codable {
    let scenes: [SceneSegment]
}

private struct SceneEmotion: Codable {
    let chapterIndex: Int
    let sceneIndex: Int
    let categoryName: String
    let intensityLevel: Int
    let reasoning: String
}

private struct ClassificationResponse: Codable {
    let classifications: [SceneEmotion]
}

// MARK: - BookAIAnalyzer

final class BookAIAnalyzer {

    // MARK: - Public entry point

    func analyzeEntireBook(book: Book, playlist: Playlist) async throws {
        let pages = book.allPages
        guard !pages.isEmpty else { throw BookAIAnalyzerError.noPages }

        let allowedCategories = playlist.emotions.map { $0.categoryName }
        let chapters = book.chapters

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🤖 CHAPTER-BY-CHAPTER AI ANALYSIS STARTED")
        print("📖 \(book.title)  (\(chapters.count) chapters, \(pages.count) pages)")
        print("🎵 Playlist: \(playlist.name)")
        print("🏷  Categories: \(allowedCategories.joined(separator: " · "))")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        var totalTagsApplied = 0
        var rollingContext = book.aiContext

        for (chapterIdx, chapter) in chapters.enumerated() {
            print("\n📖 Chapter \(chapterIdx + 1)/\(chapters.count): \"\(chapter.title)\"")

            let chapterPages = chapter.pages

            // STEP 1: Segment
            let scenes = await segmentChapter(chapter: chapter, chapterIndex: chapterIdx)
            if scenes.isEmpty {
                print("   ⚠️ No scenes found — skipping")
                continue
            }
            print("   ✅ \(scenes.count) scene(s) identified")

            // STEP 2: Classify
            let classifications = await classifyScenes(
                scenes,
                book: book,
                allowedCategories: allowedCategories,
                priorContext: rollingContext
            )
            if classifications.isEmpty {
                print("   ⚠️ No classifications returned — skipping")
                continue
            }
            print("   ✅ \(classifications.count) scene(s) classified")

            // STEP 3: Build and save tags immediately
            let rawTags = buildTags(from: classifications, scenes: scenes, playlist: playlist)
            print("   🔍 rawTags count: \(rawTags.count), pages: \(Set(rawTags.map{$0.page}).sorted())")
            print("   🔍 chapterPages: \(chapterPages.map{$0.number})")
            let filledTags = fillGaps(tags: rawTags, pages: chapterPages, playlist: playlist)
            print("   🔍 filledTags count: \(filledTags.count)")

            if !filledTags.isEmpty {
                let bookID = book.id
                await MainActor.run {
                    let existingTags = LibraryManager.shared.books
                        .first { $0.id == bookID }?.sceneTags ?? []
                    let chapterPageNumbers = Set(chapterPages.map { $0.number })
                    let kept = existingTags.filter {
                        !chapterPageNumbers.contains($0.page) || $0.musicOverride != nil
                    }
                    LibraryManager.shared.updateSceneTags(for: bookID, tags: kept + filledTags)
                }
                totalTagsApplied += filledTags.count
                print("   💾 Saved \(filledTags.count) tag(s) — total: \(totalTagsApplied)")
            }

            // Update rolling context
            let chapterSummary = classifications.suffix(2)
                .map { "\($0.categoryName) (intensity \($0.intensityLevel)): \($0.reasoning)" }
                .joined(separator: " ")
            rollingContext = buildRollingContext(
                previousContext: rollingContext,
                aiSummary: "Ch\(chapterIdx + 1): \(chapterSummary)"
            )
            let contextSnapshot = rollingContext
            let bookID = book.id
            await MainActor.run {
                LibraryManager.shared.updateAIContext(for: bookID, context: contextSnapshot)
            }
        }

        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if totalTagsApplied == 0 {
            print("❌ No tags produced.")
            throw BookAIAnalyzerError.noResolvedTags
        } else {
            print("📊 DONE: \(totalTagsApplied) total tags applied")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // Backward-compat shim
    func analyze(book: Book, playlist: Playlist, startPageIndex: Int) async throws {
        try await analyzeEntireBook(book: book, playlist: playlist)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 1 — Segment one chapter into scenes
    // ═══════════════════════════════════════════════════════════════════════

    // MARK: - Public: analyse a single chapter by index
    // Used by the chapter picker sheet so the user can choose specific chapters.
    func analyzeChapter(at chapterIndex: Int, book: Book, playlist: Playlist) async {
        guard chapterIndex < book.chapters.count else { return }
        let chapter = book.chapters[chapterIndex]
        let allowedCategories = playlist.emotions.map { $0.categoryName }

        print("📖 Analysing section \(chapterIndex + 1): \"\(chapter.title)\"")

        let scenes = await segmentChapter(chapter: chapter, chapterIndex: chapterIndex)
        guard !scenes.isEmpty else { print("   ⚠️ No scenes found"); return }

        let classifications = await classifyScenes(
            scenes, book: book,
            allowedCategories: allowedCategories,
            priorContext: book.aiContext
        )
        guard !classifications.isEmpty else { print("   ⚠️ No classifications"); return }

        let rawTags = buildTags(from: classifications, scenes: scenes, playlist: playlist)
        print("   🔍 rawTags: \(rawTags.count), pages in tags: \(Set(rawTags.map{$0.page}).sorted())")
        print("   🔍 chapter pages: \(chapter.pages.map{$0.number})")
        let filledTags = fillGaps(tags: rawTags, pages: chapter.pages, playlist: playlist)
        print("   🔍 filledTags: \(filledTags.count), categories: \(Set(filledTags.map{$0.emotionCategoryID}).count) unique")
        guard !filledTags.isEmpty else { return }

        let bookID = book.id
        let chapterPageNumbers = Set(chapter.pages.map { $0.number })
        await MainActor.run {
            let existingTags = LibraryManager.shared.books
                .first { $0.id == bookID }?.sceneTags ?? []
            let kept = existingTags.filter {
                !chapterPageNumbers.contains($0.page) || $0.musicOverride != nil
            }
            LibraryManager.shared.updateSceneTags(for: bookID, tags: kept + filledTags)
        }
        print("   💾 Saved \(filledTags.count) tag(s) for section \(chapterIndex + 1)")
    }

    private func segmentChapter(chapter: Chapter, chapterIndex: Int) async -> [SceneSegment] {
        // Build a flat numbered list of all story lines in the chapter.
        // We avoid page numbers entirely — the AI gets global line indices (0, 1, 2...)
        // and we map them back to pages ourselves in buildTags.
        let maxLines = 150
        var allLines: [(globalIdx: Int, pageNumber: Int, lineInPage: Int, text: String)] = []

        for page in chapter.pages {
            let storyLines = filterMetadata(from: page.lines)
            for (lineInPage, text) in storyLines.enumerated() {
                guard allLines.count < maxLines else { break }
                allLines.append((
                    globalIdx: allLines.count,
                    pageNumber: page.number,
                    lineInPage: lineInPage,
                    text: text
                ))
            }
            if allLines.count >= maxLines { break }
        }

        guard !allLines.isEmpty else {
            print("   ⚠️ Chapter \(chapterIndex) has no story content after filtering")
            return []
        }

        let truncated = allLines.count >= maxLines
        let flatText = allLines.map { "  \($0.globalIdx): \($0.text)" }.joined(separator: "\n")
        let suffix = truncated ? "\n[truncated at line \(maxLines - 1)]" : ""
        let chapterText = "CHAPTER — \(chapter.title)\nTotal lines: 0 to \(allLines.count - 1)\n\(flatText)\(suffix)"

        let systemPrompt = """
        You are a narrative structure analyst. Find every scene boundary in this chapter.

        A SCENE BOUNDARY occurs when:
        • Location changes — characters move somewhere different
        • Time jumps forward or backward
        • Emotional tone shifts significantly (calm → tense, grief → action)
        • Point-of-view character changes
        • A major plot beat concludes and a new one begins

        RULES:
        - Lines are numbered from 0. Use ONLY the line numbers shown in the input.
        - startLine and endLine are the global line numbers (the numbers before the colon).
        - No scenes shorter than 3 lines.
        - Skip metadata lines — only tag story narration, dialogue, and description.
        - sceneIndex is 0-based (first scene = 0, second = 1, etc).
        - Every line must be covered — no gaps between scenes.
        - The last scene must end at the last line number shown.

        Return ONLY valid JSON. No markdown, no explanation.
        """

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "scenes": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "sceneIndex":   .object(["type": .string("integer")]),
                            "startLine":    .object(["type": .string("integer")]),
                            "endLine":      .object(["type": .string("integer")]),
                            "sceneSummary": .object(["type": .string("string")])
                        ]),
                        "required": .array([
                            .string("sceneIndex"),
                            .string("startLine"),
                            .string("endLine"),
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
        Find all scene boundaries in the chapter below.
        Use the line numbers exactly as shown (the number before the colon).

        \(chapterText)
        """

        // Simplified response model — no page numbers
        struct FlatScene: Codable {
            let sceneIndex: Int
            let startLine: Int
            let endLine: Int
            let sceneSummary: String
        }
        struct FlatSegmentationResponse: Codable {
            let scenes: [FlatScene]
        }

        do {
            let raw = try await OllamaService.shared.generate(
                system: systemPrompt,
                prompt: prompt,
                schema: schema
            )
            guard let data = raw.data(using: .utf8) else { return [] }
            let decoded = try JSONDecoder().decode(FlatSegmentationResponse.self, from: data)

            // Map flat line indices back to real page numbers and per-page line indices
            return decoded.scenes.compactMap { flat -> SceneSegment? in
                guard flat.startLine <= flat.endLine,
                      flat.startLine < allLines.count,
                      flat.endLine < allLines.count else { return nil }

                let startEntry = allLines[flat.startLine]
                let endEntry   = allLines[flat.endLine]

                return SceneSegment(
                    chapterIndex: chapterIndex,
                    sceneIndex: flat.sceneIndex,
                    startPage: startEntry.pageNumber,
                    startLine: startEntry.lineInPage,
                    endPage: endEntry.pageNumber,
                    endLine: endEntry.lineInPage,
                    sceneSummary: flat.sceneSummary
                )
            }
        } catch {
            print("   ⚠️ Segmentation error ch\(chapterIndex): \(error.localizedDescription)")
            return []
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 2 — Classify scenes by emotion
    // ═══════════════════════════════════════════════════════════════════════

    private func classifyScenes(
        _ scenes: [SceneSegment],
        book: Book,
        allowedCategories: [String],
        priorContext: String
    ) async -> [SceneEmotion] {

        var allClassifications: [SceneEmotion] = []
        let batchSize = 5
        var idx = 0

        while idx < scenes.count {
            let batchEnd = min(idx + batchSize, scenes.count)
            let batch = Array(scenes[idx..<batchEnd])

            let sceneDescriptions = batch.map { scene in
                let excerpt = extractExcerpt(from: book, scene: scene, maxLines: 8)
                return """
                SCENE ch\(scene.chapterIndex)-s\(scene.sceneIndex):
                  Summary: \(scene.sceneSummary)
                  Pages: \(scene.startPage) line \(scene.startLine) to \(scene.endPage) line \(scene.endLine)
                  Excerpt: \(excerpt)
                """
            }.joined(separator: "\n\n")

            let contextBlock = priorContext.isEmpty
                ? "This is the start of the book. Be conservative with intensity (1-2)."
                : "Recent emotional context:\n\(priorContext)"

            let systemPrompt = """
            You are an expert at identifying the emotional tone of literary scenes for a reading-with-music app.
            Assign one emotional music category and an intensity level to each scene.

            ALLOWED CATEGORIES (use EXACTLY as written):
            \(allowedCategories.joined(separator: ", "))

            HOW TO CHOOSE — read the EXCERPT carefully, then ask:
            1. What does the point-of-view character FEEL in THIS specific scene?
            2. What would a film composer score THIS moment as?
            3. What tone does the prose create in the reader of THIS scene?

            CRITICAL RULES:
            - You MUST base your answer on the TEXT EXCERPT provided, not just the summary.
            - If scenes have DIFFERENT excerpts and DIFFERENT summaries, they likely need DIFFERENT categories.
            - Do NOT assign the same category to every scene just because they are in the same chapter.
            - Each scene must be evaluated INDEPENDENTLY on its own excerpt.

            AVOID THESE MISTAKES:
            - Talking ABOUT a battle is not Battle / Rage. Use Tension / Thriller or Sad / Mourning.
            - Quiet travel is not Epic / Heroic. Use Calm / Nature.
            - Fearful escape = Tension / Thriller, not Epic / Heroic.
            - Epic / Heroic needs real triumph or bravery from the POV character.
            - A happy childhood memory = Happy / Joy or Romance / Love, NOT Sad / Mourning.
            - A character meeting someone kind = Romance / Love or Happy / Joy, NOT Sad / Mourning.
            - Calm description of family life = Calm / Nature or Happy / Joy, NOT Sad / Mourning.

            INTENSITY: 1 = subtle, 2 = building, 3 = peak.
            CONTINUITY: Only keep the same category as the previous scene if the TEXT supports the same mood.

            Return ONLY valid JSON. No preamble, no markdown.
            """

            let schema: JSONValue = .object([
                "type": .string("object"),
                "properties": .object([
                    "classifications": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "chapterIndex":   .object(["type": .string("integer")]),
                                "sceneIndex":     .object(["type": .string("integer")]),
                                "categoryName":   .object([
                                    "type": .string("string"),
                                    "enum": .array(allowedCategories.map { .string($0) })
                                ]),
                                "intensityLevel": .object([
                                    "type": .string("integer"),
                                    "enum": .array([.int(1), .int(2), .int(3)])
                                ]),
                                "reasoning": .object(["type": .string("string")])
                            ]),
                            "required": .array([
                                .string("chapterIndex"), .string("sceneIndex"),
                                .string("categoryName"), .string("intensityLevel"),
                                .string("reasoning")
                            ]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ]),
                "required": .array([.string("classifications")]),
                "additionalProperties": .bool(false)
            ])

            let prompt = """
            CONTEXT:
            \(contextBlock)

            Classify each scene below:

            \(sceneDescriptions)
            """

            do {
                let raw = try await OllamaService.shared.generate(
                    system: systemPrompt,
                    prompt: prompt,
                    schema: schema
                )
                guard let data = raw.data(using: .utf8) else { idx = batchEnd; continue }
                let decoded = try JSONDecoder().decode(ClassificationResponse.self, from: data)
                allClassifications.append(contentsOf: decoded.classifications)
                for c in decoded.classifications {
                    print("   ch\(c.chapterIndex)-s\(c.sceneIndex): \(c.categoryName) [\(c.intensityLevel)]")
                }
            } catch {
                print("   ⚠️ Classification error scenes \(idx)-\(batchEnd - 1): \(error.localizedDescription)")
            }

            idx = batchEnd
        }

        return allClassifications
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 3 — Build SceneTags
    // ═══════════════════════════════════════════════════════════════════════

    private func buildTags(
        from classifications: [SceneEmotion],
        scenes: [SceneSegment],
        playlist: Playlist
    ) -> [SceneTag] {

        var sceneMap: [String: SceneSegment] = [:]
        for scene in scenes {
            sceneMap["\(scene.chapterIndex)-\(scene.sceneIndex)"] = scene
        }

        var tags: [SceneTag] = []

        for c in classifications {
            let key = "\(c.chapterIndex)-\(c.sceneIndex)"
            guard let scene = sceneMap[key] else { continue }
            guard let category = playlist.emotions.first(where: {
                $0.categoryName.lowercased() == c.categoryName.lowercased()
            }) else { continue }

            if scene.startPage == scene.endPage {
                tags.append(SceneTag(
                    page: scene.startPage,
                    startLine: scene.startLine,
                    endLine: scene.endLine,
                    emotionCategoryID: category.id,
                    intensityLevel: c.intensityLevel
                ))
            } else {
                for pageNum in scene.startPage...scene.endPage {
                    let startLine = pageNum == scene.startPage ? scene.startLine : 0
                    let endLine   = pageNum == scene.endPage   ? scene.endLine   : 999
                    tags.append(SceneTag(
                        page: pageNum,
                        startLine: startLine,
                        endLine: endLine,
                        emotionCategoryID: category.id,
                        intensityLevel: c.intensityLevel
                    ))
                }
            }
        }

        return tags
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════════

    // Strips Gutenberg headers, copyright blocks, and other non-story lines.
    private func filterMetadata(from lines: [String]) -> [String] {
        let skipPatterns = [
            "project gutenberg", "gutenberg", "www.gutenberg", "gutenberg.org",
            "copyright", "all rights reserved", "public domain",
            "produced by", "transcribed by", "distributed by",
            "isbn", "published by", "first published",
            "table of contents", "contents", "index",
            "dedication", "acknowledgment", "acknowledgement",
            "also by", "other books by", "about the author",
            "end of the project", "end of this project",
            "terms of use", "license", "terms and conditions",
            "small print", "fine print",
            "this ebook", "this e-book", "this file",
            "chapter list", "*** start", "*** end",
            "encoding:", "character set",
        ]

        var inMetadataBlock = false
        var storyStarted = false
        var result: [String] = []

        for line in lines {
            let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty lines don't count as metadata
            if trimmed.isEmpty {
                if storyStarted { result.append(line) }
                continue
            }

            // Detect Gutenberg block markers
            if lower.contains("*** start of") || lower.contains("***start of") {
                inMetadataBlock = false
                storyStarted = false
                continue
            }
            if lower.contains("*** end of") || lower.contains("***end of") {
                inMetadataBlock = true
                continue
            }
            if inMetadataBlock { continue }

            // Skip lines that are clearly metadata
            let isMetadata = skipPatterns.contains(where: { lower.contains($0) })
                || (lower.hasPrefix("chapter") && trimmed.count < 30)
                || (lower.hasPrefix("part") && trimmed.count < 20)
                || (lower.hasPrefix("volume") && trimmed.count < 20)
                || (lower.hasPrefix("book ") && trimmed.count < 20)
                || (trimmed.count < 4)  // very short lines are usually headers/page numbers

            if isMetadata && !storyStarted {
                continue  // skip pre-story metadata
            }

            // Once we see a line that looks like real prose, mark story as started
            if !storyStarted && trimmed.count > 20 && !isMetadata {
                storyStarted = true
            }

            if storyStarted {
                result.append(line)
            }
        }

        return result
    }

    private func extractExcerpt(from book: Book, scene: SceneSegment, maxLines: Int) -> String {
        let allPages = book.allPages
        guard let page = allPages.first(where: { $0.number == scene.startPage }) else {
            return "(unavailable)"
        }
        let lines = page.lines
        let start = max(0, min(scene.startLine, lines.count - 1))
        let end   = min(lines.count - 1, start + maxLines - 1)
        guard start <= end else { return "(unavailable)" }
        return lines[start...end]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func fillGaps(tags: [SceneTag], pages: [BookPage], playlist: Playlist) -> [SceneTag] {
        var result = tags

        for page in pages {
            let clamped: [SceneTag] = result
                .filter { $0.page == page.number }
                .map { tag in
                    guard tag.endLine >= page.lines.count else { return tag }
                    return SceneTag(
                        id: tag.id,
                        page: tag.page,
                        startLine: tag.startLine,
                        endLine: page.lines.count - 1,
                        emotionCategoryID: tag.emotionCategoryID,
                        intensityLevel: tag.intensityLevel,
                        musicOverride: tag.musicOverride
                    )
                }

            result.removeAll { $0.page == page.number }
            result.append(contentsOf: clamped)

            let pageTags = clamped.sorted { $0.startLine < $1.startLine }
            let totalLines = page.lines.count
            guard totalLines > 0 else { continue }

            guard let fallbackID = pageTags.first?.emotionCategoryID ?? playlist.emotions.first?.id
            else { continue }

            var covered = Set<Int>()
            for tag in pageTags {
                for line in tag.startLine...tag.endLine { covered.insert(line) }
            }

            var gapStart: Int? = nil
            for line in 0..<totalLines {
                if !covered.contains(line) {
                    if gapStart == nil { gapStart = line }
                } else if let start = gapStart {
                    let nearest = findNearestCategory(line: start, pageTags: pageTags, fallback: fallbackID)
                    result.append(SceneTag(
                        page: page.number, startLine: start, endLine: line - 1,
                        emotionCategoryID: nearest, intensityLevel: 1
                    ))
                    gapStart = nil
                }
            }
            if let start = gapStart {
                let nearest = findNearestCategory(line: start, pageTags: pageTags, fallback: fallbackID)
                result.append(SceneTag(
                    page: page.number, startLine: start, endLine: totalLines - 1,
                    emotionCategoryID: nearest, intensityLevel: 1
                ))
            }
        }

        return result
    }

    private func findNearestCategory(line: Int, pageTags: [SceneTag], fallback: UUID) -> UUID {
        var bestDist = Int.max
        var bestID   = fallback
        for tag in pageTags {
            let dist = min(abs(tag.startLine - line), abs(tag.endLine - line))
            if dist < bestDist { bestDist = dist; bestID = tag.emotionCategoryID }
        }
        return bestID
    }

    private func buildRollingContext(previousContext: String, aiSummary: String) -> String {
        guard !aiSummary.isEmpty else { return previousContext }
        let combined = previousContext.isEmpty ? aiSummary : previousContext + "\n" + aiSummary
        guard combined.count > 1000 else { return combined }
        let trimmed = String(combined.suffix(1000))
        if let nl = trimmed.firstIndex(of: "\n") {
            return String(trimmed[trimmed.index(after: nl)...])
        }
        return trimmed
    }
}
