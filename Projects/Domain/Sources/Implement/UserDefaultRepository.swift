//
//  UserDefaultRepository.swift
//  Domain
//
//  Created by sanghyeon on 5/1/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol UserDefaultRepository {
    func saveAnalyzedDate() async throws
    func fetchAnalyzedDate() async throws -> String
    func resetAnalyzedDate() async throws
    func saveLocationAnalyzedDate() async throws
    func fetchLocationAnalyzedDate() async throws -> String
    func saveDisplayMode(_ mode: String) async throws
    func fetchDisplayMode() async throws -> String
    func saveAutoNewAnalysis(isOn: Bool) async throws
    func fetchAutoNewAnalysis() async throws -> Bool?
    func saveOnboarding(isShown: Bool) async throws
    func showOnboarding() async throws -> Bool
    func saveConsent(isShown: Bool) async throws
    func showConsent() async throws -> Bool

    /// 이 기기에서 분석이 사진 한 장당 걸린 시간(초) — 아직 잰 적 없으면 nil
    func fetchAnalysisSecondsPerPhoto() async throws -> Double?
    func saveAnalysisSecondsPerPhoto(_ seconds: Double) async throws
    /// 여행 재계산(삭제 → 재클러스터링 → 재저장) 직전에 기록 — anchorDate까지는 확정된 상태(nil이면 처음부터)
    /// 성공하면 clear로 지우고, 도중에 죽으면 남아 있어서 다음 실행이 이 기준으로 다시 만든다
    func beginTravelAlbumCheckpoint(anchorDate: Date?) async throws
    func clearTravelAlbumCheckpoint() async throws
    /// nil이면 체크포인트 없음(지난 실행이 정상 종료됨)
    func fetchTravelAlbumCheckpoint() async throws -> TravelAlbumCheckpoint?
}

public struct TravelAlbumCheckpoint {
    public let anchorDate: Date?

    public init(anchorDate: Date?) {
        self.anchorDate = anchorDate
    }
}
