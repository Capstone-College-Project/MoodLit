//
//  BookAIAnalyzer.swift
//  MoodLit
//
//  Processes one chapter at a time through a 3-step pipeline:
//
//  Processes one chapter at a time through a 3-step pipeline:
//    STEP 1 – Segment: find scene boundaries within the chapter
//    STEP 2 – Classify: assign an emotion category + intensity to each scene
//    STEP 3 – Apply: convert to SceneTags and save immediately
//
//  NOTE: AIProseScenesResponse, AIProseScene, AISceneClassification,
//        AIMusicPromptsResponse, AISceneMusicPrompt are defined in OllamaService.swift

import Foundation

// MARK: - Errors

enum ChapterAnalyzerError: LocalizedError {
    case noChapters
    case invalidChapterIndex
    case noStoryContent
    case segmentationFailed
    case classificationFailed
    case musicPromptGenerationFailed
    case noScenesProduced

    var errorDescription: String? {
        switch self {
        case .noChapters:                  return "This book has no chapters to analyze."
        case .invalidChapterIndex:         return "The selected chapter is invalid."
        case .noStoryContent:              return "This chapter has no story content after filtering metadata."
        case .segmentationFailed:          return "Pass 1 (segmentation) failed to produce scenes."
        case .classificationFailed:        return "Pass 2 (classification) failed to assign emotions."
        case .musicPromptGenerationFailed: return "Pass 3 (music prompts) failed to generate descriptions."
        case .noScenesProduced:            return "No valid scenes were produced for this chapter."
        }
    }
}

// MARK: - Internal Pipeline Types (private to this file only)

private struct LineAddress {
    let globalIndex: Int
    let pageNumber: Int
    let lineInPage: Int
    let text: String
}

private struct ResolvedScene {
    let sceneIndex: Int
    let startPage: Int
    let startLine: Int
    let endPage: Int
    let endLine: Int
    let summary: String
    let excerpt: String
}

// MARK: - ChapterAnalyzer

final class ChapterAnalyzer {

    // MARK: - Public API

