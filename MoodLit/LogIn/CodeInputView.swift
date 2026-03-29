//
//  CodeInputView.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/27/26.
//


import SwiftUI

struct CodeInputView: View {
    
    let email: String  // passed from ForgotPassword
    
    @State private var code: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedIndex: Int?
    @State private var showResetPassword: Bool = false
    @State private var showError: Bool = false
    @ObservedObject var auth = AuthService.shared
    @Environment(\.dismiss) var dismiss
    
    var enteredCode: String { code.joined() }
    var allFilled: Bool { code.allSatisfy { !$0.isEmpty } }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    Spacer().frame(height: 40)
                    
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundColor(Color.gold)
                        .frame(width: 80, height: 80)
                        .background(Color.yellow.opacity(0.1))
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(Color.gold, lineWidth: 1)
                        }
                        .padding(.bottom, 24)
                    
                    Text("Enter Verification Code")
                        .font(.custom("Georgia", size: 26))
                        .foregroundColor(Color.text)
                        .padding(.bottom, 8)
                    
                    Text("We sent a 6-digit code to\n\(email)")
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(Color.text.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                    
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            CodeBox(
                                text: $code[index],
                                isFocused: focusedIndex == index,
                                hasError: showError,
                                onTap: { focusedIndex = index }
                            )
                            .focused($focusedIndex, equals: index)
                            .onChange(of: code[index]) { newValue in
                                if showError { showError = false }
                                
                                if newValue.count > 1 {
                                    code[index] = String(newValue.last ?? Character(""))
                                }
                                if !newValue.isEmpty && index < 5 {
                                    focusedIndex = index + 1
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    
                    // Error message
                    if showError, let error = auth.errorMessage {
                        Text(error)
                            .font(.custom("Georgia", size: 12))
                            .foregroundColor(.red.opacity(0.8))
                            .transition(.opacity)
                    }
                    
                    Spacer().frame(height: 28)
                    
                    // Verify button
                    Button {
                        Task {
                            let success = await auth.verifyCode(
                                email: email,
                                code: enteredCode
                            )
                            if success {
                                showError = false
                                showResetPassword = true
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showError = true
                                }
                                shakeAndClear()
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
                            Text("VERIFY")
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
                    .opacity(allFilled ? 1.0 : 0.5)
                    .disabled(!allFilled || auth.isLoading)
                    
                    Spacer().frame(height: 24)
                    
                    HStack(spacing: 4) {
                        Text("Didn't receive a code?")
                            .foregroundColor(Color.text.opacity(0.4))
                        
                        Button("Resend") {
                            Task {
                                await auth.forgotPassword(email: email)
                            }
                            resetFields()
                        }
                        .foregroundColor(Color.gold)
                        .fontWeight(.semibold)
                    }
                    .font(.custom("Georgia", size: 13))
                    
                    Spacer()
                }
            }
            .onAppear { focusedIndex = 0 }
            .navigationDestination(isPresented: $showResetPassword) {
                ResetPasswordView(email: email, code: enteredCode)
            }
            .navigationBarBackButtonHidden(true)
        }
    }
    
    private func shakeAndClear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                code = Array(repeating: "", count: 6)
                focusedIndex = 0
            }
        }
    }
    
    private func resetFields() {
        code = Array(repeating: "", count: 6)
        showError = false
        focusedIndex = 0
    }
}
