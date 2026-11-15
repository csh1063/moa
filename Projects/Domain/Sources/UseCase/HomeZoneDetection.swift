//
//  HomeZoneDetection.swift
//  Domain
//
//  Created by sanghyeon on 10/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import CoreLocation
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

    /// 여객기 순항 속도(900km/h) — 실제 평균(유럽 우회 노선 610km/h, 오클랜드 직항 830km/h)보다 빠르게 잡아 "못 다녀왔다" 판정을 엄격하게
    static let fastestTravelSpeed: Double = 900_000 / 3600  // m/s
    /// 이 거리를 넘으면 비행기 말고는 갈 방법이 없다고 보고 공항 시간을 더한다 — 더 가까우면 기차/차로 갈 수 있어 안 더한다
    static let flightOnlyDistance: Double = 1_000_000  // m
    /// 탑승 전 수속 + 내려서 입국/짐 — 실제로는 3시간 넘게 걸리지만 엄격하게 2시간
    static let airportTime: TimeInterval = 2 * 3600

    /// 한 구간을 이동하는 데 걸리는 가장 짧은 시간
    static func fastestTravelTime(meters: Double) -> TimeInterval {
        meters / fastestTravelSpeed + (meters > flightOnlyDistance ? airportTime : 0)
    }

    /// from에서 to로 가는 gap 사이에 어떤 홈존이든 들렀다 오는 게 불가능했는지.
    /// 해외에서 나라를 넘어갈 때 쪼개진 여행을 하나로 합치는 데 쓴다 — 홈존이 없으면 판단할 수 없어 false
    public static func couldNotVisitHome(
        from: (latitude: Double, longitude: Double),
        to: (latitude: Double, longitude: Double),
        gap: TimeInterval,
        homeZones: [HomeZone]
    ) -> Bool {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let shortestDetour = homeZones.map { zone -> TimeInterval in
            let home = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            return fastestTravelTime(meters: fromLocation.distance(from: home))
                + fastestTravelTime(meters: home.distance(from: toLocation))
        }.min()
        guard let shortestDetour else { return false }
        return gap < shortestDetour
    }
}
