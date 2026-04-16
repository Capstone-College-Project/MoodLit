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


/// Pass 1 v2 — prose-based scene segmentation response.
/// The AI returns scene boundaries as quoted opening phrases that
/// Swift then maps back to line indices.
struct AIProseScenesResponse: Codable {
    let scenes: [AIProseScene]
}

struct AIProseScene: Codable {
    let sceneIndex: Int
    let openingPhrase: String     // a short quoted phrase that starts this scene
    let sceneSummary: String
}

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
        case .noChapters: return "This book has no chapters to analyze."
        case .invalidChapterIndex: return "The selected chapter is invalid."
        case .noStoryContent: return "This chapter has no story content after filtering metadata."
        case .segmentationFailed: return "Pass 1 (segmentation) failed to produce scenes."
        case .classificationFailed: return "Pass 2 (classification) failed to assign emotions."
        case .musicPromptGenerationFailed: return "Pass 3 (music prompts) failed to generate descriptions."
        case .noScenesProduced: return "No valid scenes were produced for this chapter."
        }
    }
}

// MARK: - Internal Pipeline Types

/// Maps a flat global line index to its real (page, line) position in the chapter.
private struct LineAddress {
    let globalIndex: Int
    let pageNumber: Int
    let lineInPage: Int
    let text: String
}

/// A scene with resolved page+line positions, before classification.
private struct ResolvedScene {
    let sceneIndex: Int
    let startPage: Int
    let startLine: Int
    let endPage: Int
    let endLine: Int
    let summary: String
    let excerpt: String  // first ~8 lines, used for classification context
}

// MARK: - ChapterAnalyzer

final class ChapterAnalyzer {
    
    // MARK: - Public API
    
