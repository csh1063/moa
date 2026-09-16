//
//  PhotoMapClustering.swift
//  Domain
//
//  Created by sanghyeon on 9/9/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 장소 지도의 줌 레벨에 따라 주소를 얼마나 세분화해서 묶을지 결정하는 순수 함수.
/// 줌아웃 상태에서는 국가 단위로 크게, 줌인할수록 시/도 → 시/군/구 → 동까지 점점 촘촘하게
/// 묶는다(동 단위가 최대 — 도로명까지는 안 내려감). 필드별 정제 규칙은 위치 앨범과 동일하게
/// [[AddressGrouping]]을 공유해서, 같은 사진이 지역 앨범과 장소 지도에서 다르게 묶이지 않는다.
/// MKMapView의 실시간 화면거리 클러스터링 대신 이 방식을 쓰는 이유는 [[PhotoMapUseCase]] 참고.
public enum PhotoMapClustering {

    public static func cluster(photos: [Photo], zoomLevel: Double) -> [PhotoMapCluster] {
        var groups: [String: [Photo]] = [:]

        for photo in photos {
            guard let lat = photo.latitude, let lon = photo.longitude else { continue }
            groups[groupKey(for: photo, zoomLevel: zoomLevel, lat: lat, lon: lon), default: []].append(photo)
        }

        return groups.compactMap { key, members in
            let coordinates = members.compactMap { photo -> (Double, Double)? in
                guard let lat = photo.latitude, let lon = photo.longitude else { return nil }
                return (lat, lon)
            }
            guard !coordinates.isEmpty else { return nil }

            let avgLat = coordinates.reduce(0) { $0 + $1.0 } / Double(coordinates.count)
            let avgLon = coordinates.reduce(0) { $0 + $1.1 } / Double(coordinates.count)

            return PhotoMapCluster(
                id: key,
                latitude: avgLat,
                longitude: avgLon,
                photos: members.sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    /// 줌 레벨 버킷이 바뀌었는지만 저렴하게 비교하려고 쓰는 정수 티어. 버킷 경계는 groupKey와 동일.
    public static func tier(for zoomLevel: Double) -> Int {
        if zoomLevel <= 6 { return 1 }
        if zoomLevel <= 8 { return 2 }
        if zoomLevel <= 10 { return 3 }
        return 4  // 10 초과 전부 — 동/읍/면(subLocality) 단위가 최대 세분화
    }

    private static func groupKey(for photo: Photo, zoomLevel: Double, lat: Double, lon: Double) -> String {
        guard let address = photo.address, let components = AddressGrouping.cleanedComponents(for: address) else {
            // 아직 역지오코딩이 안 된 사진(좌표는 있는데 주소가 없는 경우) — 좌표를 대략적인
            // 격자(약 1km 단위)로 묶어서 따로따로 핀이 뜨는 걸 막는다
            return "geo_\(Int((lat * 100).rounded()))_\(Int((lon * 100).rounded()))"
        }

        let parts: [String?]
        switch tier(for: zoomLevel) {
        case 1:
            parts = [components.country]
        case 2:
            parts = [components.country, components.administrativeArea]
        case 3:
            parts = [components.country, components.administrativeArea, components.locality]
        default:
            parts = [components.country, components.administrativeArea, components.locality, components.subLocality]
        }

        let key = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "_")
        return key.isEmpty ? "geo_\(Int((lat * 100).rounded()))_\(Int((lon * 100).rounded()))" : key
    }
}
