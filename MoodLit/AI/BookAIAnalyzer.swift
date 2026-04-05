//
//  BookAIAnalyzer.swift
//  MoodLit
//
//  Created by Mayra Trochez on 3/31/26.
//
import Foundation

enum BookAIAnalyzerError: LocalizedError {
    case noPages
    case invalidStartPage
    case noResolvedTags

    var errorDescription: String? {
        switch self {
        case .noPages:
            return "This book has no pages to analyze."
        case .invalidStartPage:
            return "The current page is invalid."
        case .noResolvedTags:
            return "The AI finished, but no valid tags could be resolved."
        }
    }
}

final class BookAIAnalyzer {

    func analyze(book: Book, playlist: Playlist, startPageIndex: Int) async throws {
        let pages = book.allPages
        guard !pages.isEmpty else {
            throw BookAIAnalyzerError.noPages
        }

        guard startPageIndex >= 0 && startPageIndex < pages.count else {
            throw BookAIAnalyzerError.invalidStartPage
        }

        let endIndex = min(startPageIndex + 3, pages.count)
        let pageBlock = Array(pages[startPageIndex..<endIndex])

        // Filter out title/note pages
        let storyPages = pageBlock.filter { page in
            guard page.lines.count >= 3 else { return false }
            
            let skipPatterns = [
                "table of contents", "copyright", "all rights reserved",
                "published by", "isbn", "dedication", "acknowledgments",
                "about the author", "also by", "project gutenberg",
                "license", "terms of use", "oceanofpdf", "contents",
                "simon & schuster", "pocket books", "division of"
            ]
            
            var metadataLines = 0
            for line in page.lines {
                let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
                
                if skipPatterns.contains(where: { lower.contains($0) }) {
                    metadataLines += 1
                    continue
                }
                if lower.hasPrefix("chapter ") || lower.hasPrefix("part ") ||
                   lower.hasPrefix("prologue") || lower.hasPrefix("epilogue") ||
                   lower.hasPrefix("appendix") || lower.hasPrefix("section ") {
                    metadataLines += 1
                    continue
                }
            }
            
            let metadataRatio = Double(metadataLines) / Double(page.lines.count)
            if metadataRatio > 0.5 { return false }
            return true
        }

        let skippedCount = pageBlock.count - storyPages.count
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🤖 AI ANALYSIS STARTED")
        print("📖 Book: \(book.title)")
        print("🎵 Playlist: \(playlist.name) (\(playlist.emotions.count) categories)")
        print("📄 Pages: \(pageBlock.count) (index \(startPageIndex) → \(endIndex - 1))")
        if skippedCount > 0 {
            print("📄 Skipped \(skippedCount) non-story pages")
        }
        print("📄 Story pages: \(storyPages.map { $0.number })")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        var allResolvedTags: [SceneTag] = []
        var totalAPICalls = 0
        
        for page in pageBlock {
            print("📄 Page \(page.number) — \(page.lines.count) lines:")
            for (i, line) in page.lines.enumerated() {
                print("   \(i): \(line.prefix(80))")
            }
        }

        // ── PASS 1: Block analysis ──
        print("\n🔹 PASS 1: Analyzing \(storyPages.count)-page block...")
        totalAPICalls += 1

        // Build context: saved + previous pages + existing tags
        let savedContext = book.aiContext
        let allPages = book.allPages
        let firstPageIndex = allPages.firstIndex(where: { $0.number == storyPages.first?.number }) ?? 0
        let pageContext = buildContext(from: allPages, upTo: firstPageIndex)
        let tagContext = buildTagContext(from: book.sceneTags, playlist: playlist)
        let fullContext = [savedContext, pageContext, tagContext]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let blockResponse = try await OllamaService.shared.analyzePages(
            pages: storyPages,
            playlist: playlist,
            context: fullContext
        )

        let blockData = try JSONEncoder().encode(blockResponse)
        let blockParseResult = try SceneTagParser.parse(data: blockData, against: playlist)

        allResolvedTags.append(contentsOf: blockParseResult.resolved)

        let blockResolved = blockParseResult.resolved.count
        let blockUnresolved = blockParseResult.unresolved.count
        let blockTotal = blockResolved + blockUnresolved

        if blockResolved > 0 {
            print("   ✅ Block returned \(blockTotal) tags → \(blockResolved) resolved, \(blockUnresolved) unresolved")
            let blockTagsByPage = Dictionary(grouping: blockParseResult.resolved, by: { $0.page })
            for page in storyPages {
                let count = blockTagsByPage[page.number]?.count ?? 0
                let status = count > 0 ? "✅ \(count) tags" : "❌ missing"
                print("   Page \(page.number): \(status)")
            }
        } else {
            print("   ⚠️ Block returned 0 valid tags — all pages need fallback")
        }

        if !blockParseResult.unresolved.isEmpty {
            for issue in blockParseResult.unresolved {
                print("   ⚠️ Unresolved: \(issue)")
            }
        }

        // ── PASS 2: Single-page fallback ──
        var taggedPageNumbers = Set(allResolvedTags.map { $0.page })
        let missingPages = storyPages.filter { !taggedPageNumbers.contains($0.number) }

        if !missingPages.isEmpty {
            print("\n🔹 PASS 2: Fallback for \(missingPages.count) missing pages...")

            for page in missingPages {
                print("   📄 Page \(page.number) (\(page.lines.count) lines) → calling AI...")
                totalAPICalls += 1

                // Build context from tags we've already resolved
                let rollingContext = buildTagContext(from: allResolvedTags, playlist: playlist)

                let singleResponse = try await OllamaService.shared.analyzePage(
                    page: page,
                    playlist: playlist,
                    context: rollingContext
                )

                let singleData = try JSONEncoder().encode(singleResponse)
                let singleParseResult = try SceneTagParser.parse(data: singleData, against: playlist)

                let resolved = singleParseResult.resolved
                allResolvedTags.append(contentsOf: resolved)

                if resolved.isEmpty {
                    print("   ❌ Page \(page.number): AI returned no valid tags")
                } else {
                    let coveredLines = Set(resolved.flatMap { $0.startLine...$0.endLine })
                    let totalLines = page.lines.count
                    let coverage = totalLines > 0 ? Int(Double(coveredLines.count) / Double(totalLines) * 100) : 0
                    print("   ✅ Page \(page.number): \(resolved.count) tags, \(coverage)% line coverage (\(coveredLines.count)/\(totalLines) lines)")
                }

                if !singleParseResult.unresolved.isEmpty {
                    for issue in singleParseResult.unresolved {
                        print("   ⚠️ Unresolved: \(issue)")
                    }
                }

                taggedPageNumbers = Set(allResolvedTags.map { $0.page })
            }
        } else {
            print("\n🔹 PASS 2: Skipped — all pages covered by block analysis")
        }

        // ── FINAL REPORT ──
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 ANALYSIS REPORT")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        guard !allResolvedTags.isEmpty else {
            print("❌ FAILED: No valid tags produced")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            throw BookAIAnalyzerError.noResolvedTags
        }

