//
//  DefaultHomeZoneRepository.swift
//  Data
//
//  Created by sanghyeon on 5/24/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Domain
import SwiftData
import Foundation

public final class DefaultHomeZoneRepository: HomeZoneRepository {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func fetchHomeZones() throws -> [HomeZone] {
        let context = ModelContext(container)
        // 자동 측정분 먼저, 그 안에서는 저장 순서 — 화면의 "여행 제외 지역 N" 번호가 매번 같게
        let descriptor = FetchDescriptor<HomeZoneEntity>(sortBy: [SortDescriptor(\.analyzedAt)])
        let zones = try context.fetch(descriptor).map { $0.toDomain() }
        return zones.filter { !$0.isManual } + zones.filter { $0.isManual }
    }

    public func replaceAutoHomeZones(_ zones: [HomeZone]) throws {
        let context = ModelContext(container)
        try context.delete(model: HomeZoneEntity.self, where: #Predicate { $0.isManual == false })
        for zone in zones {
            context.insert(HomeZoneEntity(
                id: zone.id,
                latitude: zone.latitude,
                longitude: zone.longitude,
                analyzedAt: zone.analyzedAt,
                address: zone.address
            ))
        }
        try context.save()
    }

    public func addManualHomeZone(_ zone: HomeZone) throws {
        let context = ModelContext(container)
        context.insert(HomeZoneEntity(
            id: zone.id,
            latitude: zone.latitude,
            longitude: zone.longitude,
            analyzedAt: zone.analyzedAt,
            isManual: true,
            title: zone.title,
            address: zone.address
        ))
        try context.save()
    }

    public func updateHomeZone(_ zone: HomeZone) throws {
        let context = ModelContext(container)
        let id = zone.id
        var descriptor = FetchDescriptor<HomeZoneEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.latitude = zone.latitude
        entity.longitude = zone.longitude
        entity.isManual = zone.isManual
        entity.title = zone.title
        entity.address = zone.address
        try context.save()
    }

    public func deleteHomeZone(id: UUID) throws {
        let context = ModelContext(container)
        try context.delete(model: HomeZoneEntity.self, where: #Predicate { $0.id == id })
        try context.save()
    }
}
