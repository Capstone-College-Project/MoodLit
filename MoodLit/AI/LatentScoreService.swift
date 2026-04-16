//
//  LatentScoreService.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 4/14/26.
//


import Foundation

// MARK: - LatentScoreService
//
// Fetches AI-generated music from the LatentScore server running on
// the Mac. Responses are cached on the device so repeated reads of the
// same scene don't re-render.

final class LatentScoreService {
    static let shared = LatentScoreService()
    
    // Must match your Mac's IP and the port the Python server uses.
    private let endpoint = URL(string: "http://192.168.40.5:8765/generate")!
    
    private init() {
        createCacheDirectoryIfNeeded()
    }
    
    // MARK: - Public API
    
    /// Returns a local file URL for audio matching the given prompt.
    /// Downloads from LatentScore if not already cached.
    func audioURL(for prompt: String, duration: Double = 60.0) async throws -> URL {
        let cachedURL = localCacheURL(for: prompt, duration: duration)
        
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            print("🎼 LatentScore cache hit — \(prompt.prefix(60))")
            return cachedURL
        }
        
        print("🎼 LatentScore fetching — \(prompt.prefix(60))")
        try await downloadAudio(prompt: prompt, duration: duration, to: cachedURL)
        return cachedURL
    }
    
    // MARK: - Private
    
    private func downloadAudio(prompt: String, duration: Double, to destURL: URL) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "prompt": prompt,
            "duration": duration
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LatentScoreError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
            throw LatentScoreError.serverError(httpResponse.statusCode, errorText)
        }
        
        try data.write(to: destURL, options: .atomic)
    }
    
    private func localCacheURL(for prompt: String, duration: Double) -> URL {
        let key = "\(prompt)|\(duration)"
        let hash = key.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(32) ?? "fallback"
        return cacheDirectory().appendingPathComponent("\(hash).wav")
    }
    
    private func cacheDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Streamed", isDirectory: true)
    }
    
    private func createCacheDirectoryIfNeeded() {
        let dir = cacheDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        let dir = cacheDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        print("🎼 LatentScore cache cleared")
    }
    
    func cacheSize() -> Int64 {
        let dir = cacheDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }
}

// MARK: - Errors

enum LatentScoreError: LocalizedError {
    case invalidResponse
    case serverError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LatentScore server returned an invalid response."
        case .serverError(let code, let message):
            return "LatentScore server error \(code): \(message)"
        }
    }
}