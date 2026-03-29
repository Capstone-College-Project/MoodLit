//
//  ResetPasswordView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/27/26.
//


import SwiftUI

struct ResetPasswordView: View {
    
    let email: String   // passed from CodeInputView
    let code: String    // passed from CodeInputView
    
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var showNewPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @State private var resetSuccess: Bool = false
    @ObservedObject var auth = AuthService.shared
    @Environment(\.dismiss) var dismiss
    
    // Password requirements
    var hasMinLength: Bool { newPassword.count >= 8 }
    var hasUppercase: Bool { newPassword.range(of: "[A-Z]", options: .regularExpression) != nil }
    var hasNumber: Bool { newPassword.range(of: "[0-9]", options: .regularExpression) != nil }
    var hasSpecial: Bool { newPassword.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil }
    var passwordsMatch: Bool { !confirmPassword.isEmpty && newPassword == confirmPassword }
    var allValid: Bool { hasMinLength && hasUppercase && hasNumber && passwordsMatch }
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            if resetSuccess {
                successView
            } else {
                formView
            }
        }
    }
    
    // MARK: - Form View
    var formView: some View {
        VStack(spacing: 0) {
            
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(Color.text)
                        .frame(width: 40, height: 40)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(Color.gold, lineWidth: 1)
                        }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    
                    Spacer().frame(height: 30)
                    
                    Image(systemName: "key.rotate")
                        .font(.system(size: 36))
                        .foregroundColor(Color.gold)
                        .frame(width: 80, height: 80)
                        .background(Color.yellow.opacity(0.1))
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(Color.gold, lineWidth: 1)
                        }
                        .padding(.bottom, 24)
                    
                    Text("Create New Password")
                        .font(.custom("Georgia", size: 26))
                        .foregroundColor(Color.text)
                        .padding(.bottom, 8)
                    
                    Text("Your new password must be different\nfrom your previous password")
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(Color.text.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 36)
                    
                    // New Password Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NEW PASSWORD")
                            .font(.custom("Georgia", size: 11))
                            .tracking(1)
                            .foregroundColor(Color.text.opacity(0.4))
                        
                        HStack {
                            Group {
                                if showNewPassword {
                                    TextField("", text: $newPassword)
                                } else {
                                    SecureField("", text: $newPassword)
                                }
                            }
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.custom("Georgia", size: 15))
                            .foregroundColor(Color.text)
                            
                            Button {
                                showNewPassword.toggle()
                            } label: {
                                Image(systemName: showNewPassword ? "eye.slash" : "eye")
                                    .foregroundColor(Color.text.opacity(0.4))
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(14)
                        .background(Color.yellow.opacity(0.08))
                        .cornerRadius(12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gold.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    
                    // Requirements
                    VStack(alignment: .leading, spacing: 8) {
                        RequirementRow(text: "At least 8 characters", met: hasMinLength)
                        RequirementRow(text: "One uppercase letter", met: hasUppercase)
                        RequirementRow(text: "One number", met: hasNumber)
                        RequirementRow(text: "One special character", met: hasSpecial)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    // Confirm Password Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONFIRM PASSWORD")
                            .font(.custom("Georgia", size: 11))
                            .tracking(1)
                            .foregroundColor(Color.text.opacity(0.4))
                        
                        HStack {
                            Group {
                                if showConfirmPassword {
                                    TextField("", text: $confirmPassword)
                                } else {
                                    SecureField("", text: $confirmPassword)
                                }
                            }
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.custom("Georgia", size: 15))
                            .foregroundColor(Color.text)
                            
                            Button {
                                showConfirmPassword.toggle()
                            } label: {
                                Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                    .foregroundColor(Color.text.opacity(0.4))
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(14)
                        .background(Color.yellow.opacity(0.08))
                        .cornerRadius(12)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    !confirmPassword.isEmpty && !passwordsMatch
                                        ? Color.red.opacity(0.6)
                                        : Color.gold.opacity(0.3),
                                    lineWidth: 1
                                )
                        }
                        
                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords do not match")
                                .font(.custom("Georgia", size: 11))
                                .foregroundColor(.red.opacity(0.7))
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    
                    // Error from backend
                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.custom("Georgia", size: 12))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.bottom, 16)
                    }
                    
                    // Reset Button
                    Button {
                        Task {
                            let success = await auth.resetPassword(
                                email: email,
                                code: code,
                                newPassword: newPassword
                            )
                            if success {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    resetSuccess = true
                                }
                            }
                        }
                    } label: {
                        if auth.isLoading {
                            ProgressView()
                                .tint(Color.bg)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    LinearGradient(
                                        colors: [Color.gold, Color.gold.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(14)
                        } else {
                            Text("RESET PASSWORD")
                                .font(.custom("Georgia", size: 15).weight(.bold))
                                .tracking(2)
                                .foregroundColor(Color.bg)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    LinearGradient(
                                        colors: [Color.gold, Color.gold.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal, 20)
                    .opacity(allValid ? 1.0 : 0.4)
                    .disabled(!allValid || auth.isLoading)
                }
            }
        }
    }
    
    // MARK: - Success View
    var successView: some View {
        VStack(spacing: 0) {
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(Color.green)
                .padding(.bottom, 28)
            
            Text("Password Reset!")
                .font(.custom("Georgia", size: 28))
                .foregroundColor(Color.text)
                .padding(.bottom, 10)
            
            Text("Your password has been changed\nsuccessfully. You can now sign in\nwith your new password.")
                .font(.custom("Georgia", size: 14))
                .foregroundColor(Color.text.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 44)
            
            Button {
                dismiss()
            } label: {
                Text("BACK TO SIGN IN")
                    .font(.custom("Georgia", size: 15).weight(.bold))
                    .tracking(2)
                    .foregroundColor(Color.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [Color.gold, Color.gold.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
}

// MARK: - Requirement Row
struct RequirementRow: View {
    let text: String
    let met: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(met ? Color.green : Color.text.opacity(0.2))
                .frame(width: 7, height: 7)
            
            Text(text)
                .font(.custom("Georgia", size: 12))
                .foregroundColor(met ? Color.green : Color.text.opacity(0.3))
        }
        .animation(.easeInOut(duration: 0.2), value: met)
    }
}
