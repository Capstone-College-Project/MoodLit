//
//  CodeBox.swift
//  MoodLit
//
//  Created by Anthony Chang Martinez on 3/27/26.
//

import SwiftUI

struct CodeBox: View {
    @Binding var text: String
    let isFocused: Bool
    let hasError: Bool
    let onTap: () -> Void
    
    var body: some View {
        TextField("", text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.custom("Georgia", size: 24).weight(.semibold))
            .foregroundColor(Color.text)
            .frame(width: 48, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        hasError ? Color.red.opacity(0.6) :
                        isFocused ? Color.gold :
                        Color.text.opacity(0.2),
                        lineWidth: isFocused ? 2 : 1.5
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .animation(.easeInOut(duration: 0.2), value: hasError)
            .onTapGesture(perform: onTap)
    }
}
