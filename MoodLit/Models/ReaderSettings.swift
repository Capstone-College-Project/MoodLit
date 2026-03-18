//
//  ReaderSettings.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/4/26.
//
// ReaderSettings.swift
// MoodLit

import SwiftUI
import Combine
 
class ReaderSettings: ObservableObject {
    
    static let shared = ReaderSettings()
    private init() { load() }
    
    // MARK: - Published
    @Published var fontSize: Double = 17
    @Published var colorScheme: ReaderColorScheme = .dark
    @Published var backgroundTheme: ReaderBackground = .charcoal
    @Published var readerFont: ReaderFont = .georgia
    @Published var markerPosition: Double = 0.15
 
    // MARK: - Persistence
    private let key = "reader_settings"
 
    func save() {
        let dict: [String: Any] = [
            "fontSize":        fontSize,
            "colorScheme":     colorScheme.rawValue,
            "backgroundTheme": backgroundTheme.rawValue,
            "readerFont":      readerFont.rawValue,
            "markerPosition":  markerPosition
        ]
        UserDefaults.standard.set(dict, forKey: key)
    }
 
    private func load() {
        guard let dict = UserDefaults.standard.dictionary(forKey: key) else { return }
        if let v = dict["fontSize"]        as? Double                                          { fontSize        = v }
        if let v = dict["colorScheme"]     as? String, let e = ReaderColorScheme(rawValue: v)  { colorScheme     = e }
        if let v = dict["backgroundTheme"] as? String, let e = ReaderBackground(rawValue: v)   { backgroundTheme = e }
        if let v = dict["readerFont"]      as? String, let e = ReaderFont(rawValue: v)         { readerFont      = e }
        if let v = dict["markerPosition"]  as? Double                                          { markerPosition  = v }
    }
}
 
// MARK: - ReaderFont
 
enum ReaderFont: String, CaseIterable {
    case georgia     = "georgia"
    case palatino    = "palatino"
    case baskerville = "baskerville"
    case charter     = "charter"
    case systemSerif = "systemSerif"
    case systemSans  = "systemSans"
 
    var displayName: String {
        switch self {
        case .georgia:     return "Georgia"
        case .palatino:    return "Palatino"
        case .baskerville: return "Baskerville"
        case .charter:     return "Charter"
        case .systemSerif: return "System Serif"
        case .systemSans:  return "System Sans"
        }
    }
 
    func font(size: Double) -> Font {
        switch self {
        case .georgia:     return .custom("Georgia", size: size)
        case .palatino:    return .custom("Palatino-Roman", size: size)
        case .baskerville: return .custom("Baskerville", size: size)
        case .charter:     return .custom("Charter", size: size)
        case .systemSerif: return .system(size: size, weight: .regular, design: .serif)
        case .systemSans:  return .system(size: size, weight: .regular, design: .default)
        }
    }
}
 
// MARK: - ReaderColorScheme
 
enum ReaderColorScheme: String, CaseIterable {
    case dark  = "dark"
    case light = "light"
 
    var displayName: String {
        switch self { case .dark: return "Dark"; case .light: return "Light" }
    }
    var icon: String {
        switch self { case .dark: return "moon.fill"; case .light: return "sun.max.fill" }
    }
}
 
// MARK: - ReaderBackground
 
enum ReaderBackground: String, CaseIterable {
    case charcoal  = "charcoal"
    case parchment = "parchment"
    case forest    = "forest"
    case midnight  = "midnight"
    case warmGray  = "warmGray"
    
    var displayName: String {
        switch self {
        case .charcoal:  return "Charcoal"
        case .parchment: return "Parchment"
        case .forest:    return "Forest"
        case .midnight:  return "Midnight"
        case .warmGray:  return "Warm Gray"
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .charcoal:  return Color(hex: "#1A1A1A")
        case .parchment: return Color(hex: "#F5E6C8")
        case .forest:    return Color(hex: "#1A2318")
        case .midnight:  return Color(hex: "#0D0D1A")
        case .warmGray:  return Color(hex: "#2A2520")
        }
    }
    
    func textColor(scheme: ReaderColorScheme) -> Color {
        if scheme == .light || self == .parchment { return Color(hex: "#2A1F0E") }
        return Color(hex: "#F0E6D0")
    }
    
    func mutedTextColor(scheme: ReaderColorScheme) -> Color {
        if scheme == .light || self == .parchment { return Color(hex: "#6A5A40").opacity(0.8) }
        return Color(hex: "#8A7A60").opacity(0.8)
    }
    
    var surfaceColor: Color { backgroundColor.opacity(0.95) }
}
