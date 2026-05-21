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
    private let repeatWindowSeconds: TimeInterval = 5.0
    private let candidateContextSeconds: TimeInterval = 3.0
    private let partialOverlapDedupeWindowSeconds: TimeInterval = 1.0

    private var candidateTimestamps: [Date] = []
    private var lastCandidateOccurrenceCount = 0
    private var lastCandidateDetectedAt: Date?
    private var lastCountedCandidateAt: Date?
    private var lastCountedCandidateSegment = ""

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
        let normalizedTranscript = normalizeForCandidateMatching(trimmedTranscript)
        let candidateOccurrenceCount = countOccurrences(in: normalizedTranscript, keywords: candidateKeywords)
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
            lastCandidateDetectedAt = now
            countCandidateIfNeeded(
                count: newCandidateCount,
                normalizedSegment: normalizedTranscript,
                now: now
            )
        }

        candidateTimestamps.removeAll { now.timeIntervalSince($0) > repeatWindowSeconds }

        let hasCurrentCandidate = candidateOccurrenceCount > 0
        let hasRecentCandidate = lastCandidateDetectedAt.map { now.timeIntervalSince($0) <= candidateContextSeconds } ?? false
        let repeatCount = candidateTimestamps.filter { now.timeIntervalSince($0) <= repeatWindowSeconds }.count
        debugRepeatWindow(repeatCount: repeatCount)
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
        lastCountedCandidateAt = nil
        lastCountedCandidateSegment = ""
    }

    private func normalizeForCandidateMatching(_ text: String) -> String {
        text.filter { !$0.isWhitespace && !$0.isNewline }
    }

    private func countOccurrences(in text: String, keywords: [String]) -> Int {
        keywords.reduce(0) { count, keyword in
            count + text.components(separatedBy: keyword).count - 1
        }
    }

    private func countCandidateIfNeeded(count: Int, normalizedSegment: String, now: Date) {
        guard count > 0 else {
            return
        }

        if count >= 2 {
            debugDirectRepeatedPhrase(count: count)
            appendCountedCandidates(count: count, normalizedSegment: normalizedSegment, now: now)
            debugCandidateCounted(reason: "direct repeated phrase", count: count)
            return
        }

        if shouldDedupAsOverlapPartial(normalizedSegment: normalizedSegment, now: now) {
            debugCandidateDedupe(reason: "deduped overlap partial only after direct phrase check")
            return
        }

        appendCountedCandidates(count: count, normalizedSegment: normalizedSegment, now: now)
        debugCandidateCounted(reason: "new utterance", count: count)
    }

    private func appendCountedCandidates(count: Int, normalizedSegment: String, now: Date) {
        candidateTimestamps.append(contentsOf: Array(repeating: now, count: count))
        lastCountedCandidateAt = now
        lastCountedCandidateSegment = normalizedSegment
    }

    private func shouldDedupAsOverlapPartial(normalizedSegment: String, now: Date) -> Bool {
        guard let lastCountedCandidateAt,
              now.timeIntervalSince(lastCountedCandidateAt) <= partialOverlapDedupeWindowSeconds,
              !lastCountedCandidateSegment.isEmpty,
              normalizedSegment != lastCountedCandidateSegment else {
            return false
        }

        if normalizedSegment.hasPrefix(lastCountedCandidateSegment) ||
            lastCountedCandidateSegment.hasPrefix(normalizedSegment) {
            return true
        }

        return maxSuffixPrefixOverlapLength(lastCountedCandidateSegment, normalizedSegment) >= 2 ||
            maxSuffixPrefixOverlapLength(normalizedSegment, lastCountedCandidateSegment) >= 2
    }

    private func maxSuffixPrefixOverlapLength(_ left: String, _ right: String) -> Int {
        let maxLength = min(left.count, right.count)
        guard maxLength > 0 else {
            return 0
        }

        for length in stride(from: maxLength, through: 1, by: -1) {
            if left.suffix(length) == right.prefix(length) {
                return length
            }
        }

        return 0
    }

    private func debugCandidateCounted(reason: String, count: Int) {
        #if DEBUG
        print("[AttentionCall] candidate counted reason=\(reason), occurrenceCount=\(count)")
        #endif
    }

    private func debugDirectRepeatedPhrase(count: Int) {
        #if DEBUG
        print("[AttentionCall] direct repeated phrase occurrenceCount=\(count)")
        #endif
    }

    private func debugCandidateDedupe(reason: String) {
        #if DEBUG
        print("[AttentionCall] candidate \(reason)")
        #endif
    }

    private func debugRepeatWindow(repeatCount: Int) {
        #if DEBUG
        print("[AttentionCall] repeatWindow=\(String(format: "%.1f", repeatWindowSeconds))s, countedCandidates=\(repeatCount)")
        #endif
    }

    private func debugLog(_ analysis: AttentionCallAnalysis) {
        #if DEBUG
        print(
            "[AttentionCall] transcript=\(analysis.transcript), candidate=\(analysis.candidateDetected), recentCandidate=\(analysis.recentCandidateDetected), occurrenceCount=\(countOccurrences(in: normalizeForCandidateMatching(analysis.transcript), keywords: candidateKeywords)), repeatCount=\(analysis.repeatCount), emergency=\(analysis.emergencyKeywordDetected), score=\(analysis.score), alertLevel=\(analysis.alertLevel.rawValue)"
        )
        #endif
    }
}
