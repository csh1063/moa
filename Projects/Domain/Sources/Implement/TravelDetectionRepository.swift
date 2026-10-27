//
//  TravelDetectionRepository.swift
//  Domain
//
//  Created by sanghyeon on 5/6/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

public protocol TravelDetectionRepository {
//    func detect(from photos: [PhotoLocationSnapshot]) async throws -> [TravelCluster]
    /// onProgress: 여행 후보(지오코딩 보충 포함) 하나를 처리할 때마다 0~1
    func detect(from photos: [PhotoLocationSnapshot], homeZones: [HomeZone], onProgress: (Double) -> Void) async throws -> [TravelCluster]
    /// 주어진 사진들로부터 대표 주소/기간을 계산해 하나의 TravelCluster를 만든다 (여행 앨범 합치기에서 재사용)
    func buildCluster(from photos: [PhotoLocationSnapshot]) async throws -> TravelCluster?
}

extension TravelDetectionRepository {
    public func detect(from photos: [PhotoLocationSnapshot], homeZones: [HomeZone]) async throws -> [TravelCluster] {
        try await detect(from: photos, homeZones: homeZones, onProgress: { _ in })
    }
}
