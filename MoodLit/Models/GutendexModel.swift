//
//  GutendexResponse.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/1/26.
//


import Foundation

struct GutendexResponse: Codable {
    let results: [GutenbergBook]
}

struct GutenbergBook: Codable, Identifiable {
    let id: Int
    let title: String
    let authors: [GutenbergAuthor]
    let formats: [String: String]

    var authorNames: String {
        authors.map { $0.name }.joined(separator: ", ")
    }
    var coverURL: String? { formats["image/jpeg"] }
    var epubURL: String? { formats["application/epub+zip"] }
}

struct GutenbergAuthor: Codable {
    let name: String
}