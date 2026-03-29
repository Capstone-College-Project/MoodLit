//
//  SignUp.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/25/26.
// Sign Up page to let user Create Account

import SwiftUI
import AuthenticationServices

struct SignUp: View {
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var navigateToHome: Bool = false
    @ObservedObject var auth = AuthService.shared
    
    var hasMinLength: Bool { password.count >= 8 }
    var hasUppercase: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
    var hasNumberOrSymbol: Bool { password.range(of: "[0-9!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil }
    var allValid: Bool { hasMinLength && hasUppercase && hasNumberOrSymbol && !name.isEmpty && !email.isEmpty }
    
    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            
            VStack(alignment: .leading) {
                
                Text("Create Account")
                    .font(.largeTitle)
                    .foregroundColor(Color.text)
                    .padding()
                
                Text("Begin your reading journey!")
                    .font(.headline)
                    .foregroundColor(Color.text.opacity(0.4))
                    .padding()
                
                userDetails(title: "Name", userInput: $name)
                userDetails(title: "Email", userInput: $email)
                userDetails(title: "Password", userInput: $password)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(hasMinLength ? Color.green : Color.text.opacity(0.2))
                        .frame(width: 6, height: 6)
                    Text("At least 8 characters long")
                        .font(.headline)
                        .foregroundColor(hasMinLength ? Color.green : Color.text.opacity(0.4))
                }
                .padding(.top, 5).padding(.bottom, 5)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(hasUppercase ? Color.green : Color.text.opacity(0.2))
                        .frame(width: 6, height: 6)
                    Text("At least 1 uppercase character")
                        .font(.headline)
                        .foregroundColor(hasUppercase ? Color.green : Color.text.opacity(0.4))
                }
                .padding(.bottom, 5)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(hasNumberOrSymbol ? Color.green : Color.text.opacity(0.2))
                        .frame(width: 6, height: 6)
                    Text("At least 1 number or symbol")
                        .font(.headline)
                        .foregroundColor(hasNumberOrSymbol ? Color.green : Color.text.opacity(0.4))
                }
                
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 5)
                }
                
                // Create Account button
                Button {
                    Task {
                        let success = await auth.signUp(
                            fullName: name,
                            email: email,
                            password: password
                        )
                        if success {
                            navigateToHome = true
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
                        Text("Create Account")
                            .frame(width: 350, height: 70)
                            .foregroundColor(.surface)
                            .background(Color.gold)
                            .cornerRadius(15)
                    }
                }
                .disabled(!allValid || auth.isLoading)
                .opacity(allValid ? 1.0 : 0.5)
                
                Divider()
                    .background(Color.text)
                    .padding()
                
                // Apple Sign In
                AppleSignInButton(onSuccess: {
                    navigateToHome = true
                })
                .padding(.leading, 70)
                
                VStack(alignment: .center) {
                    Text("Already have an account?")
                        .foregroundColor(.text)
                        .padding(.top, 10)
                    NavigationLink(destination: LogIn()) {
                        Text("Log In")
                            .foregroundColor(.gold)
                    }
                }
                .padding(.leading, 78)
            }
            .padding()
        }
        .navigationDestination(isPresented: $navigateToHome) {
            Home()
        }
    }
}


struct userDetails: View {
    
            var title: String
    @Binding  var userInput: String
    
    var body: some View {
        
        VStack (alignment: .leading){
            Text(title)
                .font(.headline)
                .foregroundColor(Color.text.opacity(0.4))
            
            TextField("Enter your \(title)", text: $userInput)
                .padding(12)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(10)
                .foregroundColor(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gold, lineWidth: 1)
                }
                .textFieldStyle(PlainTextFieldStyle())
                
        }
        
        .padding(5)
    }
}

#Preview {
    SignUp()
}
