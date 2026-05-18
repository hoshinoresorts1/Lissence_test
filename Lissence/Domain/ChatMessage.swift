/// Detection mode conversation models.

import Foundation

enum ConversationMode: String, CaseIterable, Identifiable {
    case subtitle = "자막 보기"
    case chat = "대화하기"

    var id: String { rawValue }
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let sender: Sender
    var wasSpoken: Bool = false
    let timestamp: Date = Date()

    enum Sender {
        case partner
        case me
    }
}

struct QuickPhrase: Identifiable {
    let id = UUID()
    let text: String

    static let defaults: [QuickPhrase] = [
        .init(text: "저는 청각장애인입니다."),
        .init(text: "잠시만요"),
        .init(text: "다시 말씀해 주세요"),
        .init(text: "천천히 말씀해 주세요"),
        .init(text: "화면을 보고 말씀해 주세요"),
        .init(text: "감사합니다")
    ]
}
