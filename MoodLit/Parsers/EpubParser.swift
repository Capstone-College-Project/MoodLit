// EpubParser.swift
// MoodLit
import Foundation
import ZIPFoundation

class EpubParser {

    // MARK: - Output

    struct ParsedBook {
        let title: String
        let author: String
        let coverImageData: Data?
        let chapters: [Chapter]
    }

    // MARK: - Parse Entry Point

    func parse(url: URL) throws -> ParsedBook {
        let needsSecurityScope = url.path.contains("/tmp/") == false
                && !url.path.contains(FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                )[0].path)

        if needsSecurityScope {
            guard url.startAccessingSecurityScopedResource() else {
                throw EpubError.accessDenied
            }
        }
        defer {
            if needsSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let copyURL = tempDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: copyURL.path) {
            try FileManager.default.removeItem(at: copyURL)
        }
        try FileManager.default.copyItem(at: url, to: copyURL)

        let unzipDir = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: copyURL, to: unzipDir)

        let opfURL = try findOPF(in: unzipDir)
        let opfDir = opfURL.deletingLastPathComponent()
        let opfResult = try OPFParser(url: opfURL).parse()

        var coverData: Data? = nil
        if let coverPath = opfResult.coverPath {
            coverData = try? Data(contentsOf: opfDir.appendingPathComponent(coverPath))
        }

        // 7. Parse each spine file — split by headings within each file
        let uniqueSpineItems = Array(NSOrderedSet(array: opfResult.spineItems)) as! [String]
        var allChapters: [Chapter] = []
        var globalChapterIndex = 0

        for (spineIndex, itemPath) in uniqueSpineItems.enumerated() {
            let chapterURL = opfDir.appendingPathComponent(itemPath)
            let html = (try? String(contentsOf: chapterURL, encoding: .utf8)) ?? ""

            // Split HTML into sections at heading boundaries
            let sections = splitByHeadings(html: html)

            for section in sections {
                let lines = extractLines(from: section.html)
                let pages = splitIntoPages(lines: lines, chapterIndex: globalChapterIndex)
                guard !pages.isEmpty else { continue }

                // Use heading text if found, then NCX title, then fallback
                let title = section.heading
                    ?? opfResult.chapterTitles[spineIndex]
                    ?? "Chapter \(globalChapterIndex + 1)"

                allChapters.append(Chapter(title: title, pages: pages))
                globalChapterIndex += 1
            }
        }

        try? FileManager.default.removeItem(at: copyURL)
        try? FileManager.default.removeItem(at: unzipDir)

        return ParsedBook(
            title: opfResult.title,
            author: opfResult.author,
            coverImageData: coverData,
            chapters: allChapters
        )
    }

    // MARK: - Split HTML by Heading Tags

    /// Splits a single XHTML file into sections wherever an <h1>, <h2>, or <h3> appears.
    /// Each section carries the heading text (if any) and the HTML content that follows it.
    private struct HTMLSection {
        let heading: String?
        let html: String
    }

    private func splitByHeadings(html: String) -> [HTMLSection] {
        // Match <h1>…</h1>, <h2>…</h2>, <h3>…</h3> with any attributes
        let pattern = #"<(h[1-3])\b[^>]*>([\s\S]*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return [HTMLSection(heading: nil, html: html)]
        }

        let fullRange = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: fullRange)

        // If no headings found, return the whole file as one section
        guard !matches.isEmpty else {
            return [HTMLSection(heading: nil, html: html)]
        }

        var sections: [HTMLSection] = []

        // Content before the first heading (e.g. front matter)
        let firstMatchStart = Range(matches[0].range, in: html)!.lowerBound
        let preamble = String(html[html.startIndex..<firstMatchStart])
        let preambleLines = extractLines(from: preamble)
        if preambleLines.count > 1 {
            sections.append(HTMLSection(heading: nil, html: preamble))
        }

        // Each heading starts a new section that runs until the next heading
        for (i, match) in matches.enumerated() {
            // Extract heading text (strip inner tags like <span>, <br> etc.)
            let headingRange = Range(match.range(at: 2), in: html)!
            let rawHeading = String(html[headingRange])
            let cleanHeading = rawHeading
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Section runs from this match's start to next match's start (or end of file)
            let sectionStart = Range(match.range, in: html)!.lowerBound
            let sectionEnd: String.Index
            if i + 1 < matches.count {
                sectionEnd = Range(matches[i + 1].range, in: html)!.lowerBound
            } else {
                sectionEnd = html.endIndex
            }

            let sectionHTML = String(html[sectionStart..<sectionEnd])

            // Skip sections that are just a heading with no real content
            let contentLines = extractLines(from: sectionHTML)
            if contentLines.count <= 1 && (i + 1 < matches.count) {
                // Merge with next section — skip this one, next will pick up content
                continue
            }

            let title = cleanHeading.isEmpty ? nil : cleanHeading
            sections.append(HTMLSection(heading: title, html: sectionHTML))
        }

        // If splitting produced nothing useful, fall back to whole file
        if sections.isEmpty {
            return [HTMLSection(heading: nil, html: html)]
        }

        return sections
    }

    // MARK: - Find OPF

    private func findOPF(in directory: URL) throws -> URL {
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        guard let data = try? Data(contentsOf: containerURL),
              let xml = String(data: data, encoding: .utf8) else {
            throw EpubError.containerNotFound
        }

        let pattern = #"full-path="([^"]+)""#
        if let range = xml.range(of: pattern, options: .regularExpression) {
            let raw = String(xml[range])
            let path = raw
                .replacingOccurrences(of: #"full-path=""#, with: "")
                .replacingOccurrences(of: "\"", with: "")
            return directory.appendingPathComponent(path)
        }
        throw EpubError.opfNotFound
    }

    // MARK: - Strip HTML → clean lines

    private func extractLines(from html: String) -> [String] {
        var text = html

        // Remove script and style blocks
        text = text.replacingOccurrences(
            of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)

        // 1. Mark block boundaries with a unique separator BEFORE touching whitespace
        let blockTags = ["</p>", "</div>", "</h1>", "</h2>", "</h3>",
                         "</h4>", "</h5>", "</h6>", "</li>", "</blockquote>"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "⏎BREAK⏎", options: .caseInsensitive)
        }
        // Line breaks also act as separators
        for br in ["<br>", "<br/>", "<br />"] {
            text = text.replacingOccurrences(of: br, with: "⏎BREAK⏎", options: .caseInsensitive)
        }

        // 2. Strip all remaining HTML tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // 3. Decode HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"), ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}")
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }

        // 4. Split by our marker first — each chunk is one paragraph
        let rawParagraphs = text.components(separatedBy: "⏎BREAK⏎")

        // 5. Within each paragraph, collapse all whitespace (hard wraps) into single spaces
        return rawParagraphs
            .map { paragraph in
                paragraph
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - Group lines into pages

    private func splitIntoPages(lines: [String],
                                 chapterIndex: Int,
                                 linesPerPage: Int = 20) -> [BookPage] {
        guard lines.count > 1 else { return [] }

        var pages: [BookPage] = []
        let chunks = stride(from: 0, to: lines.count, by: linesPerPage)

        for (pageIndex, start) in chunks.enumerated() {
            let end = min(start + linesPerPage, lines.count)
            let pageNumber = (chapterIndex + 1) * 100_000 + (pageIndex + 1)
            pages.append(BookPage(
                number: pageNumber,
                lines: Array(lines[start..<end])
            ))
        }
        return pages
    }

    // MARK: - Errors

    enum EpubError: LocalizedError {
        case accessDenied
        case containerNotFound
        case opfNotFound
        case parseFailure(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:        return "Could not access the selected file."
            case .containerNotFound:   return "Invalid ePub: META-INF/container.xml not found."
            case .opfNotFound:         return "Invalid ePub: could not locate the OPF manifest."
            case .parseFailure(let m): return "Parse error: \(m)"
            }
        }
    }
}