        // Fill any gaps the AI left
        let filledTags = fillGaps(tags: allResolvedTags, pages: storyPages, playlist: playlist)
        let gapsFilled = filledTags.count - allResolvedTags.count
        if gapsFilled > 0 {
            print("\n🔹 PASS 3: Filled \(gapsFilled) gap(s) with nearest category")
        }

        SceneTagEngine.applyAITags(filledTags, to: book.id)

        // Save AI-generated context for next analysis session
        let aiGeneratedContext = blockResponse.contextSummary ?? ""
        let newContext = buildRollingContext(
            previousContext: book.aiContext,
            aiSummary: aiGeneratedContext,
            pages: storyPages
        )
        await MainActor.run {
            LibraryManager.shared.updateAIContext(for: book.id, context: newContext)
        }

        let expectedPages = storyPages.map { $0.number }
        let finalTaggedPages = Set(filledTags.map { $0.page })
        let stillMissing = expectedPages.filter { !finalTaggedPages.contains($0) }

        let tagsByPage = Dictionary(grouping: filledTags, by: { $0.page })
        for page in storyPages {
            let tags = tagsByPage[page.number] ?? []
            let coveredLines = Set(tags.flatMap { $0.startLine...$0.endLine })
            let totalLines = page.lines.count
            let coverage = totalLines > 0 ? Int(Double(coveredLines.count) / Double(totalLines) * 100) : 0
            let status = tags.isEmpty ? "❌ NO TAGS" : "\(tags.count) tags, \(coverage)% coverage"
            print("  📄 Page \(page.number): \(status)")
        }

        let categoryCounts = Dictionary(grouping: filledTags, by: { $0.emotionCategoryID })
        print("\n  🎭 Categories used:")
        for (catID, tags) in categoryCounts {
            let catName = playlist.emotions.first(where: { $0.id == catID })?.categoryName ?? "Unknown"
            print("     \(catName): \(tags.count) tags")
        }

        print("\n  📈 Total: \(filledTags.count) tags across \(finalTaggedPages.count) pages")
        print("  📡 API calls: \(totalAPICalls)")

