//
//  SceneTagEditorSheet.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/11/26.

//appears when creating or editing a scene tag. It lets the user pick an emotion category,
//set intensity, adjust the line range, and optionally override the music track.


import SwiftUI
import UniformTypeIdentifiers

struct SceneTagEditorSheet: View {

    let bookID: UUID
    let page: Int
    let startLine: Int
    var endLine: Int
    let playlist: Playlist
    var existingTag: SceneTag? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryID: UUID?
    @State private var selectedIntensity: Int = 1
    @State private var editedEndLine: Int
    @State private var showFilePicker = false
    @State private var musicOverride: MusicFile? = nil

    init(
        bookID: UUID,
        page: Int,
        startLine: Int,
        endLine: Int,
        playlist: Playlist,
        existingTag: SceneTag? = nil
    ) {
        self.bookID = bookID
        self.page = page
        self.startLine = startLine
        self.endLine = endLine
        self.playlist = playlist
        self.existingTag = existingTag
        _editedEndLine = State(initialValue: existingTag?.endLine ?? endLine)
        _selectedCategoryID = State(initialValue: existingTag?.emotionCategoryID)
        _selectedIntensity = State(initialValue: existingTag?.intensityLevel ?? 1)
        _musicOverride = State(initialValue: existingTag?.musicOverride)
    }

    //Selects an emtion according to id of the selectedCategory by user
    private var selectedCategory: EmotionCategory? {
        playlist.emotions.first { $0.id == selectedCategoryID }
    }

    //Returns the track assigned to that categiry
    private var playlistTrack: MusicFile? {
        guard let cat = selectedCategory else { return nil }
        switch selectedIntensity {
        case 1: return cat.intensity1.music
        case 2: return cat.intensity2.music
        default: return cat.intensity3.music
        }
    }

    //Shows a description for the intensity
    private var intensityDescription: String {
        guard let cat = selectedCategory else { return "" }
        switch selectedIntensity {
        case 1: return cat.intensity1.nameDescription
        case 2: return cat.intensity2.nameDescription
        default: return cat.intensity3.nameDescription
        }
    }

    //Save is disabled until a selection is made
    private var canSave: Bool { selectedCategoryID != nil }

    var body: some View {
        ZStack(alignment: .top) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {

                // Manual header bar
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color.text2)
                        .font(.body)

                    Spacer()

                    Text(existingTag == nil ? "Tag Scene" : "Edit Tag")
                        .font(.headline)
                        .foregroundColor(Color.text)

                    Spacer()

                    Button("Save") { save() }
                        .foregroundColor(canSave ? Color.gold : Color.text2)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.surface)

