//
//  Home.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/8/26.
//

import SwiftUI

struct Home: View {
    var body: some View {
        NavigationStack{
            ZStack{
                Color.bg
                    .ignoresSafeArea()
                
                VStack{
                    Text("Home")
                        .font(.largeTitle)
                        .foregroundColor(Color.text)
                    
                    Spacer()
                    
                    NavigationLink("Library"){
                        Library()
                    }
                    .font(.headline)
                    .foregroundColor(Color.text2)
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.text2, lineWidth: 2)
                    )
                    .padding()
                    
                    NavigationLink("PlayList"){
                        PlaylistListView()
                    }
                    .font(.headline)
                    .foregroundColor(Color.text2)
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.text2, lineWidth: 2)
                    )
                    
                    Spacer()
                    
                }
            }
        }
    }
}

#Preview {
    Home()
}
