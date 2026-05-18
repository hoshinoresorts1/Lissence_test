/// 감지모드에서 "저기요" 기반 호출어 후보를 조건 기반 알림으로 변환합니다.

import Foundation

/// 호출어 분석 결과의 알림 단계입니다.
enum AttentionAlertLevel: String {
    case none
    case displayOnly
    case softAlert
    case strongAlert
}

/// 호출어 분석 결과입니다.
struct AttentionCallAnalysis {
    let transcript: String
    let candidateDetected: Bool
    let recentCandidateDetected: Bool
    let repeatCount: Int
    let emergencyKeywordDetected: Bool
    let score: Int
    let alertLevel: AttentionAlertLevel
}

/// Speech transcript를 입력받아 호출어 후보, 반복, 긴급 단어 조건을 평가합니다.
final class AttentionCallAnalyzer {
    private let candidateKeywords = ["저기요", "안녕하세요"]
    private let emergencyKeywords = ["조심", "위험", "비켜요", "차", "뒤에", "피해요", "멈춰요", "조심하세요"]
    private let repeatWindowSeconds: TimeInterval = 2.0
    private let candidateContextSeconds: TimeInterval = 3.0

    private var candidateTimestamps: [Date] = []
    private var lastCandidateOccurrenceCount = 0
    private var lastCandidateDetectedAt: Date?

    /// 누적 transcript를 분석해 호출어 알림 단계를 반환합니다.
    func analyze(transcript: String, now: Date = Date()) -> AttentionCallAnalysis {
        analyze(transcript: transcript, now: now, treatsTranscriptAsNewSegment: false)
    }

    /// 새로 추가된 발화 조각을 분석해 호출어 알림 단계를 반환합니다.
    func analyzeSegment(transcript: String, now: Date = Date()) -> AttentionCallAnalysis {
        analyze(transcript: transcript, now: now, treatsTranscriptAsNewSegment: true)
    }

    private func analyze(
        transcript: String,
        now: Date = Date(),
        treatsTranscriptAsNewSegment: Bool
    ) -> AttentionCallAnalysis {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateOccurrenceCount = countOccurrences(in: trimmedTranscript, keywords: candidateKeywords)
        let newCandidateCount: Int

        if treatsTranscriptAsNewSegment {
            newCandidateCount = candidateOccurrenceCount
        } else {
            newCandidateCount = max(candidateOccurrenceCount - lastCandidateOccurrenceCount, 0)
        }

        if !treatsTranscriptAsNewSegment {
            if candidateOccurrenceCount < lastCandidateOccurrenceCount || trimmedTranscript.isEmpty {
                lastCandidateOccurrenceCount = candidateOccurrenceCount
            } else {
                lastCandidateOccurrenceCount = max(lastCandidateOccurrenceCount, candidateOccurrenceCount)
            }
        }

        if newCandidateCount > 0 {
            candidateTimestamps.append(contentsOf: Array(repeating: now, count: newCandidateCount))
            lastCandidateDetectedAt = now
        }

        candidateTimestamps.removeAll { now.timeIntervalSince($0) > candidateContextSeconds }

        let hasCurrentCandidate = candidateOccurrenceCount > 0
        let hasRecentCandidate = lastCandidateDetectedAt.map { now.timeIntervalSince($0) <= candidateContextSeconds } ?? false
        let repeatCount = candidateTimestamps.filter { now.timeIntervalSince($0) <= repeatWindowSeconds }.count
        let hasCandidateContext = hasCurrentCandidate || hasRecentCandidate
        let emergencyDetected = hasCandidateContext && emergencyKeywords.contains { trimmedTranscript.contains($0) }

        var score = 0
        if hasCurrentCandidate || emergencyDetected {
            score += 1
        }
        if repeatCount >= 2 {
            score += 2
        }
        if emergencyDetected {
            score += 4
        }

        // TODO: RMS/Peak 조건을 감지모드 오디오 레벨로 안정적으로 노출한 뒤 score에 반영합니다.
        // TODO: 거리 변화 조건은 마이크 amplitude trend 신뢰도 검증 후 별도 옵션으로 추가합니다.

        let alertLevel: AttentionAlertLevel
        if !hasCurrentCandidate && !emergencyDetected {
            alertLevel = .none
        } else if emergencyDetected || score >= 6 {
            alertLevel = .strongAlert
        } else if score >= 3 {
            alertLevel = .softAlert
        } else {
            alertLevel = .displayOnly
        }

        let analysis = AttentionCallAnalysis(
            transcript: trimmedTranscript,
            candidateDetected: hasCandidateContext,
            recentCandidateDetected: hasRecentCandidate,
            repeatCount: repeatCount,
            emergencyKeywordDetected: emergencyDetected,
            score: score,
            alertLevel: alertLevel
        )

        debugLog(analysis)
        return analysis
    }

    /// 분석 상태를 초기화합니다.
    func reset() {
        candidateTimestamps.removeAll()
        lastCandidateOccurrenceCount = 0
        lastCandidateDetectedAt = nil
    }

    private func countOccurrences(in text: String, keywords: [String]) -> Int {
        keywords.reduce(0) { count, keyword in
            count + text.components(separatedBy: keyword).count - 1
        }
    }

    private func debugLog(_ analysis: AttentionCallAnalysis) {
        #if DEBUG
        print(
            "[AttentionCall] transcript=\(analysis.transcript), candidate=\(analysis.candidateDetected), recentCandidate=\(analysis.recentCandidateDetected), repeatCount=\(analysis.repeatCount), emergency=\(analysis.emergencyKeywordDetected), score=\(analysis.score), alertLevel=\(analysis.alertLevel.rawValue)"
        )
        #endif
    }
}
