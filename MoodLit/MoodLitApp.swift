//
//  MoodLitApp.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/1/26.
//

import SwiftUI

@main
struct MoodLitApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
           ContentView()
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            if newValue == .background {
                LibraryManager.shared.save()
            }
        }
    }
}
