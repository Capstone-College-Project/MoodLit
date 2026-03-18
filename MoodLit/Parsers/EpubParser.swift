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
        // 1. Gain access to the security-scoped URL from the file picker
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

        // 2. Copy to a temp location we fully own
        let tempDir = FileManager.default.temporaryDirectory
        let copyURL = tempDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: copyURL.path) {
            try FileManager.default.removeItem(at: copyURL)
        }
        try FileManager.default.copyItem(at: url, to: copyURL)

        // 3. Unzip into its own temp folder
        let unzipDir = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: copyURL, to: unzipDir)

        // 4. Find OPF file (the book manifest)
        let opfURL = try findOPF(in: unzipDir)
        let opfDir = opfURL.deletingLastPathComponent()

        // 5. Parse OPF for metadata and spine
        let opfResult = try OPFParser(url: opfURL).parse()

        // 6. Extract cover image
        var coverData: Data? = nil
        if let coverPath = opfResult.coverPath {
            coverData = try? Data(contentsOf: opfDir.appendingPathComponent(coverPath))
        }

        // 7. Parse each chapter HTML
        let uniqueSpineItems = Array(NSOrderedSet(array: opfResult.spineItems)) as! [String]
        let chapters = uniqueSpineItems.enumerated().compactMap { index, itemPath -> Chapter? in
            let chapterURL = opfDir.appendingPathComponent(itemPath)
            let html = (try? String(contentsOf: chapterURL, encoding: .utf8)) ?? ""
            let lines = extractLines(from: html)
            let pages = splitIntoPages(lines: lines, chapterIndex: index)
            guard !pages.isEmpty else { return nil }   // skip empty chapters
            return Chapter(title: opfResult.chapterTitles[index] ?? "Chapter \(index + 1)", pages: pages)
        }

        // 8. Cleanup temp files
        try? FileManager.default.removeItem(at: copyURL)
        try? FileManager.default.removeItem(at: unzipDir)

        return ParsedBook(
            title: opfResult.title,
            author: opfResult.author,
            coverImageData: coverData,
            chapters: chapters
        )
    }

    // MARK: - Find OPF

    private func findOPF(in directory: URL) throws -> URL {
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        guard let data = try? Data(contentsOf: containerURL),
              let xml = String(data: data, encoding: .utf8) else {
            throw EpubError.containerNotFound
        }

        // Pull the full-path attribute from the rootfile element
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

        // Remove script and style blocks entirely
        text = text.replacingOccurrences(
            of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)

        // Replace block-level closing tags with newlines so paragraphs separate properly
        let blockEnds = ["</p>", "</div>", "</h1>", "</h2>", "</h3>",
                         "</h4>", "</li>", "<br>", "<br/>", "<br />"]
        for tag in blockEnds {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // Strip all remaining HTML tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"), ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}")
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }

        // Split on newlines, trim whitespace, drop empty lines
        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Group lines into pages

    private func splitIntoPages(lines: [String],
                                 chapterIndex: Int,
                                 linesPerPage: Int = 20) -> [BookPage] {
        guard lines.count > 3 else { return [] }

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
