    //
    //  PlaylistRow.swift
    //  MoodLit
    //
    //  Created by Anthony Chang Martinez on 3/8/26.
    // Display information of the playlist to the screen

    import SwiftUI

    struct PlaylistRow: View {
        let playlist: Playlist

        var body: some View {
            HStack(spacing: 14) {
                icon
                info
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.text2)
            }
            .padding(.vertical, 8)

        }
        

        // MARK: - Icon
        //Shows an icon with dots related to emtions
        private var icon: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.surface2)
                    .frame(width: 48, height: 48)

                let filled = playlist.emotions.filter { $0.hasAnyTrack }

                if filled.isEmpty {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 20))
                        .foregroundColor(Color.text2)
                } else {
                    // Up to 4 emotion color dots
                    LazyVGrid(
                        columns: [GridItem(.fixed(10)), GridItem(.fixed(10))],
                        spacing: 4
                    ) {
                        ForEach(Array(filled.prefix(4))) { emotion in
                            Circle()
                                .fill(emotion.color)
                                .frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }

        // MARK: - Info
        //Shows the number of tracks and and the emetions they cover
        private var info: some View {
            let filledCount = playlist.emotions.filter { $0.hasAnyTrack }.count
            let subtitle = playlist.totalTracks == 0
                ? "No tracks yet"
                : "\(playlist.totalTracks) track\(playlist.totalTracks == 1 ? "" : "s") · \(filledCount) emotion\(filledCount == 1 ? "" : "s")"

            return VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .foregroundColor(Color.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color.text2)
            }
        }
    }