    /// Runs the full 3-pass pipeline on a single chapter:
    ///   Pass 1 — segment chapter into scenes
    ///   Pass 2 — classify each scene's emotion
    ///   Pass 3 — generate music prompts for each scene
    /// Saves all results to the book in one batch.
    func analyze(book: Book, playlist: Playlist, chapterIndex: Int) async throws {
        guard !book.chapters.isEmpty else {
            throw ChapterAnalyzerError.noChapters
        }
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
        
        // ── Build flat line list (filter metadata) ──
        let lineAddresses = buildLineAddresses(chapter: chapter)
        
        guard !lineAddresses.isEmpty else {
            throw ChapterAnalyzerError.noStoryContent
        }
        
        print("\n📝 Story lines after filtering: \(lineAddresses.count)")
        
        // ── PASS 1: Segment ──
        
        
        print("\n🔹 PASS 1: Segmenting chapter into scenes...")
        
        let scenes: [ResolvedScene]
        do {
            scenes = try await runSegmentation(
                chapter: chapter,
                lineAddresses: lineAddresses
            )
        } catch {
            print("   ❌ Segmentation error: \(error.localizedDescription)")
            throw ChapterAnalyzerError.segmentationFailed
        }
        
        guard !scenes.isEmpty else {
            throw ChapterAnalyzerError.segmentationFailed
        }
        
        print("   ✅ \(scenes.count) scene(s) identified:")
        for scene in scenes {
            print("      [\(scene.sceneIndex)] P\(scene.startPage)L\(scene.startLine) → P\(scene.endPage)L\(scene.endLine)")
            print("           \(scene.summary)")
        }
        
        // ── PASS 2: Classify ──
        print("\n🔹 PASS 2: Classifying scene emotions...")
        
        let classifications: [AISceneClassification]
        do {
            classifications = try await runClassification(
                scenes: scenes,
                allowedCategories: allowedCategories,
            )
        } catch {
            print("   ❌ Classification error: \(error.localizedDescription)")
            throw ChapterAnalyzerError.classificationFailed
        }
        
        guard !classifications.isEmpty else {
            throw ChapterAnalyzerError.classificationFailed
        }
        
        print("   ✅ \(classifications.count) scene(s) classified:")
        for c in classifications {
            print("      [\(c.sceneIndex)] \(c.categoryName) intensity \(c.intensityLevel)")
        }
        
        // ── PASS 3: Generate Music Prompts ──
        print("\n🔹 PASS 3: Generating music prompts for streaming...")
        
        let musicPrompts: [Int: String]
        do {
            musicPrompts = try await runMusicPromptGeneration(
                scenes: scenes,
                classifications: classifications
            )
            print("   ✅ \(musicPrompts.count) music prompt(s) generated:")
            for (idx, prompt) in musicPrompts.sorted(by: { $0.key < $1.key }) {
                print("      [\(idx)] \(prompt)")
            }
        } catch {
            // Pass 3 failure is non-fatal — we still save emotion tags without prompts
            print("   ⚠️ Music prompt generation failed: \(error.localizedDescription)")
            print("   ⚠️ Continuing with emotion tags only — stream mode will fall back to playlist")
            musicPrompts = [:]
        }
        
        // ── BUILD TAGS ──
        let tags = buildSceneTags(
            scenes: scenes,
            classifications: classifications,
            musicPrompts: musicPrompts,
            playlist: playlist
        )
        
        guard !tags.isEmpty else {
            throw ChapterAnalyzerError.noScenesProduced
        }
        
        // ── SAVE TAGS ──
        let bookID = book.id
        let chapterPageNumbers = Set(chapter.pages.map { $0.number })
        
        await MainActor.run {
            let existing = LibraryManager.shared.books
                .first { $0.id == bookID }?.sceneTags ?? []
            
            // Keep tags that don't touch this chapter at all (preserves other chapters)
            // and any tags that have a user-set music override
            let kept = existing.filter { tag in
                let tagPages = Set(tag.startPage...tag.endPage)
                let touchesThisChapter = !tagPages.isDisjoint(with: chapterPageNumbers)
                return !touchesThisChapter || tag.musicOverride != nil
            }
            
            let merged = (kept + tags).sorted { lhs, rhs in
                if lhs.startPage != rhs.startPage { return lhs.startPage < rhs.startPage }
                return lhs.startLine < rhs.startLine
            }
            
            LibraryManager.shared.updateSceneTags(for: bookID, tags: merged)
        }
        
        // ── REPORT ──
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 CHAPTER REPORT")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("  ✅ \(tags.count) scenes saved")
        print("  🎼 \(musicPrompts.count) music prompts attached")
        
        let categoryCounts = Dictionary(grouping: tags, by: { $0.emotionCategoryID })
        print("\n  🎭 Categories used:")
        for (catID, ts) in categoryCounts {
            let catName = playlist.emotions.first(where: { $0.id == catID })?.categoryName ?? "Unknown"
            print("     \(catName): \(ts.count) scene(s)")
        }
        
        print("\n  📡 API calls: 3 (segmentation + classification + music prompts)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    // MARK: - Pass 1 Implementation
    
    private func runSegmentation(
        chapter: Chapter,
        lineAddresses: [LineAddress]
    ) async throws -> [ResolvedScene] {
        
        let chapterProse = lineAddresses
            .map { $0.text }
            .joined(separator: "\n\n")
        
        let totalLines = lineAddresses.count
        let minimumScenes = totalLines > 60 ? 3 : (totalLines > 30 ? 2 : 1)
        
        // ── Retry once if the model under-segments ──
        var bestResponse: AIProseScenesResponse?
        var bestUsableCount = 0
        
        for attempt in 1...2 {
            let raw = try await OllamaService.shared.segmentChapterIntoScenes(
                chapterTitle: chapter.title,
                chapterProse: chapterProse,
                approximateLineCount: totalLines
            )
            
            // Count how many scenes have valid, matchable opening phrases
            let usableCount = raw.scenes.filter { scene in
                let trimmed = scene.openingPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Reject placeholders
                if trimmed == "..." || trimmed == "…" || trimmed.isEmpty { return false }
                if trimmed.split(separator: " ").count < 4 { return false }
                if trimmed.filter({ $0.isLetter }).count < 10 { return false }
                
                // Reject system prompt echoes
                let lower = trimmed.lowercased()
                if lower.hasPrefix("you divide") { return false }
                if lower.hasPrefix("output json") { return false }
                if lower.hasPrefix("a scene is") { return false }
                
                // Must actually match a line in the chapter
                return findLineMatchingPhrase(trimmed, in: lineAddresses) != nil
            }.count
            
            if usableCount >= minimumScenes {
                bestResponse = raw
                break
            }
            
            // Keep the better attempt even if both fail the minimum
            if usableCount > bestUsableCount {
                bestUsableCount = usableCount
                bestResponse = raw
            }
            
            if attempt == 1 {
                print("   ⚠️ Pass 1 attempt 1: only \(usableCount) usable scene(s) (need \(minimumScenes)). Retrying...")
            }
        }
        
        guard let response = bestResponse else {
            print("   ❌ Both attempts failed. Falling back to single scene.")
            return [fallbackSingleScene(lineAddresses: lineAddresses)]
        }
        
        // ── Validate and filter scenes ──
        let validResponseScenes = response.scenes.filter { scene in
            let trimmed = scene.openingPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "..." || trimmed == "…" || trimmed.isEmpty { return false }
            if trimmed.split(separator: " ").count < 4 { return false }
            if trimmed.filter({ $0.isLetter }).count < 10 { return false }
            
            let lower = trimmed.lowercased()
            if lower.hasPrefix("you divide") { return false }
            if lower.hasPrefix("output json") { return false }
            if lower.hasPrefix("a scene is") { return false }
            
            return true
        }
        
        if validResponseScenes.count < response.scenes.count {
            print("   ⚠️ Rejected \(response.scenes.count - validResponseScenes.count) scenes with invalid opening phrases")
        }
        
        // ── STEP 1: Map each opening phrase to a line index ──
        var sceneStartLines: [(sceneIndex: Int, lineIndex: Int, summary: String)] = []
        
        for scene in validResponseScenes {
            if let matchedLine = findLineMatchingPhrase(scene.openingPhrase, in: lineAddresses) {
                sceneStartLines.append((
                    sceneIndex: scene.sceneIndex,
                    lineIndex: matchedLine,
                    summary: scene.sceneSummary
                ))
            } else {
                print("   ⚠️ Could not match phrase '\(scene.openingPhrase.prefix(40))...' to any line — skipping")
            }
        }
        
        guard !sceneStartLines.isEmpty else {
            print("   ❌ No phrases matched. Falling back to single scene.")
            return [fallbackSingleScene(lineAddresses: lineAddresses)]
        }
        
        // ── STEP 2: Sort, dedupe, enforce order ──
        var sorted = sceneStartLines.sorted { $0.lineIndex < $1.lineIndex }
        
        var deduped: [(sceneIndex: Int, lineIndex: Int, summary: String)] = []
        for scene in sorted {
            if deduped.last?.lineIndex != scene.lineIndex {
                deduped.append(scene)
            }
        }
        sorted = deduped
        
        // Force first scene to start at 0
        if sorted[0].lineIndex > 0 {
            sorted[0] = (sceneIndex: 0, lineIndex: 0, summary: sorted[0].summary)
        }
        
        // ── STEP 3: Derive endLine for each scene ──
        var resolved: [ResolvedScene] = []
        
        for (idx, scene) in sorted.enumerated() {
            let start = scene.lineIndex
            let end: Int
            
            if idx + 1 < sorted.count {
                end = sorted[idx + 1].lineIndex - 1
            } else {
                end = totalLines - 1
            }
            
            guard end >= start else {
                print("   ⚠️ Invalid scene range \(start)-\(end) — skipping")
                continue
            }
            
            let startAddr = lineAddresses[start]
            let endAddr = lineAddresses[end]
            let excerpt = buildExcerpt(from: lineAddresses, start: start, end: end)
            
            resolved.append(ResolvedScene(
                sceneIndex: idx,
                startPage: startAddr.pageNumber,
                startLine: startAddr.lineInPage,
                endPage: endAddr.pageNumber,
                endLine: endAddr.lineInPage,
                summary: scene.summary,
                excerpt: excerpt
            ))
        }
        
        // ── STEP 4: Merge tiny scenes into their predecessors ──
        let minSceneLength = 10
        var merged: [ResolvedScene] = []
        
        for scene in resolved {
            let sceneLength = (scene.endPage == scene.startPage)
                ? scene.endLine - scene.startLine + 1
                : 100
            
            if sceneLength < minSceneLength, let last = merged.last {
                merged[merged.count - 1] = ResolvedScene(
                    sceneIndex: last.sceneIndex,
                    startPage: last.startPage,
                    startLine: last.startLine,
                    endPage: scene.endPage,
                    endLine: scene.endLine,
                    summary: last.summary,
                    excerpt: last.excerpt
                )
            } else {
                merged.append(scene)
            }
        }
        
        // Re-index after merging
        let final = merged.enumerated().map { idx, scene in
            ResolvedScene(
                sceneIndex: idx,
                startPage: scene.startPage,
                startLine: scene.startLine,
                endPage: scene.endPage,
                endLine: scene.endLine,
                summary: scene.summary,
                excerpt: scene.excerpt
            )
        }
        
        return splitOversizedScenes(final, lineAddresses: lineAddresses)
    }
    
    /// Splits any scene longer than maxLines into roughly equal sub-scenes.
    /// Preserves the original scene's summary for the first sub-scene.
    private func splitOversizedScenes(
        _ scenes: [ResolvedScene],
        lineAddresses: [LineAddress],
        maxLines: Int = 25
    ) -> [ResolvedScene] {
        var result: [ResolvedScene] = []
        
        for scene in scenes {
            // Calculate scene length in global line indices
            guard let startGlobal = lineAddresses.firstIndex(where: {
                $0.pageNumber == scene.startPage && $0.lineInPage == scene.startLine
            }),
            let endGlobal = lineAddresses.firstIndex(where: {
                $0.pageNumber == scene.endPage && $0.lineInPage == scene.endLine
            }) else {
                result.append(scene)
                continue
            }
            
            let length = endGlobal - startGlobal + 1
            
            if length <= maxLines {
                result.append(scene)
                continue
            }
            
            // Split into chunks of ~maxLines
            let chunkCount = max(2, (length + maxLines - 1) / maxLines)
            let chunkSize = length / chunkCount
            
            for i in 0..<chunkCount {
                let chunkStart = startGlobal + (i * chunkSize)
                let chunkEnd: Int
                if i == chunkCount - 1 {
                    chunkEnd = endGlobal  // last chunk gets the remainder
                } else {
                    chunkEnd = chunkStart + chunkSize - 1
                }
                
                let startAddr = lineAddresses[chunkStart]
                let endAddr = lineAddresses[chunkEnd]
                let excerpt = buildExcerpt(from: lineAddresses, start: chunkStart, end: chunkEnd)
                
                // First sub-scene keeps the AI summary, others get a generic one
                let summary = (i == 0) ? scene.summary : "Continuation of scene"
                
                result.append(ResolvedScene(
                    sceneIndex: 0,  // will be reindexed later
                    startPage: startAddr.pageNumber,
                    startLine: startAddr.lineInPage,
                    endPage: endAddr.pageNumber,
                    endLine: endAddr.lineInPage,
                    summary: summary,
                    excerpt: excerpt
                ))
            }
        }
        
        // Reindex
        return result.enumerated().map { idx, scene in
            ResolvedScene(
                sceneIndex: idx,
                startPage: scene.startPage,
                startLine: scene.startLine,
                endPage: scene.endPage,
                endLine: scene.endLine,
                summary: scene.summary,
                excerpt: scene.excerpt
            )
        }
    }

    
    
    /// Finds the first line whose text contains the given phrase.
    /// Matching is done case-insensitively, ignoring quotes and extra whitespace.
    private func findLineMatchingPhrase(_ phrase: String, in lineAddresses: [LineAddress]) -> Int? {
        let normalizedPhrase = normalize(phrase)
        guard !normalizedPhrase.isEmpty else { return nil }
        
        // 1. Try exact substring match
        for (idx, addr) in lineAddresses.enumerated() {
            if normalize(addr.text).contains(normalizedPhrase) {
                return idx
            }
        }
        
        // 2. Try progressively shorter prefixes (first 8, 5, 3 words)
        let words = normalizedPhrase.split(separator: " ").map(String.init)
        for wordCount in [8, 5, 3] {
            guard words.count >= wordCount else { continue }
            let prefix = words.prefix(wordCount).joined(separator: " ")
            guard prefix.count >= 8 else { continue }
            
            for (idx, addr) in lineAddresses.enumerated() {
                if normalize(addr.text).contains(prefix) {
                    return idx
                }
            }
        }
        
        // 3. Fuzzy fallback: find the line that shares the most words with the phrase
        //    Only triggers if the phrase has enough substance to be meaningful
        guard words.count >= 4 else { return nil }
        
        let phraseWords = Set(words)
        var bestIdx: Int? = nil
        var bestOverlap = 0
        
        for (idx, addr) in lineAddresses.enumerated() {
            let lineWords = Set(normalize(addr.text).split(separator: " ").map(String.init))
            let overlap = phraseWords.intersection(lineWords).count
            
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestIdx = idx
            }
        }
        
        // Require at least 60% word overlap to accept a fuzzy match
        let threshold = max(3, Int(Double(phraseWords.count) * 0.6))
        if bestOverlap >= threshold {
            return bestIdx
        }
        
        return nil
    }

    /// Normalizes text for phrase matching — lowercases, collapses whitespace,
    /// strips quote marks and common punctuation that AIs sometimes alter.
    private func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        var cleaned = lowered
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "")    // unicode ellipsis …
        
