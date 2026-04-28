//
//  Playlist.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.
//

import Foundation
import SwiftUI

// MARK: - Playlist

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var emotions: [EmotionCategory]

    init(id: UUID = UUID(), name: String, emotions: [EmotionCategory] = EmotionCategory.defaults) {
        self.id = id
        self.name = name
        self.emotions = emotions
    }

    var totalTracks: Int {
        emotions.flatMap { [$0.intensity1, $0.intensity2, $0.intensity3] }
            .compactMap { $0.music }
            .count
    }
    
    func track(forCategoryID id: UUID, intensityLevel: Int) -> MusicFile? {
        guard let category = emotions.first(where: { $0.id == id }) else { return nil }
        switch intensityLevel {
        case 1: return category.intensity1.music
        case 2: return category.intensity2.music
        default: return category.intensity3.music
        }
    }
}

// MARK: - EmotionCategory

struct EmotionCategory: Identifiable, Codable {
    let id: UUID
    var categoryName: String
    var colorHex: String
    var intensity1: Intensity
    var intensity2: Intensity
    var intensity3: Intensity
    
    init(
        id: UUID = UUID(),
        categoryName: String,
        colorHex: String,
        intensity1: Intensity = Intensity(nameDescription: "Low"),
        intensity2: Intensity = Intensity(nameDescription: "Medium"),
        intensity3: Intensity = Intensity(nameDescription: "High")
    ) {
        self.id = id
        self.categoryName = categoryName
        self.colorHex = colorHex
        self.intensity1 = intensity1
        self.intensity2 = intensity2
        self.intensity3 = intensity3
    }
    
    var color: Color { Color(hex: colorHex) }
    
    var hasAnyTrack: Bool {
        intensity1.music != nil || intensity2.music != nil || intensity3.music != nil
    }
    
