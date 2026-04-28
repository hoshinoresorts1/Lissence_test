/// 공통 데이터 규격(Shared Group)
///

import Foundation

/// 아이폰과 애플워치 간의 통신을 위한 데이터 규격
struct MessageData: Codable {
    let title: String      // 감지된 소리의 이름 (예: "아기 울음소리", "사이렌")
    let iconName: String   // 표시할 시스템 아이콘 이름 (예: "figure.walk")
    let isDanger: Bool     // 위험 소리 여부 (UI 색상 결정용: true면 빨간색)
    
    // 추가적인 정보가 필요할 때를 대비한 옵셔널 필드들
    var transcript: String? // 음성 인식 결과 자막
    var timestamp: Date     // 데이터 생성 시간
    
    // 초기화 함수를 정의하여 사용하기 편하게 만듭니다.
    init(title: String, iconName: String, isDanger: Bool, transcript: String? = nil) {
        self.title = title
        self.iconName = iconName
        self.isDanger = isDanger
        self.transcript = transcript
        self.timestamp = Date()
    }
}