        // Collapse whitespace
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        
        // Strip any trailing ellipsis / dots / truncation markers
        // This removes "....", "...", "..", "." and any trailing whitespace
        cleaned = cleaned.replacingOccurrences(
            of: #"[\s\.]+$"#,
            with: "",
            options: .regularExpression
        )
        
        // Strip trailing punctuation that AIs sometimes add (commas, quotes, etc.)
        cleaned = cleaned.replacingOccurrences(
            of: #"[,;:\"\']+$"#,
            with: "",
            options: .regularExpression
        )
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a context excerpt by sampling from throughout the scene,
    /// not just the opening. Gives Pass 2 a better feel for scene tone.
    private func buildExcerpt(from lineAddresses: [LineAddress], start: Int, end: Int) -> String {
        let length = end - start + 1
        
        // If scene is short, use all of it
        guard length > 6 else {
            return lineAddresses[start...end]
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        
        // Otherwise sample: first 3 lines + middle 2 + last 2
        let middle = start + length / 2
        let indices = [
            start, start + 1, start + 2,
            middle, middle + 1,
            end - 1, end
        ].filter { $0 >= start && $0 <= end }
        
        let uniqueIndices = Array(Set(indices)).sorted()
        return uniqueIndices
            .map { lineAddresses[$0].text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ... ")
    }

    private func fallbackSingleScene(lineAddresses: [LineAddress]) -> ResolvedScene {
        let first = lineAddresses.first!
        let last = lineAddresses.last!
        let excerpt = lineAddresses.prefix(8)
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return ResolvedScene(
            sceneIndex: 0,
            startPage: first.pageNumber,
            startLine: first.lineInPage,
            endPage: last.pageNumber,
            endLine: last.lineInPage,
            summary: "Full chapter",
            excerpt: excerpt
        )
    }
    
    // MARK: - Pass 2 Implementation
    private func runClassification(
        scenes: [ResolvedScene],
        allowedCategories: [String]
    ) async throws -> [AISceneClassification] {
        
        // Run all scene classifications in parallel
        let results = await withTaskGroup(of: AISceneClassification?.self) { group in
            for scene in scenes {
                group.addTask {
                    do {
                        return try await self.classifyOneScene(
                            scene: scene,
                            allowedCategories: allowedCategories
                        )
                    } catch {
                        print("   ⚠️ Scene \(scene.sceneIndex) classification failed: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            var collected: [AISceneClassification] = []
            for await result in group {
                if let r = result { collected.append(r) }
            }
            return collected
        }
        
        // Fill any scenes that failed with a safe default
        let validIndices = Set(scenes.map { $0.sceneIndex })
        let doneIndices = Set(results.map { $0.sceneIndex })
        let missing = validIndices.subtracting(doneIndices).sorted()
        
        var final = results
        for idx in missing {
            print("   ⚠️ Scene \(idx) missing — defaulting to \(allowedCategories.first ?? "Neutral") intensity 1")
            final.append(AISceneClassification(
                sceneIndex: idx,
                categoryName: allowedCategories.first ?? "Neutral",
                intensityLevel: 1
            ))
        }
        
        return final.sorted { $0.sceneIndex < $1.sceneIndex }
    }

    /// Classifies a single scene. The AI never sees multiple scenes at once,
    /// so it can't confuse indices or pollute one scene's emotion with another's.
    private func classifyOneScene(
        scene: ResolvedScene,
        allowedCategories: [String]
    ) async throws -> AISceneClassification {
        let sceneText = """
        Summary: \(scene.summary)
        Excerpt: \(scene.excerpt)
        """
        
        let response = try await OllamaService.shared.classifyOneSceneEmotion(
            sceneText: sceneText,
            sceneIndex: scene.sceneIndex,
            allowedCategories: allowedCategories
        )
        
        return response
    }
    
    // MARK: - Pass 3 Implementation
    private func runMusicPromptGeneration(
        scenes: [ResolvedScene],
        classifications: [AISceneClassification]
    ) async throws -> [Int: String] {
        
        var classByIndex: [Int: AISceneClassification] = [:]
        for c in classifications {
            classByIndex[c.sceneIndex] = c
        }
        
        let scenesText = scenes.compactMap { scene -> String? in
            guard let classification = classByIndex[scene.sceneIndex] else { return nil }
            return """
            SCENE \(scene.sceneIndex):
              Summary: \(scene.summary)
              Emotion: \(classification.categoryName)
              Intensity: \(classification.intensityLevel)
            """
        }.joined(separator: "\n\n")
        
        guard !scenesText.isEmpty else { return [:] }
        
        let response = try await OllamaService.shared.generateMusicPromptsForScenes(
            scenesText: scenesText
        )
        
        // ── Safety net: dedupe, drop invalid indices, fill missing ──
        let validIndices = Set(scenes.map { $0.sceneIndex })
        var promptByIndex: [Int: String] = [:]
        
        for prompt in response.prompts {
            guard validIndices.contains(prompt.sceneIndex) else { continue }
            if promptByIndex[prompt.sceneIndex] == nil {
                promptByIndex[prompt.sceneIndex] = prompt.musicPrompt
            }
        }
        
        // For any scene the AI skipped, generate a generic fallback prompt from its emotion
        let missing = validIndices.subtracting(promptByIndex.keys).sorted()
        if !missing.isEmpty {
            print("   ⚠️ Pass 3 missed scenes \(missing) — using generic fallback prompts")
            for idx in missing {
                guard let classification = classByIndex[idx] else { continue }
                promptByIndex[idx] = genericPrompt(
                    for: classification.categoryName,
                    intensity: classification.intensityLevel
                )
            }
        }
        
        return promptByIndex
    }

    /// Builds a serviceable music prompt from emotion + intensity when Pass 3 drops a scene.
    private func genericPrompt(for category: String, intensity: Int) -> String {
        let texture: String
        switch intensity {
        case 1: texture = "sparse, minimal, 60 BPM, subtle and understated"
        case 2: texture = "moderate density, 90 BPM, clearly present mood"
        default: texture = "dense layered, 110 BPM, full expression"
        }
        
        let base: String
        switch category.lowercased() {
        case let s where s.contains("battle") || s.contains("rage"):
            base = "driving percussion, low brass hits, aggressive strings"
        case let s where s.contains("sad") || s.contains("mourning") || s.contains("death"):
            base = "mournful cello, soft piano, distant reverb"
        case let s where s.contains("happy") || s.contains("joy") || s.contains("comedy"):
            base = "warm strings, light woodwinds, playful rhythm"
        case let s where s.contains("romance") || s.contains("love"):
            base = "gentle piano, warm strings, intimate melody"
        case let s where s.contains("mystery") || s.contains("scary") || s.contains("dark"):
            base = "haunting strings, dissonant piano, low drones"
        case let s where s.contains("epic") || s.contains("heroic"):
            base = "orchestral strings, powerful brass, triumphant theme"
        case let s where s.contains("calm") || s.contains("nature"):
            base = "ambient pads, soft acoustic guitar, gentle atmosphere"
        case let s where s.contains("tension") || s.contains("thriller"):
            base = "string tremolos, rising drones, suspenseful pulse"
        case let s where s.contains("magic") || s.contains("wonder"):
            base = "ethereal harp, shimmering synths, airy choir"
        default:
            base = "orchestral textures, balanced instrumentation"
        }
        
        return "\(base), \(texture)"
    }
    
    // MARK: - Tag Building
    
    private func buildSceneTags(
        scenes: [ResolvedScene],
        classifications: [AISceneClassification],
        musicPrompts: [Int: String],
        playlist: Playlist
    ) -> [SceneTag] {
        
        var classByIndex: [Int: AISceneClassification] = [:]
        for c in classifications {
            classByIndex[c.sceneIndex] = c
        }
        
        var tags: [SceneTag] = []
        
        for scene in scenes {
            guard let classification = classByIndex[scene.sceneIndex] else {
                print("   ⚠️ Scene \(scene.sceneIndex) has no classification — skipped")
                continue
            }
            
            guard let category = playlist.emotions.first(where: {
                $0.categoryName.lowercased() == classification.categoryName.lowercased()
            }) else {
                print("   ⚠️ Unknown category '\(classification.categoryName)' — scene \(scene.sceneIndex) skipped")
                continue
            }
            
            // ONE tag per scene with all three passes' data attached
            let tag = SceneTag(
                id: UUID(),
                startPage: scene.startPage,
                startLine: scene.startLine,
                endPage: scene.endPage,
                endLine: scene.endLine,
                emotionCategoryID: category.id,
                intensityLevel: max(1, min(3, classification.intensityLevel)),
                musicOverride: nil,
                musicPrompt: musicPrompts[scene.sceneIndex],   // may be nil if Pass 3 failed
                sceneSummary: scene.summary
            )
            tags.append(tag)
        }
        
        return tags.sorted { lhs, rhs in
            if lhs.startPage != rhs.startPage { return lhs.startPage < rhs.startPage }
            return lhs.startLine < rhs.startLine
        }
    }
    
    // MARK: - Line Address Building (with metadata filtering)
    
    private func buildLineAddresses(chapter: Chapter) -> [LineAddress] {
        var addresses: [LineAddress] = []
        var globalIdx = 0
        
        for page in chapter.pages {
            let storyLines = filterMetadata(from: page.lines)
            for (lineInPage, text) in storyLines.enumerated() {
                addresses.append(LineAddress(
                    globalIndex: globalIdx,
                    pageNumber: page.number,
                    lineInPage: lineInPage,
                    text: text
                ))
                globalIdx += 1
            }
        }
        
        return addresses
    }
    
    /// Strips Project Gutenberg headers, copyright blocks, ToC, and other metadata.
    private func filterMetadata(from lines: [String]) -> [String] {
        let skipExact = [
            "project gutenberg", "gutenberg.org",
            "all rights reserved", "table of contents",
            "*** start of", "*** end of",
            "oceanofpdf"
        ]
        
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return false }
            let lower = trimmed.lowercased()
            // Drop only obvious metadata markers
            return !skipExact.contains(where: { lower.contains($0) })
        }
    }
    

}