    // MARK: - Default categories pre-loaded for new playlists
    static var defaults: [EmotionCategory] {[
        EmotionCategory(
            categoryName: "Neutral",
            colorHex: "#AAAAAA",
            intensity1: Intensity(nameDescription: "Background ambience, minimal emotion"),
            intensity2: Intensity(nameDescription: "Soft presence, lightly engaging"),
            intensity3: Intensity(nameDescription: "Steady tone, adaptable to any scene")
        ),
        EmotionCategory(
            categoryName: "Joy",
            colorHex: "#F5C842",
            intensity1: Intensity(nameDescription: "Quiet contentment, inner peace"),
            intensity2: Intensity(nameDescription: "Cheerful, light-hearted happiness"),
            intensity3: Intensity(nameDescription: "Radiant joy, celebration")
        ),
        EmotionCategory(
            categoryName: "Happiness",
            colorHex: "#FFD966",
            intensity1: Intensity(nameDescription: "Pleasant mood, mild positivity"),
            intensity2: Intensity(nameDescription: "Bright and upbeat"),
            intensity3: Intensity(nameDescription: "Overflowing happiness, excitement")
        ),
        EmotionCategory(
            categoryName: "Warmth",
            colorHex: "#F4A261",
            intensity1: Intensity(nameDescription: "Comfort, familiarity"),
            intensity2: Intensity(nameDescription: "Connection, bonding"),
            intensity3: Intensity(nameDescription: "Deep warmth, emotional closeness")
        ),
        EmotionCategory(
            categoryName: "Romance",
            colorHex: "#E8748A",
            intensity1: Intensity(nameDescription: "Gentle attraction, subtle affection"),
            intensity2: Intensity(nameDescription: "Tender connection, emotional intimacy"),
            intensity3: Intensity(nameDescription: "Passionate love, overwhelming emotion")
        ),
        EmotionCategory(
            categoryName: "Sadness",
            colorHex: "#5A8FBF",
            intensity1: Intensity(nameDescription: "Melancholy, quiet sadness"),
            intensity2: Intensity(nameDescription: "Emotional pain, longing"),
            intensity3: Intensity(nameDescription: "Deep sorrow, grief")
        ),
        EmotionCategory(
            categoryName: "Loneliness",
            colorHex: "#6C7A89",
            intensity1: Intensity(nameDescription: "Solitude, quiet isolation"),
            intensity2: Intensity(nameDescription: "Emotional distance, emptiness"),
            intensity3: Intensity(nameDescription: "Profound loneliness, despair")
        ),
        EmotionCategory(
            categoryName: "Tension",
            colorHex: "#D4501A",
            intensity1: Intensity(nameDescription: "Unease, subtle discomfort"),
            intensity2: Intensity(nameDescription: "Suspense building, anticipation"),
            intensity3: Intensity(nameDescription: "High tension, edge of breaking")
        ),
        EmotionCategory(
            categoryName: "Fear",
            colorHex: "#6A4FA0",
            intensity1: Intensity(nameDescription: "Eerie feeling, something off"),
            intensity2: Intensity(nameDescription: "Dread, growing fear"),
            intensity3: Intensity(nameDescription: "Terror, panic")
        ),
        EmotionCategory(
            categoryName: "Battle",
            colorHex: "#E03A2A",
            intensity1: Intensity(nameDescription: "Conflict rising, readiness"),
            intensity2: Intensity(nameDescription: "Active struggle, aggression"),
            intensity3: Intensity(nameDescription: "Full combat, chaos")
        ),
        EmotionCategory(
            categoryName: "Heroic",
            colorHex: "#C87A20",
            intensity1: Intensity(nameDescription: "Determination, rising courage"),
            intensity2: Intensity(nameDescription: "Purposeful action, bravery"),
            intensity3: Intensity(nameDescription: "Triumph, legendary victory")
        ),
        EmotionCategory(
            categoryName: "Darkness",
            colorHex: "#4A3060",
            intensity1: Intensity(nameDescription: "Subtle menace, unease"),
            intensity2: Intensity(nameDescription: "Corruption, oppressive presence"),
            intensity3: Intensity(nameDescription: "Overwhelming darkness, evil")
        ),
        EmotionCategory(
            categoryName: "Death",
            colorHex: "#707070",
            intensity1: Intensity(nameDescription: "Quiet passing, stillness"),
            intensity2: Intensity(nameDescription: "Loss, emotional weight"),
            intensity3: Intensity(nameDescription: "Tragic finality, devastation")
        ),
        EmotionCategory(
            categoryName: "Magic",
            colorHex: "#A0C8F0",
            intensity1: Intensity(nameDescription: "Subtle magic, faint presence"),
            intensity2: Intensity(nameDescription: "Active spellwork, mystical energy"),
            intensity3: Intensity(nameDescription: "Overwhelming power, arcane force")
        ),
        EmotionCategory(
            categoryName: "Wonder",
            colorHex: "#BDE0FE",
            intensity1: Intensity(nameDescription: "Curiosity, gentle awe"),
            intensity2: Intensity(nameDescription: "Amazement, discovery"),
            intensity3: Intensity(nameDescription: "Breathtaking awe, grand spectacle")
        ),
        EmotionCategory(
            categoryName: "Comedy",
            colorHex: "#F5A623",
            intensity1: Intensity(nameDescription: "Light humor, playful"),
            intensity2: Intensity(nameDescription: "Comedic situation, exaggerated"),
            intensity3: Intensity(nameDescription: "Chaotic humor, absurdity")
        ),
        EmotionCategory(
            categoryName: "Calm",
            colorHex: "#5A9A6A",
            intensity1: Intensity(nameDescription: "Stillness, quiet atmosphere"),
            intensity2: Intensity(nameDescription: "Peaceful flow, relaxation"),
            intensity3: Intensity(nameDescription: "Deep serenity, meditative state")
        ),
        EmotionCategory(
            categoryName: "Reflection",
            colorHex: "#8D99AE",
            intensity1: Intensity(nameDescription: "Thoughtful pause"),
            intensity2: Intensity(nameDescription: "Emotional introspection"),
            intensity3: Intensity(nameDescription: "Deep self-realization")
        )
    ]}
}

// MARK: - Intensity

struct Intensity: Identifiable, Codable {
    let id: UUID
    var nameDescription: String
    var musicFileName: String?
    var music: MusicFile?
    
    init(
        id: UUID = UUID(),
        nameDescription: String,
        musicFileName: String? = nil,
        music: MusicFile? = nil
    ) {
        self.id = id
        self.nameDescription = nameDescription
        self.musicFileName = musicFileName
        self.music = music
    }
    
    var hasTrack: Bool { music != nil }
}

// MARK: - MusicFile

struct MusicFile: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var fileName: String
    
    init(id: UUID = UUID(), title: String, fileName: String) {
        self.id = id
        self.title = title
        self.fileName = fileName
    }
    
    var fileURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Music").appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
