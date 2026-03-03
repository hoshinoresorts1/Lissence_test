//
//  DetectionDetailView.swift
//  Lissence
//
//  Created by 서유정 on 2/17/26.
//

import SwiftUI

struct DetectionDetailView: View {
    @Binding var currentPath: String
    @State private var isVoiceOn = false

    var body: some View {
        VStack(spacing: 0) {
            // 상단바 (홈버튼 & 토글)
            HStack {
                Button(action: { currentPath = "home" }) {
                    Image(systemName: "house.fill").font(.title2).foregroundColor(.gray)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Toggle("음성인식", isOn: $isVoiceOn)
                    .toggleStyle(.button).tint(.orange)
            }.padding(.horizontal)
            .frame(height: 60)
            
            .overlay {
                Text("감지 모드")
                    .font(.system(size: 40, weight: .bold))
                    .offset(y:130)
            }
            
            Spacer()
        
            VStack(spacing: 25) {
                Image(systemName: "waveform")
                    .font(.system(size: 90))
                    .foregroundColor(.blue)
                
                Text("소리 분석 중..")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            Spacer()

            // 하단 전환 버튼
            Button(action: { currentPath = "music" }) {
                Label("음악모드 전환", systemImage: "music.quarternote.3")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(15)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
        
        // 자막창
        .sheet(isPresented: $isVoiceOn) {
            SubtitleWidgetView(isShowing: $isVoiceOn, text: "실시간 대화 내용입니다...")
                .interactiveDismissDisabled() // 맘대로 끌어내려 닫기 방지
        }
    }
}
