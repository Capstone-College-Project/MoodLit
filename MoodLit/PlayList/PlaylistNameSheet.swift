//
//  PlaylistNameSheet.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.

import SwiftUI

// MARK: - PlaylistNameSheet
// Used for both creating and renaming a playlist.

struct PlaylistNameSheet: View {
    @Binding var name: String
    let title: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Playlist name", text: $name)
                        .foregroundColor(Color.text)
                        .tint(Color.gold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.surface2)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focused ? Color.gold : Color.text2.opacity(0.2), lineWidth: 1)
                        )
                        .focused($focused)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Spacer()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Continue") { onConfirm() }
                        .foregroundColor(isValid ? Color.gold : Color.text2)
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.height(160)])
        .onAppear { focused = true }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - AddCategorySheet
// Used inside PlaylistEditorView to create a custom emotion category.

struct AddCategorySheet: View {
    @Binding var name: String
    @Binding var color: Color
    @Binding var intensity1: String
    @Binding var intensity2: String
    @Binding var intensity3: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Category Name")
                                .font(.subheadline)
                                .foregroundColor(Color.text2)
                                .padding(.horizontal, 20)

                            TextField("e.g. Nostalgia", text: $name)
                                .foregroundColor(Color.text)
                                .tint(Color.gold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.surface2)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(focused ? Color.gold : Color.text2.opacity(0.2), lineWidth: 1)
                                )
                                .focused($focused)
                                .padding(.horizontal, 20)
                        }

                        HStack {
                            Text("Color")
                                .font(.subheadline)
                                .foregroundColor(Color.text2)
                            Spacer()
                            ColorPicker("", selection: $color, supportsOpacity: false)
                                .labelsHidden()
                                .frame(height: 44)
                        }
                        .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Intensity Descriptions")
                                .font(.subheadline)
                                .foregroundColor(Color.text2)
                                .padding(.horizontal, 20)

                            // Use the bindings directly — no local state
                            intensityField(number: "1", binding: $intensity1, placeholder: "e.g. Soft warmth, quiet contentment")
                            intensityField(number: "2", binding: $intensity2, placeholder: "e.g. Cheerful, light-hearted")
                            intensityField(number: "3", binding: $intensity3, placeholder: "e.g. Full celebration, jubilation")
                        }

                        Spacer()
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") { onConfirm() }
                        .foregroundColor(!name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gold : Color.text2)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { focused = true }
    }

    private func intensityField(number: String, binding: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundColor(Color.bg)
                .frame(width: 20, height: 20)
                .background(Color.gold)
                .clipShape(Circle())

            TextField(placeholder, text: binding)
                .foregroundColor(Color.text)
                .tint(Color.gold)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.surface2)
        .cornerRadius(10)
        .padding(.horizontal, 20)
    }
}
