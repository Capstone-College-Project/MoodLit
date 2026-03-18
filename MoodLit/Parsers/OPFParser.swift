// OPFParser.swift
// MoodLit
//
// Parses the OPF (Open Packaging Format) XML file inside an ePub.
// Extracts: title, author, spine order (chapter file paths), and cover image path.

import Foundation

class OPFParser: NSObject, XMLParserDelegate {

    // MARK: - Output

    struct OPFResult {
        let title: String
        let author: String
        let spineItems: [String]            // ordered file paths for chapters
        let chapterTitles: [Int: String]    // index → title from NCX/nav
        let coverPath: String?
    }

    // MARK: - Private State

    private let url: URL
    private var title = "Unknown Title"
    private var author = "Unknown Author"
    private var spineOrder: [String] = []
    private var manifest: [String: String] = [:]    // id → href
    private var coverPath: String? = nil
    private var currentElement = ""
    private var navPath: String? = nil

    init(url: URL) {
        self.url = url
    }

    // MARK: - Parse

    func parse() throws -> OPFResult {
        guard let data = try? Data(contentsOf: url) else {
            throw EpubParser.EpubError.parseFailure("Cannot read OPF file")
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        let spineFiles = spineOrder.compactMap { manifest[$0] }

        // Optionally parse NCX or nav for chapter titles
        var chapterTitles: [Int: String] = [:]
        if let nav = navPath {
            let navURL = url.deletingLastPathComponent().appendingPathComponent(nav)
            chapterTitles = (try? parseNav(at: navURL)) ?? [:]
        }

        return OPFResult(
            title: title,
            author: author,
            spineItems: spineFiles,
            chapterTitles: chapterTitles,
            coverPath: coverPath
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement element: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String]) {
        currentElement = element

        switch element {

        case "item":
            let id   = attributes["id"]   ?? ""
            let href = attributes["href"] ?? ""
            let mediaType = attributes["media-type"] ?? ""
            manifest[id] = href

            // Detect cover image
            if attributes["properties"] == "cover-image" ||
               id.lowercased().contains("cover") &&
               mediaType.hasPrefix("image/") {
                coverPath = href
            }

            // Detect navigation document
            if attributes["properties"] == "nav" ||
               id.lowercased().contains("toc") {
                navPath = href
            }

        case "itemref":
            if let idref = attributes["idref"] {
                spineOrder.append(idref)
            }

        case "meta":
            // Handle OPF2 cover meta tag
            if attributes["name"] == "cover",
               let content = attributes["content"] {
                coverPath = manifest[content]
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }

        switch currentElement {
        case "dc:title":   if title == "Unknown Title" { title = s }
        case "dc:creator": if author == "Unknown Author" { author = s }
        default: break
        }
    }

    // MARK: - Parse NAV / NCX for chapter titles

    private func parseNav(at url: URL) throws -> [Int: String] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return [:] }

        var titles: [Int: String] = [:]

        // Very simple extraction of ordered list items from nav or NCX
        // Works for both EPUB2 NCX (navLabel/text) and EPUB3 nav (li > a)
        let patterns = [
            #"<navLabel>\s*<text>([^<]+)</text>"#,   // NCX
            #"<a[^>]*>([^<]+)</a>"#                  // NAV
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: content,
                                            range: NSRange(content.startIndex..., in: content))
                for (index, match) in matches.enumerated() {
                    if let range = Range(match.range(at: 1), in: content) {
                        titles[index] = String(content[range])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if !titles.isEmpty { break }
            }
        }

        return titles
    }
}
