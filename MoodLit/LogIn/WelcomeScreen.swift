//
//  WelcomeScreen.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/25/26.
//Welcome screen for to navigate to log in or Sig Up

import SwiftUI

struct WelcomeScreen: View {
    var body: some View {
        NavigationStack{
            ZStack {
                Color.surface.ignoresSafeArea()
                VStack{
                    
                    Image(systemName:  "books.vertical")
                        .font(Font.largeTitle)
                        .foregroundColor(.gold)
                        .padding(28)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gold.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text("MoodLit")
                        .font(.largeTitle)
                        .foregroundColor(.text)
                        .padding(.top, 20)
                    
                    Text("Fully immerse in the reading experience")
                        .font(.headline)
                        .foregroundColor(Color.yellow.opacity(0.4))
                        .padding(.top, 10)
                    
                    
                    VStack{
                        
                        presentInfo(icon: "book", description: "Read ePubs, and, Webnovels with immersive music")
                            .padding(.bottom,10)
                        
                        presentInfo(icon: "theatermasks", description: "AI powered scene and mood tagging for each page" )
                            .padding(.bottom,10)
                        
                        presentInfo(icon: "book", description: "Create Playlist and tags specefically for each book")
                            .padding(.bottom,10)
                        
                    }
                    .padding(20)
                    
                    NavigationLink(destination: LogIn()) {
                        Text("Log In")
                            .frame(width: 350,height: 70)
                            .foregroundColor(.surface)
                            .background(Color.gold)
                            .cornerRadius(15)
                    }
                    
                    
                    Divider()
                        .background(Color.text)
                        .padding(20)
                    
                    Text("Dont't have an account?")
                        .foregroundColor(.text)
                        .padding(.top, 10)
                    
                    NavigationLink(destination: SignUp()){
                        Text("Sign Up")
                            .foregroundColor(.gold)
                    }
                    
                }
            }
        }

    }
    
    //Helps Present Description of App
    struct presentInfo: View {
        
        let icon: String
        let description: String
        
        var body: some View {
            HStack {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .padding(.trailing,5)

                Text(description)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(15)
            .frame(width: 350)
            .foregroundColor(Color.text)
            .background(Color.yellow.opacity(0.2))
            .cornerRadius(20)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gold, lineWidth: 1)
            }
            
        }
    }
    
    
    
    
    
}

#Preview {
    WelcomeScreen()
}