    func analyze(book: Book, playlist: Playlist, chapterIndex: Int) async throws {
        guard !book.chapters.isEmpty else { throw ChapterAnalyzerError.noChapters }
        guard chapterIndex >= 0 && chapterIndex < book.chapters.count else {
            throw ChapterAnalyzerError.invalidChapterIndex
        }

        let chapter = book.chapters[chapterIndex]
        let allowedCategories = playlist.emotions.map { $0.categoryName }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🤖 CHAPTER ANALYSIS — 3-PASS PIPELINE")
        print("📖 Book: \(book.title)")
        print("📑 Chapter \(chapterIndex + 1) of \(book.chapters.count): \(chapter.title)")
        print("📄 Pages: \(chapter.pages.count)")
        print("🎵 Playlist: \(playlist.name) (\(allowedCategories.count) categories)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let lineAddresses = buildLineAddresses(chapter: chapter)
        guard !lineAddresses.isEmpty else { throw ChapterAnalyzerError.noStoryContent }
        print("\n📝 Story lines after filtering: \(lineAddresses.count)")

        // ── PASS 1 ──
        print("\n🔹 PASS 1: Segmenting chapter into scenes...")
        let scenes: [ResolvedScene]
        do {
            scenes = try await runSegmentation(chapter: chapter, lineAddresses: lineAddresses)
        } catch {
            print("   ❌ Segmentation error: \(error.localizedDescription)")
            throw ChapterAnalyzerError.segmentationFailed
        }
        guard !scenes.isEmpty else { throw ChapterAnalyzerError.segmentationFailed }

        print("   ✅ \(scenes.count) scene(s) identified:")
        for s in scenes {
            print("      [\(s.sceneIndex)] P\(s.startPage)L\(s.startLine) → P\(s.endPage)L\(s.endLine)")
            print("           \(s.summary)")
        }

        // ── PASS 2 ──
        print("\n🔹 PASS 2: Classifying scene emotions...")
        let classifications: [AISceneClassification]
        do {
            classifications = try await runClassification(scenes: scenes, allowedCategories: allowedCategories)
        } catch {
            print("   ❌ Classification error: \(error.localizedDescription)")
            throw ChapterAnalyzerError.classificationFailed
        }
        guard !classifications.isEmpty else { throw ChapterAnalyzerError.classificationFailed }

        print("   ✅ \(classifications.count) scene(s) classified:")
        for c in classifications {
            print("      [\(c.sceneIndex)] \(c.categoryName) intensity \(c.intensityLevel)")
        }

        // ── PASS 3 ──
        print("\n🔹 PASS 3: Generating music prompts for streaming...")
        let musicPrompts: [Int: String]
        do {
            musicPrompts = try await runMusicPromptGeneration(scenes: scenes, classifications: classifications)
            print("   ✅ \(musicPrompts.count) music prompt(s) generated:")
            for (idx, prompt) in musicPrompts.sorted(by: { $0.key < $1.key }) {
                print("      [\(idx)] \(prompt)")
            }
        } catch {
            print("   ⚠️ Music prompt generation failed: \(error.localizedDescription)")
            print("   ⚠️ Continuing with emotion tags only")
            musicPrompts = [:]
        }

        // ── BUILD + SAVE ──
        let tags = buildSceneTags(scenes: scenes, classifications: classifications,
                                  musicPrompts: musicPrompts, playlist: playlist)
        guard !tags.isEmpty else { throw ChapterAnalyzerError.noScenesProduced }

        let bookID = book.id
        let chapterPageNumbers = Set(chapter.pages.map { $0.number })

        await MainActor.run {
            let existing = LibraryManager.shared.books.first { $0.id == bookID }?.sceneTags ?? []
            let kept = existing.filter { tag in
                let tagPages = Set(tag.startPage...tag.endPage)
                let touches = !tagPages.isDisjoint(with: chapterPageNumbers)
                return !touches || tag.musicOverride != nil
            }
            let merged = (kept + tags).sorted {
                $0.startPage != $1.startPage ? $0.startPage < $1.startPage : $0.startLine < $1.startLine
            }
            LibraryManager.shared.updateSceneTags(for: bookID, tags: merged)
        }

        // ── REPORT ──
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 CHAPTER REPORT")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  ✅ \(tags.count) scenes saved")
        print("  🎼 \(musicPrompts.count) music prompts attached")
        print("\n  🎭 Categories used:")
        for (catID, ts) in Dictionary(grouping: tags, by: { $0.emotionCategoryID }) {
            let name = playlist.emotions.first(where: { $0.id == catID })?.categoryName ?? "Unknown"
            print("     \(name): \(ts.count) scene(s)")
        }
        print("\n  📡 API calls: 3 (segmentation + classification + music prompts)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - Pass 1

    private func runSegmentation(
        chapter: Chapter,
        lineAddresses: [LineAddress]
    ) async throws -> [ResolvedScene] {

        let chapterProse  = lineAddresses.map { $0.text }.joined(separator: "\n\n")
        let totalLines    = lineAddresses.count
        let minimumScenes = totalLines > 60 ? 3 : (totalLines > 30 ? 2 : 1)

        var bestResponse: AIProseScenesResponse?
        var bestUsableCount = 0

        for attempt in 1...2 {
            let raw = try await OllamaService.shared.segmentChapterIntoScenes(
                chapterTitle: chapter.title,
                chapterProse: chapterProse,
                approximateLineCount: totalLines
            )

            let usableCount = raw.scenes.filter { scene in
                let trimmed = stripQuotes(scene.openingPhrase)
                if trimmed == "..." || trimmed == "…" || trimmed.isEmpty { return false }
                if trimmed.split(separator: " ").count < 4  { return false }
                if trimmed.filter({ $0.isLetter }).count < 10 { return false }
                let lower = trimmed.lowercased()
                if lower.hasPrefix("you divide") || lower.hasPrefix("output json") || lower.hasPrefix("a scene is") { return false }
                return findLineMatchingPhrase(trimmed, in: lineAddresses) != nil
            }.count

            if usableCount >= minimumScenes { bestResponse = raw; break }
            if usableCount > bestUsableCount { bestUsableCount = usableCount; bestResponse = raw }
            if attempt == 1 {
                print("   ⚠️ Pass 1 attempt 1: only \(usableCount) usable scene(s) (need \(minimumScenes)). Retrying...")
            }
        }

        guard let response = bestResponse else {
            print("   ❌ Both attempts failed. Falling back to single scene.")
            return [fallbackSingleScene(lineAddresses: lineAddresses)]
        }

        let validScenes = response.scenes.filter { scene in
            let trimmed = stripQuotes(scene.openingPhrase)
            if trimmed == "..." || trimmed == "…" || trimmed.isEmpty { return false }
            if trimmed.split(separator: " ").count < 4  { return false }
            if trimmed.filter({ $0.isLetter }).count < 10 { return false }
            let lower = trimmed.lowercased()
            return !lower.hasPrefix("you divide") && !lower.hasPrefix("output json") && !lower.hasPrefix("a scene is")
        }

        if validScenes.count < response.scenes.count {
            print("   ⚠️ Rejected \(response.scenes.count - validScenes.count) scenes with invalid opening phrases")
        }

        var sceneStartLines: [(sceneIndex: Int, lineIndex: Int, summary: String)] = []
        for scene in validScenes {
            let cleaned = stripQuotes(scene.openingPhrase)
            if let idx = findLineMatchingPhrase(cleaned, in: lineAddresses) {
                sceneStartLines.append((sceneIndex: scene.sceneIndex, lineIndex: idx, summary: scene.sceneSummary))
            } else {
                print("   ⚠️ Could not match phrase '\(scene.openingPhrase.prefix(40))...' to any line — skipping")
            }
        }

        guard !sceneStartLines.isEmpty else {
            print("   ❌ No phrases matched. Falling back to single scene.")
            return [fallbackSingleScene(lineAddresses: lineAddresses)]
        }

        var sorted = sceneStartLines.sorted { $0.lineIndex < $1.lineIndex }
        var deduped: [(sceneIndex: Int, lineIndex: Int, summary: String)] = []
        for s in sorted { if deduped.last?.lineIndex != s.lineIndex { deduped.append(s) } }
        sorted = deduped

        if sorted[0].lineIndex > 0 {
            sorted[0] = (sceneIndex: 0, lineIndex: 0, summary: sorted[0].summary)
        }

        var resolved: [ResolvedScene] = []
        for (idx, scene) in sorted.enumerated() {
            let start = scene.lineIndex
            let end   = idx + 1 < sorted.count ? sorted[idx + 1].lineIndex - 1 : totalLines - 1
            guard end >= start else { print("   ⚠️ Invalid scene range \(start)-\(end) — skipping"); continue }
            resolved.append(ResolvedScene(
                sceneIndex: idx,
                startPage: lineAddresses[start].pageNumber, startLine: lineAddresses[start].lineInPage,
                endPage:   lineAddresses[end].pageNumber,   endLine:   lineAddresses[end].lineInPage,
                summary: scene.summary,
                excerpt: buildExcerpt(from: lineAddresses, start: start, end: end)
            ))
        }

        // Merge tiny scenes
        var merged: [ResolvedScene] = []
        for scene in resolved {
            let len = scene.endPage == scene.startPage ? scene.endLine - scene.startLine + 1 : 100
            if len < 10, let last = merged.last {
                merged[merged.count - 1] = ResolvedScene(
                    sceneIndex: last.sceneIndex,
                    startPage: last.startPage, startLine: last.startLine,
                    endPage: scene.endPage,    endLine: scene.endLine,
                    summary: last.summary,     excerpt: last.excerpt
                )
            } else {
                merged.append(scene)
            }
        }

        let reindexed = merged.enumerated().map { i, s in
            ResolvedScene(sceneIndex: i, startPage: s.startPage, startLine: s.startLine,
                          endPage: s.endPage, endLine: s.endLine, summary: s.summary, excerpt: s.excerpt)
        }
        return splitOversizedScenes(reindexed, lineAddresses: lineAddresses)
    }

    private func splitOversizedScenes(
        _ scenes: [ResolvedScene],
        lineAddresses: [LineAddress],
        maxLines: Int = 25
    ) -> [ResolvedScene] {
        var result: [ResolvedScene] = []
        for scene in scenes {
            guard
                let sg = lineAddresses.firstIndex(where: { $0.pageNumber == scene.startPage && $0.lineInPage == scene.startLine }),
                let eg = lineAddresses.firstIndex(where: { $0.pageNumber == scene.endPage   && $0.lineInPage == scene.endLine })
            else { result.append(scene); continue }

            let length = eg - sg + 1
            guard length > maxLines else { result.append(scene); continue }

            let chunks = max(2, (length + maxLines - 1) / maxLines)
            let size   = length / chunks
            for i in 0..<chunks {
                let cs = sg + i * size
                let ce = i == chunks - 1 ? eg : cs + size - 1
                result.append(ResolvedScene(
                    sceneIndex: 0,
                    startPage: lineAddresses[cs].pageNumber, startLine: lineAddresses[cs].lineInPage,
                    endPage:   lineAddresses[ce].pageNumber, endLine:   lineAddresses[ce].lineInPage,
                    summary: i == 0 ? scene.summary : "Continuation of scene",
                    excerpt: buildExcerpt(from: lineAddresses, start: cs, end: ce)
                ))
            }
        }
        return result.enumerated().map { i, s in
            ResolvedScene(sceneIndex: i, startPage: s.startPage, startLine: s.startLine,
                          endPage: s.endPage, endLine: s.endLine, summary: s.summary, excerpt: s.excerpt)
        }
    }

    // MARK: - Pass 2

    private func runClassification(
        scenes: [ResolvedScene],
        allowedCategories: [String]
    ) async throws -> [AISceneClassification] {

        let results = await withTaskGroup(of: AISceneClassification?.self) { group in
            for scene in scenes {
                group.addTask {
                    try? await self.classifyOneScene(scene: scene, allowedCategories: allowedCategories)
                }
            }
            var collected: [AISceneClassification] = []
            for await r in group { if let r { collected.append(r) } }
            return collected
        }

        var final = results
        for idx in Set(scenes.map { $0.sceneIndex }).subtracting(results.map { $0.sceneIndex }).sorted() {
            print("   ⚠️ Scene \(idx) missing — defaulting to \(allowedCategories.first ?? "Neutral") intensity 1")
            final.append(AISceneClassification(sceneIndex: idx,
                categoryName: allowedCategories.first ?? "Neutral", intensityLevel: 1))
        }
        return final.sorted { $0.sceneIndex < $1.sceneIndex }
    }

    private func classifyOneScene(
        scene: ResolvedScene,
        allowedCategories: [String]
    ) async throws -> AISceneClassification {
        return try await OllamaService.shared.classifyOneSceneEmotion(
            sceneText: "Summary: \(scene.summary)\nExcerpt: \(scene.excerpt)",
            sceneIndex: scene.sceneIndex,
            allowedCategories: allowedCategories
        )
    }

    // MARK: - Pass 3

    private func runMusicPromptGeneration(
        scenes: [ResolvedScene],
        classifications: [AISceneClassification]
    ) async throws -> [Int: String] {

        var classByIndex: [Int: AISceneClassification] = [:]
        for c in classifications { classByIndex[c.sceneIndex] = c }

        let scenesText = scenes.compactMap { scene -> String? in
            guard let c = classByIndex[scene.sceneIndex] else { return nil }
            return "SCENE \(scene.sceneIndex):\n  Summary: \(scene.summary)\n  Emotion: \(c.categoryName)\n  Intensity: \(c.intensityLevel)"
        }.joined(separator: "\n\n")

        guard !scenesText.isEmpty else { return [:] }

        let response = try await OllamaService.shared.generateMusicPromptsForScenes(scenesText: scenesText)

        var promptByIndex: [Int: String] = [:]
        let validIndices = Set(scenes.map { $0.sceneIndex })
        for p in response.prompts {
            guard validIndices.contains(p.sceneIndex), promptByIndex[p.sceneIndex] == nil else { continue }
            promptByIndex[p.sceneIndex] = p.musicPrompt
        }

        for idx in validIndices.subtracting(promptByIndex.keys).sorted() {
            guard let c = classByIndex[idx] else { continue }
            print("   ⚠️ Pass 3 missed scene \(idx) — using generic fallback")
            promptByIndex[idx] = genericPrompt(for: c.categoryName, intensity: c.intensityLevel)
        }
        return promptByIndex
    }

    private func genericPrompt(for category: String, intensity: Int) -> String {
        switch category.lowercased() {
        case let s where s.contains("battle") || s.contains("rage"):
            return intensity == 3 ? "fierce battle"   : "rising tension"
        case let s where s.contains("sad") || s.contains("mourning") || s.contains("death"):
            return intensity == 3 ? "deep grief"      : "quiet sorrow"
        case let s where s.contains("happy") || s.contains("joy"):
            return intensity == 3 ? "radiant joy"     : "warm light"
        case let s where s.contains("comedy"):
            return "playful spark"
        case let s where s.contains("romance") || s.contains("love"):
            return intensity == 3 ? "burning passion" : "tender warmth"
        case let s where s.contains("mystery") || s.contains("dark") || s.contains("scary"):
            return intensity == 3 ? "dark dread"      : "creeping shadow"
        case let s where s.contains("epic") || s.contains("heroic"):
            return intensity == 3 ? "triumphant rise" : "quiet courage"
        case let s where s.contains("calm") || s.contains("nature"):
            return intensity == 3 ? "vast stillness"  : "gentle calm"
        case let s where s.contains("tension") || s.contains("thriller"):
            return intensity == 3 ? "building dread"  : "quiet unease"
        case let s where s.contains("magic") || s.contains("wonder"):
            return intensity == 3 ? "celestial light" : "soft wonder"
        case let s where s.contains("family") || s.contains("warmth"):
            return "warm home"
        case let s where s.contains("hope") || s.contains("inspire"):
            return intensity == 3 ? "soaring hope"    : "distant light"
        case let s where s.contains("betrayal") || s.contains("anger"):
            return intensity == 3 ? "cold betrayal"   : "bitter silence"
        default:
            return intensity == 3 ? "vast unknown"    : "ambient drift"
        }
    }

    // MARK: - Tag Building

    private func buildSceneTags(
        scenes: [ResolvedScene],
        classifications: [AISceneClassification],
        musicPrompts: [Int: String],
        playlist: Playlist
    ) -> [SceneTag] {
        var classByIndex: [Int: AISceneClassification] = [:]
        for c in classifications { classByIndex[c.sceneIndex] = c }

        var tags: [SceneTag] = []
        for scene in scenes {
            guard let c = classByIndex[scene.sceneIndex] else {
                print("   ⚠️ Scene \(scene.sceneIndex) has no classification — skipped"); continue
            }
            guard let category = playlist.emotions.first(where: {
                $0.categoryName.lowercased() == c.categoryName.lowercased()
            }) else {
                print("   ⚠️ Unknown category '\(c.categoryName)' — scene \(scene.sceneIndex) skipped"); continue
            }
            tags.append(SceneTag(
                id: UUID(),
                startPage: scene.startPage, startLine: scene.startLine,
                endPage:   scene.endPage,   endLine:   scene.endLine,
                emotionCategoryID: category.id,
                intensityLevel: max(1, min(3, c.intensityLevel)),
                musicOverride: nil,
                musicPrompt: musicPrompts[scene.sceneIndex],
                sceneSummary: scene.summary
            ))
        }
        return tags.sorted {
            $0.startPage != $1.startPage ? $0.startPage < $1.startPage : $0.startLine < $1.startLine
        }
    }

    // MARK: - Helpers

    /// Strips all quote characters before phrase validation or matching.
    private func stripQuotes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{201C}", with: "")
            .replacingOccurrences(of: "\u{201D}", with: "")
            .replacingOccurrences(of: "\u{2018}", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'",  with: "")
            .replacingOccurrences(of: "`",  with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findLineMatchingPhrase(_ phrase: String, in lineAddresses: [LineAddress]) -> Int? {
        let normalizedPhrase = normalize(phrase)
        guard !normalizedPhrase.isEmpty else { return nil }

        for (idx, addr) in lineAddresses.enumerated() {
            if normalize(addr.text).contains(normalizedPhrase) { return idx }
        }

        let words = normalizedPhrase.split(separator: " ").map(String.init)
        for wordCount in [8, 5, 3] {
            guard words.count >= wordCount else { continue }
            let prefix = words.prefix(wordCount).joined(separator: " ")
            guard prefix.count >= 8 else { continue }
            for (idx, addr) in lineAddresses.enumerated() {
                if normalize(addr.text).contains(prefix) { return idx }
            }
        }

        guard words.count >= 4 else { return nil }
        let phraseWords = Set(words)
        var bestIdx: Int?
        var bestOverlap = 0
        for (idx, addr) in lineAddresses.enumerated() {
            let overlap = phraseWords.intersection(
                Set(normalize(addr.text).split(separator: " ").map(String.init))
            ).count
            if overlap > bestOverlap { bestOverlap = overlap; bestIdx = idx }
        }
        return bestOverlap >= max(3, Int(Double(phraseWords.count) * 0.6)) ? bestIdx : nil
    }

    private func normalize(_ text: String) -> String {
        var s = text.lowercased()
            .replacingOccurrences(of: "\u{201C}", with: "").replacingOccurrences(of: "\u{201D}", with: "")
            .replacingOccurrences(of: "\u{2018}", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "`",  with: "")
            .replacingOccurrences(of: "\u{2014}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "")
        s = s.replacingOccurrences(of: #"\s+"#,       with: " ",  options: .regularExpression)
        s = s.replacingOccurrences(of: #"[\s\.]+$"#,  with: "",   options: .regularExpression)
        s = s.replacingOccurrences(of: #"[,;:\"\']+$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildExcerpt(from lineAddresses: [LineAddress], start: Int, end: Int) -> String {
        let length = end - start + 1
        guard length > 6 else {
            return lineAddresses[start...end]
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let mid = start + length / 2
        let indices = Array(Set([start, start+1, start+2, mid, mid+1, end-1, end]
            .filter { $0 >= start && $0 <= end })).sorted()
        return indices
            .map { lineAddresses[$0].text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ... ")
    }

    private func fallbackSingleScene(lineAddresses: [LineAddress]) -> ResolvedScene {
        let first = lineAddresses.first!
        let last  = lineAddresses.last!
        return ResolvedScene(
            sceneIndex: 0,
            startPage: first.pageNumber, startLine: first.lineInPage,
            endPage:   last.pageNumber,  endLine:   last.lineInPage,
            summary: "Full chapter",
            excerpt: lineAddresses.prefix(8)
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        )
    }

    private func buildLineAddresses(chapter: Chapter) -> [LineAddress] {
        var addresses: [LineAddress] = []
        var globalIdx = 0
        for page in chapter.pages {
            for (lineInPage, text) in filterMetadata(from: page.lines).enumerated() {
                addresses.append(LineAddress(globalIndex: globalIdx,
                    pageNumber: page.number, lineInPage: lineInPage, text: text))
                globalIdx += 1
            }
        }
        return addresses
    }

    private func filterMetadata(from lines: [String]) -> [String] {
        let skip = ["project gutenberg", "gutenberg.org", "all rights reserved",
                    "table of contents", "*** start of", "*** end of", "oceanofpdf"]
        return lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return false }
            let lower = t.lowercased()
            return !skip.contains(where: { lower.contains($0) })
        }
    }
}
