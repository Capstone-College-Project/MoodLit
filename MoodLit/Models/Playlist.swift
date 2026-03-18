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
    var categoryName: String       // e.g. "Happy / Joy" — user can rename
    var colorHex: String           // user defined
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
            categoryName: "Happy / Joy",
            colorHex: "#F5C842",
            intensity1: Intensity(nameDescription: "Soft warmth, quiet contentment"),
            intensity2: Intensity(nameDescription: "Cheerful, light-hearted"),
            intensity3: Intensity(nameDescription: "Full celebration, jubilation")
        ),
        EmotionCategory(
            categoryName: "Battle / Rage",
            colorHex: "#E03A2A",
            intensity1: Intensity(nameDescription: "Tension rising, pre-fight"),
            intensity2: Intensity(nameDescription: "Skirmish, controlled aggression"),
            intensity3: Intensity(nameDescription: "Full combat, peak fury")
        ),
        EmotionCategory(
            categoryName: "Mystery / Scary",
            colorHex: "#6A4FA0",
            intensity1: Intensity(nameDescription: "Eerie calm, something feels off"),
            intensity2: Intensity(nameDescription: "Dread building, suspense"),
            intensity3: Intensity(nameDescription: "Horror, terror, full fear")
        ),
        EmotionCategory(
            categoryName: "Sad / Mourning",
            colorHex: "#5A8FBF",
            intensity1: Intensity(nameDescription: "Quiet grief, melancholy"),
            intensity2: Intensity(nameDescription: "Emotional loss, longing"),
            intensity3: Intensity(nameDescription: "Deep sorrow, tragedy")
        ),
        EmotionCategory(
            categoryName: "Romance / Love",
            colorHex: "#E8748A",
            intensity1: Intensity(nameDescription: "Gentle attraction, shy glances"),
            intensity2: Intensity(nameDescription: "Tender moments, warmth"),
            intensity3: Intensity(nameDescription: "Passionate, overwhelming love")
        ),
        EmotionCategory(
            categoryName: "Epic / Heroic",
            colorHex: "#C87A20",
            intensity1: Intensity(nameDescription: "Rising hope, determination"),
            intensity2: Intensity(nameDescription: "Hero's march, purpose"),
            intensity3: Intensity(nameDescription: "Full orchestral triumph, legend")
        ),
        EmotionCategory(
            categoryName: "Comedy / Quirky",
            colorHex: "#F5A623",
            intensity1: Intensity(nameDescription: "Light silliness, playful"),
            intensity2: Intensity(nameDescription: "Comedic situation, absurd"),
            intensity3: Intensity(nameDescription: "Full chaos, slapstick frenzy")
        ),
        EmotionCategory(
            categoryName: "Calm / Nature",
            colorHex: "#5A9A6A",
            intensity1: Intensity(nameDescription: "Still, meditative, empty landscape"),
            intensity2: Intensity(nameDescription: "Serene journey, exploration"),
            intensity3: Intensity(nameDescription: "Breathtaking awe, vast beauty")
        ),
        EmotionCategory(
            categoryName: "Tension / Thriller",
            colorHex: "#D4501A",
            intensity1: Intensity(nameDescription: "Unease, something is wrong"),
            intensity2: Intensity(nameDescription: "Chase, countdown, stakes rising"),
            intensity3: Intensity(nameDescription: "Maximum suspense, life or death")
        ),
        EmotionCategory(
            categoryName: "Dark / Villain",
            colorHex: "#4A3060",
            intensity1: Intensity(nameDescription: "Sinister undertone, lurking threat"),
            intensity2: Intensity(nameDescription: "Menacing presence, corruption"),
            intensity3: Intensity(nameDescription: "Full villainy, overwhelming darkness")
        ),
        EmotionCategory(
            categoryName: "Death / Sacrifice",
            colorHex: "#707070",
            intensity1: Intensity(nameDescription: "Quiet passing, accepted fate"),
            intensity2: Intensity(nameDescription: "Tragic loss, weight of death"),
            intensity3: Intensity(nameDescription: "Devastating sacrifice, epic tragedy")
        ),
        EmotionCategory(
            categoryName: "Magic / Wonder",
            colorHex: "#A0C8F0",
            intensity1: Intensity(nameDescription: "Curious, whimsical discovery"),
            intensity2: Intensity(nameDescription: "Enchanted, otherworldly"),
            intensity3: Intensity(nameDescription: "Grand magic, divine power")
        ),
    ]}
}

// MARK: - Intensity

struct Intensity: Identifiable, Codable {
    let id: UUID
    var nameDescription: String    // e.g. "Soft warmth, quiet contentment"
    var musicFileName: String?     // filename as stored in Documents
    var music: MusicFile?          // the actual file info

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

struct MusicFile: Identifiable, Codable {
    let id: UUID
    var title: String       // display name — user can rename
    var fileName: String    // actual filename stored in Documents/Music/

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
