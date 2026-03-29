//
//  ForgotPassword.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/27/26.
//
import SwiftUI

struct ForgotPassword: View {
    
    @State var email: String = ""
    @State private var navigateToCode: Bool = false
    @ObservedObject var auth = AuthService.shared
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack {
                Image(systemName: "envelope")
                    .font(Font.largeTitle)
                    .foregroundColor(.gold)
                    .padding(28)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gold.opacity(0.3), lineWidth: 1)
                    )
                
                Text("Reset Password")
                    .font(.largeTitle)
                    .foregroundColor(Color.text)
                    .padding()
                
                Text("Enter the email associated with your account")
                    .font(.headline)
                    .foregroundColor(Color.text.opacity(0.4))
                    .padding()
                
                userDetails(title: "Email", userInput: $email)
                    .padding()
                
                // Error message
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }
                
                // Get Code button
                Button {
                    Task {
                        let success = await auth.forgotPassword(email: email)
                        if success {
                            navigateToCode = true
                        }
                    }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .tint(Color.surface)
                            .frame(width: 350, height: 70)
                            .background(Color.gold)
                            .cornerRadius(15)
                    } else {
                        Text("GET CODE")
                            .frame(width: 350, height: 70)
                            .foregroundColor(.surface)
                            .background(Color.gold)
                            .cornerRadius(15)
                    }
                }
                .disabled(email.isEmpty || auth.isLoading)
                .opacity(email.isEmpty ? 0.5 : 1.0)
            }
        }
        .navigationDestination(isPresented: $navigateToCode) {
            CodeInputView(email: email)
        }
    }
}
