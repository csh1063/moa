//
//  HomeZone.swift
//  Domain
//
//  Created by sanghyeon on 5/24/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import CoreLocation
import Foundation

// Domain 모듈
/// 여행 판정에서 빼는 "자주가는 동네" — 자동 측정(최근 사진 좌표) 또는 사용자가 직접 추가한 것
public struct HomeZone {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double
    public let analyzedAt: Date
    /// 직접 추가한 동네는 자동 재측정이 덮어쓰지 않고, 초기화해도 남는다
    public let isManual: Bool
    /// 직접 추가할 때 입력한 이름 — 자동은 nil
    public let title: String?
    /// "시/도 구 동(또는 도로명)"까지의 주소 — 저장 시점에 모르면 nil
    public var address: String?

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        analyzedAt: Date,
        isManual: Bool = false,
        title: String? = nil,
        address: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.analyzedAt = analyzedAt
        self.isManual = isManual
        self.title = title
        self.address = address
    }
}

public extension HomeZone {
    // 홈존 위경도 기준으로 가장 가까운 사진의 주소를 찾아 사람이 알아볼 수 있는 문자열로 변환
    func addressDescription(in photos: [PhotoLocationSnapshot]) -> String {
        let zoneLocation = CLLocation(latitude: latitude, longitude: longitude)
        guard let nearest = photos
            .filter({ $0.latitude != 0 || $0.longitude != 0 })
            .min(by: {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: zoneLocation)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: zoneLocation)
            })
        else {
            return "주소 확인 불가 (lat: \(latitude), lng: \(longitude))"
        }

        let components = [nearest.country, nearest.administrativeArea, nearest.locality, nearest.subLocality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }

        return components.isEmpty ? "주소 확인 불가 (lat: \(latitude), lng: \(longitude))" : components.joined(separator: ", ")
    }

    /// 가장 가까운 사진의 주소를 동/도로명까지 — 자동 측정 동네의 표시용 주소
    func nearestShortAddress(in photos: [PhotoLocationSnapshot]) -> String? {
        let zoneLocation = CLLocation(latitude: latitude, longitude: longitude)
        guard let nearest = photos
            .filter({ ($0.latitude != 0 || $0.longitude != 0) && $0.administrativeArea != nil })
            .min(by: {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: zoneLocation)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: zoneLocation)
            })
        else { return nil }
        return Self.shortAddress([nearest.administrativeArea, nearest.locality, nearest.subLocality, nearest.thoroughfare])
    }

    /// 한국 주소는 subLocality=구, thoroughfare=동/도로명 — 시/도(중복 제거) 구 동까지만 이어붙인다
    static func shortAddress(_ parts: [String?]) -> String? {
        let components = parts
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }
}
