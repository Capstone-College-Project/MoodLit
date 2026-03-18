//
//  CreateWebNovelSheet.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/14/26.
//


import SwiftUI

struct CreateWebNovelSheet: View {
    @ObservedObject private var library = LibraryManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var author: String = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                VStack(spacing: 24) {

                    // Icon
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color.gold)

                        Text("Create a Web Novel")
                            .font(.headline)
                            .foregroundColor(Color.text)

                        Text("Add chapters one at a time as they release.")
                            .font(.subheadline)
                            .foregroundColor(Color.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title")
                                .font(.caption)
                                .foregroundColor(Color.text2)
                            TextField("e.g. Solo Leveling", text: $title)
                                .font(.subheadline)
                                .foregroundColor(Color.text)
                                .padding(12)
                                .background(Color.surface)
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Author (optional)")
                                .font(.caption)
                                .foregroundColor(Color.text2)
                            TextField("e.g. Chugong", text: $author)
                                .font(.subheadline)
                                .foregroundColor(Color.text)
                                .padding(12)
                                .background(Color.surface)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("New Web Novel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        let novel = Book.newWebNovel(
                            title: title.trimmingCharacters(in: .whitespaces),
                            author: author.trimmingCharacters(in: .whitespaces)
                        )
                        library.addWebNovel(novel)
                        dismiss()
                    }
                    .foregroundColor(canSave ? Color.gold : Color.text2)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}