        if stillMissing.isEmpty {
            print("  ✅ All pages tagged successfully")
        } else {
            print("  ⚠️ Missing pages: \(stillMissing)")
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    // MARK: - Fill Gaps
    
    private func fillGaps(tags: [SceneTag], pages: [BookPage], playlist: Playlist) -> [SceneTag] {
        var result = tags

        for page in pages {
            let pageTags = result
                .filter { $0.page == page.number }
                .sorted { $0.startLine < $1.startLine }

            let totalLines = page.lines.count
            guard totalLines > 0 else { continue }

            let fillerCategoryID = pageTags.first?.emotionCategoryID
                ?? playlist.emotions.first?.id
            guard let categoryID = fillerCategoryID else { continue }

            var coveredLines = Set<Int>()
            for tag in pageTags {
                for line in tag.startLine...tag.endLine {
                    coveredLines.insert(line)
                }
            }

            var gapStart: Int? = nil
            for line in 0..<totalLines {
                if !coveredLines.contains(line) {
                    if gapStart == nil { gapStart = line }
                } else {
                    if let start = gapStart {
                        let nearestCategory = findNearestCategory(
                            line: start,
                            pageTags: pageTags,
                            fallback: categoryID
                        )
                        result.append(SceneTag(
                            id: UUID(),
                            page: page.number,
                            startLine: start,
                            endLine: line - 1,
                            emotionCategoryID: nearestCategory,
                            intensityLevel: 1,
                            musicOverride: nil
                        ))
                        gapStart = nil
                    }
                }
            }
            if let start = gapStart {
                let nearestCategory = findNearestCategory(
                    line: start,
                    pageTags: pageTags,
                    fallback: categoryID
                )
                result.append(SceneTag(
                    id: UUID(),
                    page: page.number,
                    startLine: start,
                    endLine: totalLines - 1,
                    emotionCategoryID: nearestCategory,
                    intensityLevel: 1,
                    musicOverride: nil
                ))
            }
        }

        return result
    }

    // MARK: - Find Nearest Category
    
    private func findNearestCategory(line: Int, pageTags: [SceneTag], fallback: UUID) -> UUID {
        var bestDist = Int.max
        var bestID = fallback
        for tag in pageTags {
            let dist = min(abs(tag.startLine - line), abs(tag.endLine - line))
            if dist < bestDist {
                bestDist = dist
                bestID = tag.emotionCategoryID
            }
        }
        return bestID
    }
    
    // MARK: - Build Context from Previous Pages
    
    private func buildContext(from pages: [BookPage], upTo index: Int) -> String {
        let startIdx = max(0, index - 3)
        let contextPages = Array(pages[startIdx..<index])
        
        guard !contextPages.isEmpty else { return "" }
        
        var contextLines: [String] = []
        for page in contextPages {
            let storyLines = page.lines.filter { line in
                let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
                let skip = lower.hasPrefix("chapter ") || lower.hasPrefix("part ") ||
                           lower.contains("oceanofpdf") || lower.contains("isbn") ||
                           lower.contains("copyright")
                return !skip && line.count > 10
            }
            
            if !storyLines.isEmpty {
                let preview = storyLines.prefix(3).joined(separator: " ")
                contextLines.append("Page \(page.number): \(preview)")
            }
        }
        
        return contextLines.isEmpty ? "" : contextLines.joined(separator: "\n")
    }
    
    // MARK: - Build Context from Existing Tags
    
    private func buildTagContext(from tags: [SceneTag], playlist: Playlist) -> String {
        guard !tags.isEmpty else { return "" }
        
        let recent = tags.suffix(5)
        let descriptions = recent.compactMap { tag -> String? in
            let catName = playlist.emotions.first(where: { $0.id == tag.emotionCategoryID })?.categoryName ?? "Unknown"
            return "Page \(tag.page) lines \(tag.startLine)-\(tag.endLine): \(catName) (intensity \(tag.intensityLevel))"
        }
        
        return "Recent emotional tags:\n" + descriptions.joined(separator: "\n")
    }
    

    // MARK: - Build Rolling Context from AI Summaries

    private func buildRollingContext(
        previousContext: String,
        aiSummary: String,
        pages: [BookPage]
    ) -> String {
        guard !aiSummary.isEmpty else { return previousContext }
        
        let pageRange = pages.map { $0.number }
        let label = "Pages \(pageRange.first ?? 0)-\(pageRange.last ?? 0)"
        let newEntry = "\(label): \(aiSummary)"
        
        // Append to existing context
        let combined: String
        if previousContext.isEmpty {
            combined = newEntry
        } else {
            combined = previousContext + "\n\n" + newEntry
        }
        
        // Keep only the last ~1500 chars to avoid token bloat
        if combined.count > 1500 {
            // Find the start of the second entry to avoid cutting mid-sentence
            let trimmed = String(combined.suffix(1500))
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                return String(trimmed[trimmed.index(after: firstNewline)...])
            }
            return trimmed
        }
        return combined
    }
}
