//
//  AppVersionCheckUseCase.swift
//  Domain
//
//  Created by sanghyeon on 8/3/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol AppVersionCheckUseCase {
    func check() async -> AppVersionStatus
}

public final class DefaultAppVersionCheckUseCase: AppVersionCheckUseCase {

    private let repository: RemoteConfigRepository
    private let currentVersion: String

    public init(repository: RemoteConfigRepository,
                currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") {
        self.repository = repository
        self.currentVersion = currentVersion
    }

    public func check() async -> AppVersionStatus {
        guard let policy = await fetchPolicyWithTimeout() else {
            return .upToDate
        }

        if isCurrentVersion(lowerThan: policy.minVersion) {
            return .forceUpdate
        }
        if isCurrentVersion(lowerThan: policy.recommendVersion) {
            return .recommendUpdate
        }
        return .upToDate
    }

    // 토큰 발급 콜백은 취소를 따르지 않아서, 스플래시가 멈추지 않게 타임아웃과 경합시켜 먼저 끝난 쪽으로 리턴한다
    private func fetchPolicyWithTimeout(seconds: UInt64 = 20) async -> AppVersionPolicy? {
        await withCheckedContinuation { continuation in
            let resumeGuard = ResumeGuard()

            Task {
                let value = try? await self.repository.fetchVersionPolicy()
                await resumeGuard.resumeOnce { continuation.resume(returning: value) }
            }

            Task {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                await resumeGuard.resumeOnce { continuation.resume(returning: nil) }
            }
        }
    }

    private func isCurrentVersion(lowerThan other: String) -> Bool {
        guard !other.isEmpty, !currentVersion.isEmpty else { return false }
        return currentVersion.compare(other, options: .numeric) == .orderedAscending
    }
}

private actor ResumeGuard {
    private var didResume = false

    func resumeOnce(_ action: () -> Void) {
        guard !didResume else { return }
        didResume = true
        action()
    }
}
