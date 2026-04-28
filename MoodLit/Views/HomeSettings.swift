//
//  homeSettings.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 4/25/26.
//

import SwiftUI

// MARK: - homeSettings
struct HomeSettings: View {
    @ObservedObject var settings = ReaderSettings.shared
    @ObservedObject private var auth = AuthService.shared
    @StateObject private var tracker = LineTracker(musicEngine: MusicEngine())
    
    // Toggle password visibility
    @State private var showPassword: Bool = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            List {
                // MARK: - Font Section
                Section("Font") {
                    ForEach(ReaderFont.allCases, id: \.rawValue) { font in
                        Button {
                            settings.readerFont = font
                            settings.save()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(font.displayName)
                                        .font(font.font(size: 16))
                                        .foregroundColor(Color.text)
                                    Text("The old castle stood silent in the mist.")
                                        .font(font.font(size: 13))
                                        .foregroundColor(Color.text2)
                                }
                                Spacer()
                                if settings.readerFont == font {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color.gold)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            settings.readerFont == font
                                ? Color.gold.opacity(0.08)
                                : Color.surface
                        )
                    }
                }

                // MARK: - Font Size
                Section("Font Size") {
                    HStack(spacing: 12) {
                        Text("A")
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(Color.text2)
                        Slider(value: $settings.fontSize, in: 12...28, step: 1)
                            .accentColor(Color.gold)
                            .onChange(of: settings.fontSize) { _, _ in settings.save() }
                        Text("A")
                            .font(.system(size: 22, design: .serif))
                            .foregroundColor(Color.text2)
                    }
                    .padding(.vertical, 4)

                    Text("The old castle stood silent in the mist.")
                        .font(settings.readerFont.font(size: settings.fontSize))
                        .foregroundColor(Color.text)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.surface)
                }

                // MARK: - Background
                Section("Background") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(ReaderBackground.allCases, id: \.rawValue) { theme in
                            Button {
                                settings.backgroundTheme = theme
                                settings.save()
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(theme.backgroundColor)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gold.opacity(0.3), lineWidth: 1)
                                        )
                                    Text(theme.displayName)
                                        .font(.subheadline)
                                        .foregroundColor(Color.text)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    settings.backgroundTheme == theme
                                        ? Color.gold.opacity(0.12)
                                        : Color.surface2
                                )
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            settings.backgroundTheme == theme
                                                ? Color.gold
                                                : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.surface)
                }

                // MARK: - Reading Marker
                Section("Reading Marker") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Marker Position")
                            .font(.subheadline)
                            .foregroundColor(Color.text)
                        HStack(spacing: 8) {
                            Text("Top")
                                .font(.caption2)
                                .foregroundColor(Color.text2)
                            Slider(value: $settings.markerPosition, in: 0...1)
                                .accentColor(Color.gold)
                                .onChange(of: settings.markerPosition) { _, _ in
                                    settings.save()
                                }
                            Text("Bottom")
                                .font(.caption2)
                                .foregroundColor(Color.text2)
                        }

                        // Preview
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.backgroundTheme.backgroundColor)
                                .frame(height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.surface3, lineWidth: 1)
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(0..<5) { i in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.text2.opacity(0.2))
                                        .frame(
                                            width: CGFloat([120,150,90,140,110][i]),
                                            height: 3
                                        )
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.vertical, 10)

                            Rectangle()
                                .fill(Color.gold.opacity(0.6))
                                .frame(height: 1.5)
                                .offset(y: -40 + 80 * CGFloat(settings.markerPosition))
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.surface)

                    // Auto-scroll speed
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auto-scroll Speed")
                            .font(.subheadline)
                            .foregroundColor(Color.text)
                        HStack(spacing: 8) {
                            Image(systemName: "tortoise.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color.text2)
                            Slider(value: $tracker.sliderValue, in: 0...1)
                                .accentColor(Color.gold)
                            Image(systemName: "hare.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color.text2)
                        }
                        Text("\(Int(tracker.scrollSpeed)) pts/sec")
                            .font(.caption2)
                            .foregroundColor(Color.text2)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.surface)
                    
                    // MARK: - Log Out
                    Section {
                        Button {
                            auth.logOut()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.red)
                                    .frame(width: 28, height: 28)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)

                                Text("Log Out")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.red)

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.surface)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bg)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
