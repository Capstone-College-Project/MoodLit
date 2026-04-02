    //
    //  AppleSignInButton.swift
    //  MoodLit
    //
    //  Created by Anthony Chang Martinez on 3/28/26.
    //
    import SwiftUI
    import AuthenticationServices

    struct AppleSignInButton: View {
        
        var onSuccess: () -> Void
        @ObservedObject var auth = AuthService.shared
        
        var body: some View {
            Button {
                startAppleSignIn()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    Text("Sign in with Apple")
                }
                .frame(width: 200, height: 70)
                .foregroundColor(.text)
                .background(Color.surface)
                .cornerRadius(15)
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.text, lineWidth: 1)
                }
            }
        }
        
        private func startAppleSignIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let coordinator = AppleSignInCoordinator(auth: auth, onSuccess: onSuccess)
            
            // Store coordinator so it doesn't get deallocated
            AppleSignInCoordinator.current = coordinator
            
            controller.delegate = coordinator
            controller.performRequests()
        }
    }

    // Handles the Apple Sign In callback
    class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
        
        // Keep a strong reference so ARC doesn't kill it mid-flow
        static var current: AppleSignInCoordinator?
        
        let auth: AuthService
        let onSuccess: () -> Void
        
        init(auth: AuthService, onSuccess: @escaping () -> Void) {
            self.auth = auth
            self.onSuccess = onSuccess
        }
        
        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                print("❌ Apple Sign In: missing token")
                AppleSignInCoordinator.current = nil
                return
            }
            
            // Build full name if provided (only on first sign in)
            var fullName: String? = nil
            if let givenName = credential.fullName?.givenName {
                let familyName = credential.fullName?.familyName ?? ""
                fullName = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespaces)
            }
            
            let email = credential.email  // nil after first sign in
            
            Task { @MainActor in
                let success = await auth.appleLogin(
                    identityToken: identityToken,
                    fullName: fullName,
                    email: email
                )
                if success {
                    onSuccess()
                }
                AppleSignInCoordinator.current = nil
            }
        }
        
        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            print("❌ Apple Sign In error: \(error.localizedDescription)")
            AppleSignInCoordinator.current = nil
        }
    }