                Divider().background(Color.surface3)

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        locationSection
                        emotionSection
                        intensitySection
                        musicSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result)
        }
    }

    // MARK: - Location

    // Add this computed property alongside your other ones
    private var expandedCount: Int {
        editedEndLine - endLine
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Location")

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page").font(.caption).foregroundColor(Color.text2)
                    Text("\(page)").font(.headline).foregroundColor(Color.text)
                }

                Divider().frame(height: 30).background(Color.surface3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start").font(.caption).foregroundColor(Color.text2)
                    Text("\(startLine)").font(.headline).foregroundColor(Color.text)
                }

                Divider().frame(height: 30).background(Color.surface3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("End").font(.caption).foregroundColor(Color.text2)
                    HStack(spacing: 8) {
                        Text("\(editedEndLine)").font(.headline).foregroundColor(Color.text)
                        Stepper("", value: $editedEndLine, in: startLine...startLine + 200)
                            .labelsHidden()
                    }
                }
            }
            .padding(14)
            .background(Color.surface)
            .cornerRadius(12)

            // Line counter
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "text.line.last.and.arrowtriangle.forward")
                        .font(.system(size: 11))
                        .foregroundColor(Color.text2)
                    Text("\(editedEndLine - startLine) lines selected")
                        .font(.caption)
                        .foregroundColor(Color.text2)
                }

                if expandedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color.gold)
                        Text("\(expandedCount) expanded")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Color.gold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gold.opacity(0.12))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Emotion
    //Displays list of all categories
    //allows user to select one
    private var emotionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Emotion")

            if playlist.emotions.isEmpty {
                Text("No categories in this playlist yet.")
                    .font(.subheadline)
                    .foregroundColor(Color.text2)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface)
                    .cornerRadius(12)
            } else {
                ForEach(playlist.emotions) { category in
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 12, height: 12)

                            Text(category.categoryName)
                                .font(.subheadline)
                                .foregroundColor(Color.text)

                            Spacer()

                            if selectedCategoryID == category.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color.gold)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            selectedCategoryID == category.id
                                ? Color.gold.opacity(0.08) : Color.surface
                        )
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    selectedCategoryID == category.id
                                        ? Color.gold.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Intensity
    //Lets user pick  intensity for scene
    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Intensity")

            HStack(spacing: 10) {
                ForEach(1...3, id: \.self) { level in
                    Button {
                        selectedIntensity = level
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 3) {
                                ForEach(0..<3) { dot in
                                    Circle()
                                        .fill(dot < level ? Color.gold : Color.surface3)
                                        .frame(width: 7, height: 7)
                                }
                            }
                            Text("\(level)")
                                .font(.headline)
                                .foregroundColor(selectedIntensity == level ? Color.gold : Color.text2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selectedIntensity == level ? Color.gold.opacity(0.1) : Color.surface
                        )
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    selectedIntensity == level
                                        ? Color.gold.opacity(0.5) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !intensityDescription.isEmpty {
                Text(intensityDescription)
                    .font(.caption)
                    .foregroundColor(Color.text2)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Music
    //Allows user to see which track user is selecting
    //If user can override current track or assing track if
    //no music is has been assign to this intensity
    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Music")

            VStack(alignment: .leading, spacing: 6) {
                Text("From Playlist")
                    .font(.caption)
                    .foregroundColor(Color.text2)

                if let track = playlistTrack {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .foregroundColor(Color.gold)
                            .font(.system(size: 13))
                        Text(track.title)
                            .font(.subheadline)
                            .foregroundColor(Color.text)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface)
                    .cornerRadius(10)
                } else {
                    Text("No track assigned to this emotion / intensity")
                        .font(.caption)
                        .foregroundColor(Color.text2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface)
                        .cornerRadius(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Override (optional)")
                    .font(.caption)
                    .foregroundColor(Color.text2)

                if let override = musicOverride {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .foregroundColor(Color.gold)
                            .font(.system(size: 13))
                        Text(override.title)
                            .font(.subheadline)
                            .foregroundColor(Color.text)
                        Spacer()
                        Button { musicOverride = nil } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(Color.text2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.surface)
                    .cornerRadius(10)
                } else {
                    Button { showFilePicker = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(Color.gold)
                                .font(.system(size: 13))
                            Text("Upload different track for this scene")
                                .font(.subheadline)
                                .foregroundColor(Color.gold)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gold.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Color.text2)
    }
    

    //Creates a Scene Tag, and save its, which is an old tag the id remains the same
    //new tag a new id is created
    private func save() {
        guard let categoryID = selectedCategoryID else { return }
        let tag = SceneTag(
            id: existingTag?.id ?? UUID(),
            page: page,
            startLine: startLine,
            endLine: editedEndLine,
            emotionCategoryID: categoryID,
            intensityLevel: selectedIntensity,
            musicOverride: musicOverride
        )
        SceneTagEngine.save(tag, to: bookID)
        dismiss()
    }

    //Helps import Music from File for Music Override feature.
    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let musicDir = docs.appendingPathComponent("Music")
            try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
            let dest = musicDir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.copyItem(at: url, to: dest)
            }
            musicOverride = MusicFile(
                title: url.deletingPathExtension().lastPathComponent,
                fileName: url.lastPathComponent
            )
        } catch {
            print("❌ Music override import: \(error)")
        }
    }
}
