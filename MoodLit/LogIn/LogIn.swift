//
//  LogIn.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/27/26.
//

import SwiftUI

struct LogIn: View {
    
    @State var userEmail: String = ""
    @State var userPassword: String = ""
    @State private var navigateToHome: Bool = false
    @ObservedObject var auth = AuthService.shared
    
    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            
            VStack {
                Image(systemName: "books.vertical")
                    .font(Font.largeTitle)
                    .foregroundColor(.gold)
                    .padding(28)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gold.opacity(0.3), lineWidth: 1)
                    )
                
                Text("Welcome Back!")
                    .font(.largeTitle)
                    .foregroundColor(Color.text)
                    .padding()
                
                Text("Pick Where you left off!")
                    .font(.headline)
                    .foregroundColor(Color.text.opacity(0.4))
                    .padding()
                
                VStack {
                    userDetails(title: "Email", userInput: $userEmail)
                    userDetails(title: "Password", userInput: $userPassword)
                    
                    NavigationLink(destination: ForgotPassword()) {
                        Text("Forgot Password?")
                            .foregroundColor(Color.gold)
                            .padding(.leading, 150)
                    }
                }
                .padding()
                
                // Error message
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }
                
                // Log In button
                Button {
                    Task {
                        let success = await auth.logIn(
                            email: userEmail,
                            password: userPassword
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
                        Text("Log In")
                            .frame(width: 350, height: 70)
                            .foregroundColor(.surface)
                            .background(Color.gold)
                            .cornerRadius(15)
                    }
                }
                .disabled(auth.isLoading || userEmail.isEmpty || userPassword.isEmpty)
                .opacity(userEmail.isEmpty || userPassword.isEmpty ? 0.5 : 1.0)
                
                Divider()
                    .background(Color.text)
                    .padding()
                
                // Apple Sign In
                AppleSignInButton(onSuccess: {
                    navigateToHome = true
                })
                .padding(.leading, 30)
            }
        }
        .navigationDestination(isPresented: $navigateToHome) {
            Home()
        }
    }
}
