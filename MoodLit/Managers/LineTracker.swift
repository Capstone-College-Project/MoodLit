// LineTracker.swift
// MoodLit
//
// Tracks which page and line the marker is currently on.
// The BookReaderView observes this to highlight the active line.
// The MusicEngine observes this to trigger track changes.


import Foundation
import Combine
import CoreGraphics

class LineTracker: ObservableObject {

    // MARK: - Published State
    @Published var activePage: Int = 0
    @Published var activeLine: Int = 0

    // MARK: - Marker State
    @Published var markerY: CGFloat = 120
    @Published var dragStartY: CGFloat = 120
    @Published var isAutoScrolling: Bool = false
    @Published var scrollSpeed: Double = 30        // points per second

    // MARK: - Internal
    var lineAccumulator: Double = 0

    // Quadratic slider: bottom half = slow, top half = fast
    var sliderValue: Double {
        get { sqrt((scrollSpeed - 5) / 95) }
        set { scrollSpeed = (newValue * newValue * 95) + 5 }
    }

    // MARK: - Dependencies
    private let musicEngine: MusicEngine
    private var cancellables = Set<AnyCancellable>()

    init(musicEngine: MusicEngine) {
        self.musicEngine = musicEngine
    }

    // MARK: - Marker drag
    // PageView's detectActiveLine handles line detection from geometry —
    // LineTracker just stores the Y position.

    func markerMoved(to y: CGFloat) {
        markerY = y
        dragStartY = y
    }

    // MARK: - Auto-scroll

    func toggleAutoScroll() {
        isAutoScrolling.toggle()
        lineAccumulator = 0
    }

    func tick() {
        guard isAutoScrolling else { return }
        // Actual scrollOffset increment happens in PageView's onReceive(ticker)
        // This is kept for any future line-based advance logic
    }

    // MARK: - Progress

    func restoreProgress(_ progress: ReadingProgress) {
        activePage = progress.pageIndex
        activeLine = progress.lineIndex
        scrollSpeed = progress.markerSpeed
    }

    func toProgress() -> ReadingProgress {
        ReadingProgress(
            pageIndex: activePage,
            lineIndex: activeLine,
            markerSpeed: scrollSpeed,
            isAutoScrolling: isAutoScrolling
        )
    }
}
