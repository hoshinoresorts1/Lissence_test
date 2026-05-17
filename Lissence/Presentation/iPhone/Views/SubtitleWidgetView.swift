/// Detection mode subtitle and communication sheet.

import SwiftUI

struct SubtitleWidgetView: View {
    @Binding var isShowing: Bool
    @ObservedObject var viewModel: DetectionViewModel

    @State private var detent: PresentationDetent = .height(350)
    @FocusState private var inputFocused: Bool

    private let bgColor = Color.black
    private let accentYellow = Color(red: 1.00, green: 0.78, blue: 0.00)
    private let accentBlue = Color(red: 0.12, green: 0.42, blue: 1.00)
    private let accentMagenta = Color(red: 0.85, green: 0.27, blue: 0.94)

    var body: some View {
        VStack(spacing: 0) {
            header

            modeToggle
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            switch viewModel.conversationMode {
            case .subtitle:
                subtitleMode
            case .chat:
                chatMode
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor)
        .presentationDetents([.height(350), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: viewModel.conversationMode) { _, newMode in
            if newMode == .chat {
                detent = .large
            }
        }
    }

    private var header: some View {
        HStack {
            Text(viewModel.conversationMode == .subtitle ? "실시간 자막" : "실시간 대화")
                .font(.caption.bold())
                .foregroundColor(accentYellow)

            Spacer()

            Button {
                isShowing = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding([.top, .horizontal], 20)
        .padding(.bottom, 10)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(ConversationMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.conversationMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(viewModel.conversationMode == mode ? accentBlue : Color.clear)
                        .foregroundColor(viewModel.conversationMode == mode ? .white : .white.opacity(0.55))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    private var subtitleMode: some View {
        ScrollView {
            Text(viewModel.transcript.isEmpty ? "소리를 기다리고 있습니다..." : viewModel.transcript)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(viewModel.transcript.isEmpty ? .white.opacity(0.4) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
    }

    private var chatMode: some View {
        VStack(spacing: 0) {
            messageList
            quickPhraseBar
            inputBar
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.messages.isEmpty && viewModel.transcript.isEmpty {
                        Text("소리를 기다리고 있습니다...")
                            .font(.system(size: 17))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 40)
                    }

                    ForEach(viewModel.messages) { message in
                        bubble(for: message, isLive: false)
                            .id(message.id)
                    }

                    if !viewModel.transcript.isEmpty {
                        bubble(
                            for: ChatMessage(text: viewModel.transcript, sender: .partner),
                            isLive: true
                        )
                        .id("live")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.transcript) { _, _ in
                withAnimation {
                    proxy.scrollTo("live", anchor: .bottom)
                }
            }
        }
    }

    private func bubble(for message: ChatMessage, isLive: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.sender == .me {
                Spacer(minLength: 50)
                if message.wasSpoken {
                    Button {
                        viewModel.replay(message)
                    } label: {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }

            Text(message.text)
                .font(.system(size: 17))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.sender == .me ? accentBlue : Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .opacity(isLive ? 0.55 : 1.0)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(accentYellow.opacity(0.6), style: .init(lineWidth: 1, dash: [4]))
                        .opacity(isLive ? 1 : 0)
                )

            if message.sender == .partner {
                Spacer(minLength: 50)
            }
        }
    }

    private var quickPhraseBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.quickPhrases) { phrase in
                    Button {
                        viewModel.sendQuickPhrase(phrase)
                    } label: {
                        Text(phrase.text)
                            .font(.callout)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(
                                Capsule()
                                    .strokeBorder(accentYellow.opacity(0.7), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $viewModel.inputText,
                prompt: Text("말하고 싶은 문장 입력 (최대 \(viewModel.inputCharLimit)자)")
                    .foregroundColor(.white.opacity(0.4)),
                axis: .vertical
            )
            .lineLimit(1...3)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .focused($inputFocused)
            .onChange(of: viewModel.inputText) { _, newValue in
                if newValue.count > viewModel.inputCharLimit {
                    viewModel.inputText = String(newValue.prefix(viewModel.inputCharLimit))
                }
            }

            Button {
                viewModel.sendMyMessage(speak: true)
                inputFocused = false
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(canSend ? accentMagenta : Color.gray.opacity(0.35))
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, 4)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
