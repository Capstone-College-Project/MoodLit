//
//  EmotionCategorySection.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - EmotionCategorySection

struct EmotionCategorySection: View {
    @Binding var emotion: EmotionCategory
    let isExpanded: Bool
    let onTapHeader: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded { slots }
        }
    }

    // MARK: - Header
    private var header: some View {
        Button(action: onTapHeader) {
            HStack(spacing: 12) {
                Circle()
                    .fill(emotion.color)
                    .frame(width: 14, height: 14)

                Text(emotion.categoryName)
                    .font(.headline)
                    .foregroundColor(Color.text)
                    .fixedSize(horizontal: false, vertical: true)  

                Spacer()

                let filled = [emotion.intensity1, emotion.intensity2, emotion.intensity3]
                    .filter { $0.hasTrack }.count
                if filled > 0 {
                    Text("\(filled)/3")
                        .font(.caption2)
                        .foregroundColor(Color.text2)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(Color.text2)
                    .animation(.none, value: isExpanded)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .animation(.none, value: isExpanded)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Intensity Slots

    private var slots: some View {
        VStack(spacing: 6) {
            IntensityRow(label: "1", intensity: $emotion.intensity1, onSave: onSave)
            IntensityRow(label: "2", intensity: $emotion.intensity2, onSave: onSave)
            IntensityRow(label: "3", intensity: $emotion.intensity3, onSave: onSave)
        }
        .padding(.bottom, 10)
    }
}

// MARK: - IntensityRow

struct IntensityRow: View {
    let label: String
    @Binding var intensity: Intensity
    let onSave: () -> Void

    @State private var showFilePicker = false
    @State private var isEditingDescription = false
    @State private var descriptionDraft = ""

    var body: some View {
        HStack(spacing: 12) {
            levelBadge
            trackInfo
            Spacer()
            actionButton
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.surface2)
        .cornerRadius(10)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: audioTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result)
        }
    }

    // MARK: - Sub-views

    private var levelBadge: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundColor(Color.bg)
            .frame(width: 20, height: 20)
            .background(Color.gold)
            .clipShape(Circle())
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            if isEditingDescription {
                TextField("Description", text: $descriptionDraft, onCommit: {
                    intensity.nameDescription = descriptionDraft
                    isEditingDescription = false
                    onSave()
                })
                .font(.subheadline)
                .foregroundColor(Color.text)
                .tint(Color.gold)
            } else {
                Text(intensity.nameDescription)
                    .font(.subheadline)
                    .foregroundColor(Color.text)
                    .onTapGesture {
                        descriptionDraft = intensity.nameDescription
                        isEditingDescription = true
                    }
            }

            if let music = intensity.music {
                Text(music.title)
                    .font(.caption)
                    .foregroundColor(Color.gold)
                    .lineLimit(1)
            } else {
                Text("Tap to upload")
                    .font(.caption)
                    .foregroundColor(Color.text2)
            }
        }
    }

    private var actionButton: some View {
        Button {
            if intensity.hasTrack {
                intensity.music = nil
                intensity.musicFileName = nil
                onSave()
            } else {
                showFilePicker = true
            }
        } label: {
            Image(systemName: intensity.hasTrack ? "xmark.circle" : "square.and.arrow.up")
                .font(.system(size: 16))
                .foregroundColor(intensity.hasTrack ? Color.text2 : Color.gold)
        }
        .buttonStyle(.plain)
    }

    // MARK: - File Handling

    private var audioTypes: [UTType] {
        [UTType.audio]
    }

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
            intensity.music = MusicFile(
                title: url.deletingPathExtension().lastPathComponent,
                fileName: url.lastPathComponent
            )
            intensity.musicFileName = url.lastPathComponent
            onSave()
        } catch {
            print("❌ Music import error: \(error)")
        }
    }
}
