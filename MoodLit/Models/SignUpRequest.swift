//
//  SignUpRequest.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/28/26.
//


import Foundation

// MARK: - Request Models

struct AppleLoginRequest: Codable {
    let identityToken: String
    let fullName: String?
    let email: String?
}

struct SignUpRequest: Codable {
    let fullName: String
    let email: String
    let password: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct ForgotPasswordRequest: Codable {
    let email: String
}

struct VerifyCodeRequest: Codable {
    let email: String
    let code: String
}

struct ResetPasswordRequest: Codable {
    let email: String
    let code: String
    let newPassword: String
}

// MARK: - Response Models

struct AuthResponse: Codable {
    let token: String
    let user: UserDTO
}

struct UserDTO: Codable, Identifiable {
    let id: UUID
    let fullName: String
    let email: String
    let authProvider: String 
}

struct MessageResponse: Codable {
    let message: String
}

struct ErrorResponse: Codable {
    let error: String
}
