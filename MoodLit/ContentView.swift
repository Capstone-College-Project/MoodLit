//
//  ContentView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/1/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var auth = AuthService.shared

    var body: some View {
        NavigationStack {
            if auth.isAuthenticated {
                Home()
            } else {
                WelcomeScreen()
            }
        }
        .id(auth.isAuthenticated) 
    }
}

#Preview {
    ContentView()
}
