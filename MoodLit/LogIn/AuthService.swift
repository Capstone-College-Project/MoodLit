//
//  AuthService.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/28/26.
//


// AuthService.swift
// MoodLit

import Foundation
import Combine

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    // Change this to your actual server URL
    // Use your machine's local IP for simulator (not localhost)
    private let baseURL = "http://192.168.40.5:8080/api/auth"

    @Published var currentUser: UserDTO? = nil
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private var token: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set {
            if let val = newValue {
                UserDefaults.standard.set(val, forKey: "auth_token")
            } else {
                UserDefaults.standard.removeObject(forKey: "auth_token")
            }
        }
    }

    init() {
        // Auto-restore session if token exists
        if token != nil {
            isAuthenticated = true
        }
    }

    // MARK: - Sign Up

    func signUp(fullName: String, email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = SignUpRequest(fullName: fullName, email: email, password: password)

        do {
            let response: AuthResponse = try await post(endpoint: "/signup", body: body)
            token = response.token
            currentUser = response.user
            isAuthenticated = true
            return true
        } catch let err as APIError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = "Connection failed. Check your network."
            return false
        }
    }

    // MARK: - Log In

    func logIn(email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = LoginRequest(email: email, password: password)

        do {
            let response: AuthResponse = try await post(endpoint: "/login", body: body)
            token = response.token
            currentUser = response.user
            isAuthenticated = true
            return true
        } catch let err as APIError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = "Connection failed. Check your network."
            return false
        }
    }

    // MARK: - Forgot Password

    func forgotPassword(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = ForgotPasswordRequest(email: email)

        do {
            let _: MessageResponse = try await post(endpoint: "/forgot-password", body: body)
            return true
        } catch let err as APIError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = "Connection failed. Check your network."
            return false
        }
    }

    // MARK: - Verify Code

    func verifyCode(email: String, code: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = VerifyCodeRequest(email: email, code: code)

        do {
            let _: MessageResponse = try await post(endpoint: "/verify-code", body: body)
            return true
        } catch let err as APIError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = "Connection failed. Check your network."
            return false
        }
    }

    // MARK: - Reset Password

    func resetPassword(email: String, code: String, newPassword: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = ResetPasswordRequest(email: email, code: code, newPassword: newPassword)

        do {
            let _: MessageResponse = try await post(endpoint: "/reset-password", body: body)
            return true
        } catch let err as APIError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = "Connection failed. Check your network."
            return false
        }
    }

    // MARK: - Log Out

    func logOut() {
        token = nil
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Apple Sign In

    func appleLogin(identityToken: String, fullName: String?, email: String?) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let body = AppleLoginRequest(
            identityToken: identityToken,
            fullName: fullName,
            email: email
        )
        
        do {
            let response: AuthResponse = try await post(endpoint: "/apple", body: body)
            token = response.token
            currentUser = response.user
            isAuthenticated = true
            return true
        } catch let err as APIError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = "Apple Sign In failed. Please try again."
            return false
        }
    }

    // MARK: - Network Helper

    private func post<T: Codable, R: Codable>(endpoint: String, body: T) async throws -> R {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid server response")
        }

        if http.statusCode >= 200 && http.statusCode < 300 {
            return try JSONDecoder().decode(R.self, from: data)
        } else {
            if let errorResp = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError(message: errorResp.error)
            }
            throw APIError(message: "Server error (\(http.statusCode))")
        }
    }
}

// MARK: - API Error

struct APIError: Error {
    let message: String
}
