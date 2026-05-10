/// ESP32 BLE Peripheral과의 최소 통신을 검증하는 iPhone 테스트 화면입니다.

import SwiftUI

/// BLE 스캔, 연결 상태, notify 수신, 테스트 write 액션을 제공하는 화면입니다.
struct BLETestView: View {
    // MARK: - 속성

    /// 앱의 단순 화면 전환 상태입니다.
    @Binding var currentPath: String

    /// BLE 테스트 화면 상태와 액션을 관리하는 ViewModel입니다.
    @StateObject private var viewModel = BLETestViewModel()

    // MARK: - 화면

    var body: some View {
        VStack(spacing: 24) {
            headerView

            ScrollView {
                VStack(spacing: 16) {
                    statusSection
                    micLevelSection
                    audioStreamSection
                    messageSection
                    actionSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Spacer()
        }
        .padding(.top, 20)
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - 하위 뷰

    /// 상단 제목과 홈 이동 버튼입니다.
    private var headerView: some View {
        HStack {
            Button(action: { currentPath = "home" }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("홈으로 이동")

            Spacer()

            Text("BLE 테스트")
                .font(.title2)
                .bold()

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
    }

    /// Bluetooth와 ESP32 연결 상태를 표시하는 영역입니다.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BLEStatusRow(title: "Bluetooth", value: viewModel.bluetoothStateText)
            BLEStatusRow(title: "상태", value: viewModel.statusText)
            BLEStatusRow(title: "장치", value: viewModel.discoveredDeviceName)
            BLEStatusRow(title: "연결", value: viewModel.isConnected ? "연결됨" : "연결 안 됨")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    /// ESP32에서 notify로 받은 최신 INMP441 RMS/Peak 값을 표시하는 영역입니다.
    private var micLevelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("마이크 레벨")
                .font(.headline)

            BLEStatusRow(title: "상태", value: viewModel.micLevelStateText)
            BLEStatusRow(title: "RMS", value: viewModel.latestMicRMSText)
            BLEStatusRow(title: "Peak", value: viewModel.latestMicPeakText)
            BLEStatusRow(title: "Candidate", value: viewModel.latestAudioCandidateKind)
            BLEStatusRow(title: "Candidate RMS", value: viewModel.latestAudioCandidateRMSText)
            BLEStatusRow(title: "Candidate Peak", value: viewModel.latestAudioCandidatePeakText)
            BLEStatusRow(title: "Candidate count", value: "\(viewModel.audioCandidateReceivedCount)")
            BLEStatusRow(title: "Candidate time", value: viewModel.latestAudioCandidateTimeText)
            BLEStatusRow(title: "Triggered analysis", value: viewModel.triggeredAnalysisStateText)
            BLEStatusRow(title: "Trigger window", value: viewModel.triggeredAnalysisWindowSecondsText)
            BLEStatusRow(title: "Trigger request id", value: viewModel.currentTriggeredAnalysisRequestIDText)
            BLEStatusRow(title: "Trigger time", value: viewModel.lastTriggeredAnalysisTimeText)
            BLEStatusRow(title: "Detected danger", value: viewModel.lastTriggeredDangerLabel)
            BLEStatusRow(title: "Danger confidence", value: viewModel.lastTriggeredDangerConfidenceText)
            BLEStatusRow(title: "Analyzer label", value: viewModel.lastTriggeredAnalyzerLabel)
            BLEStatusRow(title: "Analyzer confidence", value: viewModel.lastTriggeredAnalyzerConfidenceText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    /// ESP32 PCM audio stream binary packet 재조립 통계를 표시하는 영역입니다.
    private var audioStreamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Stream")
                .font(.headline)

            BLEStatusRow(title: "상태", value: viewModel.audioStreamingStateText)
            BLEStatusRow(title: "Packets", value: "\(viewModel.audioPacketsReceived)")
            BLEStatusRow(title: "Chunks", value: "\(viewModel.audioChunksReconstructed)")
            BLEStatusRow(title: "Dropped", value: "\(viewModel.audioDroppedChunks)")
            BLEStatusRow(title: "Latest chunk", value: "\(viewModel.latestAudioChunkSize) bytes")
            BLEStatusRow(title: "Latest sequence", value: viewModel.latestAudioSequenceText)
            BLEStatusRow(title: "Sample rate", value: viewModel.bleAudioSampleRateText)
            BLEStatusRow(title: "Ring buffer", value: "\(viewModel.audioRingBufferBytes) bytes")
            BLEStatusRow(title: "Ring duration", value: viewModel.audioRingBufferDurationText)
            BLEStatusRow(title: "Analysis ready", value: viewModel.audioAnalysisReadyText)
            BLEStatusRow(title: "Received audio", value: viewModel.estimatedReceivedAudioText)
            BLEStatusRow(title: "PCM RMS", value: viewModel.pcmRMSText)
            BLEStatusRow(title: "PCM Peak", value: viewModel.pcmPeakText)
            BLEStatusRow(title: "Zero crossing", value: viewModel.pcmZeroCrossingRateText)
            BLEStatusRow(title: "Samples", value: "\(viewModel.pcmSampleCount)")
            BLEStatusRow(title: "BLE analysis", value: viewModel.bleAudioAnalysisStatusText)
            BLEStatusRow(title: "Classification", value: viewModel.bleAudioLastClassification)
            BLEStatusRow(title: "Confidence", value: viewModel.bleAudioConfidenceText)
            BLEStatusRow(title: "Analysis seq", value: viewModel.bleAudioLastAnalysisSequenceText)

            HStack(spacing: 12) {
                Button(action: viewModel.startAudioStream) {
                    Label("Start Audio Stream", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canControlAudioStream)

                Button(action: viewModel.stopAudioStream) {
                    Label("Stop", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canControlAudioStream)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    /// notify 수신 메시지와 최근 write 메시지를 표시하는 영역입니다.
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("메시지")
                .font(.headline)

            BLEStatusRow(title: "수신", value: viewModel.lastReceivedMessage)
            BLEStatusRow(title: "송신", value: viewModel.lastSentMessage)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    /// 스캔, 연결 해제, 테스트 write 버튼 영역입니다.
    private var actionSection: some View {
        VStack(spacing: 12) {
            Button(action: viewModel.startScan) {
                Label("ESP32 스캔 및 연결", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: viewModel.sendWarningHapticCommand) {
                Label("테스트 햅틱 명령 전송", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canSendTestCommand)

            Button(action: viewModel.stop) {
                Label("연결 해제", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - 상태 행

/// BLE 테스트 화면에서 label과 value를 한 줄로 표시하는 재사용 뷰입니다.
private struct BLEStatusRow: View {
    /// 상태 항목 이름입니다.
    let title: String

    /// 상태 항목 값입니다.
    let value: String

    /// 상태 행 화면 구성입니다.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
