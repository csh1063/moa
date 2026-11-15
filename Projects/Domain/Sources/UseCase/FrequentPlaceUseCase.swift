//
//  FrequentPlaceUseCase.swift
//  Domain
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 설정 > 정리 옵션 > "자주가는 동네" — 여행 판정에서 빼는 동네(홈존)를 보고, 직접 추가하고, 지운다
public protocol FrequentPlaceUseCase {
    /// 자동 측정 + 직접 추가 동네. 이 기능 전에 측정돼 주소가 비어있는 자동 동네는 가장 가까운 사진 주소로 채운다
    func fetchPlaces() async throws -> [HomeZone]
    func placeCount() throws -> Int
    func addPlace(latitude: Double, longitude: Double, title: String, address: String?) throws
    /// 자동 동네를 수정하면 재측정 때 덮어써지지 않게 직접 추가 동네로 바뀐다
    func updatePlace(id: UUID, latitude: Double, longitude: Double, title: String, address: String?) throws
    func deletePlace(id: UUID) throws
    /// 추가 화면 지도의 시작 위치 — 좌표 있는 가장 최근 사진(위치 권한 없이 쓰려고), 없으면 nil
    func lastPhotoLocation() throws -> (latitude: Double, longitude: Double)?
}

public final class DefaultFrequentPlaceUseCase: FrequentPlaceUseCase {

    private let homeZoneRepository: HomeZoneRepository
    private let photoDataRepository: PhotoDataRepository

    public init(homeZoneRepository: HomeZoneRepository, photoDataRepository: PhotoDataRepository) {
        self.homeZoneRepository = homeZoneRepository
        self.photoDataRepository = photoDataRepository
    }

    public func fetchPlaces() async throws -> [HomeZone] {
        let zones = try homeZoneRepository.fetchHomeZones()
        guard zones.contains(where: { $0.address == nil }) else { return zones }

        let photos = try photoDataRepository.fetchHasCoordinators().map { PhotoLocationSnapshot(from: $0) }
        let filled = zones.map { zone in
            guard zone.address == nil else { return zone }
            var filled = zone
            filled.address = zone.nearestShortAddress(in: photos)
            return filled
        }
        // 사진 전체 스캔은 한 번만 — 찾은 주소를 저장해 다음부터 바로 뜨게
        if filled.contains(where: { !$0.isManual && $0.address != nil }) {
            try homeZoneRepository.replaceAutoHomeZones(filled.filter { !$0.isManual })
        }
        return filled
    }

    public func placeCount() throws -> Int {
        try homeZoneRepository.fetchHomeZones().count
    }

    public func addPlace(latitude: Double, longitude: Double, title: String, address: String?) throws {
        try homeZoneRepository.addManualHomeZone(HomeZone(
            latitude: latitude,
            longitude: longitude,
            analyzedAt: Date(),
            isManual: true,
            title: title,
            address: address
        ))
    }

    public func updatePlace(id: UUID, latitude: Double, longitude: Double, title: String, address: String?) throws {
        try homeZoneRepository.updateHomeZone(HomeZone(
            id: id,
            latitude: latitude,
            longitude: longitude,
            analyzedAt: Date(),
            isManual: true,
            title: title,
            address: address
        ))
    }

    public func deletePlace(id: UUID) throws {
        try homeZoneRepository.deleteHomeZone(id: id)
    }

    public func lastPhotoLocation() throws -> (latitude: Double, longitude: Double)? {
        guard let photo = try photoDataRepository.fetchLatestLocated(),
              let latitude = photo.latitude, let longitude = photo.longitude else { return nil }
        return (latitude, longitude)
    }
}
