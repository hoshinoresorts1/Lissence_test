/// 감지모드의 화면 코드입니다.
/// **여기에 감지모드 로직은 작성하지 않습니다.**

import SwiftUI

struct DetectionDetailView: View {
    @Binding var currentPath: String
    @StateObject private var viewModel = DetectionViewModel()

    var body: some View {
        VStack(spacing: 0) {
            headerView

            bleIndicatorView

            attentionCallControlView

            Spacer()

            contentView

            Spacer()

            bottomControls
        }
        // 자막창 시트: viewModel의 isVoiceOn 상태에 따라 자동으로 열림
        .sheet(isPresented: $viewModel.isVoiceOn) {
            SubtitleWidgetView(
                isShowing: $viewModel.isVoiceOn,
                viewModel: viewModel
            )
            .interactiveDismissDisabled() // 제스처로 끄기 방지 (버튼으로만 끄게 함)
        }
        .overlay {
            if viewModel.showAttentionPrompt {
                attentionPromptOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showAttentionPrompt)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }
}

// MARK: - UI Components (Extensions)
extension DetectionDetailView {

    // 1. 헤더: 홈 버튼 및 음성 인식 토글
    private var headerView: some View {
        HStack {
            Button(action: { currentPath = "home" }) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // 토글 버튼: 클릭 시 ViewModel의 오디오 세션 제어 로직 실행
            Button(action: { viewModel.toggleVoiceMode() }) {
                HStack {
                    Image(systemName: viewModel.isVoiceOn ? "mic.fill" : "mic.slash")
                    Text(viewModel.isVoiceOn ? "음성 인식 중" : "음성 인식")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(viewModel.isVoiceOn ? Color.red : Color.gray.opacity(0.2))
                .foregroundColor(viewModel.isVoiceOn ? .white : .primary)
                .cornerRadius(20)
            }
        }
        .padding()
    }

    // 1-1. BLE 연결 상태 인디케이터 (헤더 바로 아래에 한 줄)
    private var bleIndicatorView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isBLEConnected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            Text(viewModel.isBLEConnected
                 ? "ESP32 연결됨 (\(viewModel.bleDeviceName))"
                 : "ESP32 미연결")
                .font(.footnote)
                .foregroundColor(viewModel.isBLEConnected ? .green : .secondary)

            Spacer()

            Text(viewModel.bleStatusText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(
            (viewModel.isBLEConnected ? Color.green : Color.gray)
                .opacity(0.08)
        )
        .cornerRadius(8)
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBLEConnected)
    }

    private var attentionCallControlView: some View {
        HStack(spacing: 8) {
            attentionToggleItem(
                title: "1회호출",
                isOn: $viewModel.isSingleCallAlertEnabled,
                tint: .blue
            )

            attentionToggleItem(
                title: "반복호출",
                isOn: $viewModel.isRepeatedCallAlertEnabled,
                tint: .blue
            )

            attentionToggleItem(
                title: "긴급호출",
                isOn: $viewModel.isEmergencyCallAlertEnabled,
                tint: .red
            )
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSingleCallAlertEnabled)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRepeatedCallAlertEnabled)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEmergencyCallAlertEnabled)
    }

    private func attentionToggleItem(
        title: String,
        isOn: Binding<Bool>,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(tint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .padding(.horizontal, 6)
        .background(tint.opacity(isOn.wrappedValue ? 0.10 : 0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(isOn.wrappedValue ? 0.28 : 0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // 2. 메인 컨텐츠: 소리 감지 결과 표시
    private var contentView: some View {
        VStack {
            if viewModel.lastDetectedSound.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    Text("주변 소리 분석 중...")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: viewModel.currentSoundIcon)
                        .font(.system(size: 100))
                        .foregroundColor(viewModel.isDanger ? .red : .blue)

                    Text(viewModel.lastDetectedSound)
                        .font(.system(size: 32, weight: .bold))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(), value: viewModel.lastDetectedSound)
    }

    // 3. 하단 컨트롤: 모드 전환 버튼
    private var bottomControls: some View {
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

    private var attentionPromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.blue)

                Text(viewModel.attentionPromptMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        viewModel.dismissAttentionPrompt()
                    } label: {
                        Text("아니오")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.gray.opacity(0.16))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        viewModel.acceptAttentionPrompt()
                    } label: {
                        Text("네")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .padding(.horizontal, 28)
        }
    }
}
