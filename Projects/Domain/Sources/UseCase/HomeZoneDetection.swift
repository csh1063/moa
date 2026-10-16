//
//  HomeZoneDetection.swift
//  Domain
//
//  Created by sanghyeon on 10/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 최근 사진 좌표로 홈존(자주 머무는 구역)을 고르는 순수 계산 — 여행 판정에서 동네를 빼기 위해 쓴다.
/// AutoAlbumUseCase에서 테스트할 수 있게 분리했다.
public enum HomeZoneDetection {

    static let reanalyzePeriod: TimeInterval = 90 * 24 * 60 * 60  // 3개월
    static let gridSize: Double = 50                               // 0.02도 격자 ≈ 2km
    static let maxHomeZones: Int = 5

    /// 최근 3개월 안에서 같은 격자에 5장 이상, 서로 다른 3주 이상 찍힌 곳을 사진 많은 순으로 최대 5개
    static func zones(from photos: [PhotoLocationSnapshot], now: Date = Date()) -> [HomeZone] {
        let recent = photos.filter { $0.createdAt >= now.addingTimeInterval(-reanalyzePeriod) }

        let grid = Dictionary(grouping: recent) { photo -> String in
            let latKey = (photo.latitude * gridSize).rounded()
            let lngKey = (photo.longitude * gridSize).rounded()
            return "\(latKey),\(lngKey)"
        }

        return grid
            .filter { $0.value.count >= 5 }
            .filter { _, photos in
                let uniqueWeeks = Set(photos.map {
                    Calendar.current.component(.weekOfYear, from: $0.createdAt)
                }).count
                return uniqueWeeks >= 3
            }
            .sorted { $0.value.count > $1.value.count }
            .prefix(maxHomeZones)
            .compactMap { _, photos -> HomeZone? in
                guard let first = photos.first else { return nil }
                return HomeZone(latitude: first.latitude, longitude: first.longitude, analyzedAt: now)
            }
    }
}
