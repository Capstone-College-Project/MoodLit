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

        let endIndex = min(startPageIndex + 10, pages.count)
        let pageBlock = Array(pages[startPageIndex..<endIndex])

        var allResolvedTags: [SceneTag] = []

        // First pass: 10-page block
        let blockResponse = try await OllamaService.shared.analyzePages(
            pages: pageBlock,
            playlist: playlist
        )

        let blockData = try JSONEncoder().encode(blockResponse)
        let blockParseResult = try SceneTagParser.parse(data: blockData, against: playlist)

        allResolvedTags.append(contentsOf: blockParseResult.resolved)

        if !blockParseResult.unresolved.isEmpty {
            print("⚠️ Unresolved tags in current block: \(blockParseResult.unresolved.count)")
        }

        // Fallback pass: fill pages with no tag
        var taggedPageNumbers = Set(allResolvedTags.map { $0.page })

        for page in pageBlock {
            if !taggedPageNumbers.contains(page.number) {
                print("⚠️ Missing tag for page \(page.number). Running single-page fallback.")

                let singleResponse = try await OllamaService.shared.analyzePage(
                    page: page,
                    playlist: playlist
                )

                let singleData = try JSONEncoder().encode(singleResponse)
                let singleParseResult = try SceneTagParser.parse(data: singleData, against: playlist)

                allResolvedTags.append(contentsOf: singleParseResult.resolved)

                if !singleParseResult.unresolved.isEmpty {
                    print("⚠️ Unresolved tags on fallback page \(page.number): \(singleParseResult.unresolved.count)")
                }

                // update after each fallback
                taggedPageNumbers = Set(allResolvedTags.map { $0.page })
            }
        }

        guard !allResolvedTags.isEmpty else {
            throw BookAIAnalyzerError.noResolvedTags
        }

        SceneTagEngine.applyAITags(allResolvedTags, to: book.id)

        let expectedPages = pageBlock.map { $0.number }
        let finalTaggedPages = Set(allResolvedTags.map { $0.page })
        let stillMissing = expectedPages.filter { !finalTaggedPages.contains($0) }

        print("✅ Expected pages: \(expectedPages)")
        print("✅ Tagged pages: \(Array(finalTaggedPages).sorted())")

        if stillMissing.isEmpty {
            print("✅ Every page in the block has at least one tag.")
        } else {
            print("⚠️ Still missing tags for pages: \(stillMissing)")
        }

        print("✅ Analyzed pages \(pageBlock.first?.number ?? 0) to \(pageBlock.last?.number ?? 0)")
    }
}
