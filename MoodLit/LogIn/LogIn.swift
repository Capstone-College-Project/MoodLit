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
    @State private var showPassword: Bool = false
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
                    VStack(alignment: .leading) {
                        Text("Email")
                            .font(.headline)
                            .foregroundColor(Color.text.opacity(0.4))
                        
                        TextField("Enter your Email", text: $userEmail)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .onChange(of: userEmail) { _, newValue in
                                let lowered = newValue.lowercased()
                                if lowered != newValue {
                                    userEmail = lowered
                                }
                            }
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
                    
                    // Password field — hidden with toggle
                    VStack(alignment: .leading) {
                        Text("Password")
                            .font(.headline)
                            .foregroundColor(Color.text.opacity(0.4))
                        
                        HStack {
                            if showPassword {
                                TextField("Enter your Password", text: $userPassword)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Enter your Password", text: $userPassword)
                                    .textInputAutocapitalization(.never)
                            }
                            
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundColor(Color.text.opacity(0.4))
                                    .font(.system(size: 14))
                            }
                        }
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
                    
                    NavigationLink(destination: ForgotPassword()) {
                        Text("Forgot Password?")
                            .foregroundColor(Color.gold)
                            .padding(.leading, 150)
                    }
                }
                .padding()
                
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }
                
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
