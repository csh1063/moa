//
//  DefaultPhotoDataRepository.swift
//  Data
//
//  Created by sanghyeon on 3/21/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import SwiftData
import Foundation
import Domain

public final class DefaultPhotoDataRepository: PhotoDataRepository {

    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func savePhoto(photo: Photo) throws {
        let context = ModelContext(container)
        let identifier = photo.localIdentifier
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.localIdentifier == identifier }
        )

        let existing = try context.fetch(fetchDescriptor)
        guard existing.isEmpty else { return }

        let entity = PhotoEntity(
            id: photo.id,
            localIdentifier: photo.localIdentifier,
            createdAt: photo.createdAt,
            latitude: photo.latitude,
            longitude: photo.longitude,
            isoCountryCode: photo.isoCountryCode,
            address: photo.address,
            addressEn: photo.addressEn,
            year: photo.year,
            month: photo.month,
            isVideo: photo.isVideo
        )
        context.insert(entity)
        try context.save()
    }

    // 기존 id를 한 번에 조회하고 하나의 context에 모아 넣은 뒤 일정 개수마다 저장한다
    public func saveAllPhotosBase(_ photos: [Photo]) throws {
        guard !photos.isEmpty else { return }

        let context = ModelContext(container)
        let existingIds = Set(try context.fetch(FetchDescriptor<PhotoEntity>()).map { $0.localIdentifier })

        let batchSize = 500
        var pendingCount = 0

        for photo in photos where !existingIds.contains(photo.localIdentifier) {
            let entity = PhotoEntity(
                id: photo.id,
                localIdentifier: photo.localIdentifier,
                createdAt: photo.createdAt,
                latitude: photo.latitude,
                longitude: photo.longitude,
                isoCountryCode: photo.isoCountryCode,
                address: photo.address,
                addressEn: photo.addressEn,
                year: photo.year,
                month: photo.month,
                isVideo: photo.isVideo
            )
            context.insert(entity)
            pendingCount += 1

            if pendingCount >= batchSize {
                try context.save()
                pendingCount = 0
            }
        }

        if pendingCount > 0 {
            try context.save()
        }
    }

    /// 분석 결과 저장 — 사진이 없으면 만들고 들어온 값만 갱신, 라벨/얼굴/동물 임베딩은 새 값이 있을 때만 통째로 교체
    public func saveAndUpdateLabels(photo: Photo, labels: [PhotoLabel]) async throws {
        try await Task.detached(priority: .high) { [container] in
            let context = ModelContext(container)

            let identifier = photo.localIdentifier
            let fetchDescriptor = FetchDescriptor<PhotoEntity>(
                predicate: #Predicate { $0.localIdentifier == identifier }
            )

            let entity: PhotoEntity
            if let existing = try context.fetch(fetchDescriptor).first {
                entity = existing

                if let latitude = photo.latitude { entity.latitude = latitude }
                if let longitude = photo.longitude { entity.longitude = longitude }
                if let isoCountryCode = photo.isoCountryCode { entity.isoCountryCode = isoCountryCode }
                if let address = photo.address { entity.address = address }
                if let addressEn = photo.addressEn { entity.addressEn = addressEn }
                if let year = photo.year { entity.year = year }
                if let month = photo.month { entity.month = month }
            } else {
                entity = PhotoEntity(
                    id: photo.id,
                    localIdentifier: photo.localIdentifier,
                    createdAt: photo.createdAt,
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                    isoCountryCode: photo.isoCountryCode,
                    address: photo.address,
                    addressEn: photo.addressEn,
                    year: photo.year,
                    month: photo.month,
                    isVideo: photo.isVideo
                )
                context.insert(entity)
            }

            if !labels.isEmpty {
                entity.labels.forEach { context.delete($0) }

                labels.forEach {
                    let labelEntity = PhotoLabelEntity(
                        name: $0.name,
                        confidence: $0.confidence,
                        photo: entity
                    )
                    context.insert(labelEntity)
                }
            }

            let faceEmbeddings = photo.faceEmbedding
            if !photo.faceEmbedding.isEmpty {

                entity.faceEmbeddings.forEach { context.delete($0) }

                faceEmbeddings.forEach {
                    let labelEntity = FaceEmbeddingEntity.from(
                        domain: $0,
                        photo: entity
                    )
                    context.insert(labelEntity)
                }
            }

            let animalEmbeddings = photo.animalEmbedding
            if !photo.animalEmbedding.isEmpty {

                entity.animalEmbeddings.forEach { context.delete($0) }

                animalEmbeddings.forEach {
                    let animalEmbeddingEntity = AnimalEmbeddingEntity.from(
                        domain: $0,
                        photo: entity
                    )
                    context.insert(animalEmbeddingEntity)
                }
            }

            entity.analyzedAt = Date()
            try context.save()
        }.value
    }

    public func fetchPhotos(page: Int = -1, pageSize: Int = 300) throws -> [Photo] {
        let context = ModelContext(container)
        var fetchDescriptor = FetchDescriptor<PhotoEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        if page >= 0 {
            fetchDescriptor.fetchLimit = pageSize
            fetchDescriptor.fetchOffset = page * pageSize
        }

        return try context.fetch(fetchDescriptor).map { $0.toDomain() }
    }

    public func fetchAll(page: Int = -1, pageSize: Int = 50) throws -> [Photo] {

        let context = ModelContext(container)

        var fetchDescriptor = FetchDescriptor<PhotoEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        if page >= 0 {
            fetchDescriptor.fetchLimit = pageSize
            fetchDescriptor.fetchOffset = page * pageSize
        }

        return try context.fetch(fetchDescriptor).map { $0.toDomainAll() }
    }

    public func fetchPhotoCount() throws -> Int {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>()
        return try context.fetchCount(fetchDescriptor)
    }

    public func fetchIds(page: Int, pageSize: Int) throws -> [String] {

        let context = ModelContext(container)

        var fetchDescriptor = FetchDescriptor<PhotoEntity>()

        if page >= 0 {
            fetchDescriptor.fetchLimit = pageSize
            fetchDescriptor.fetchOffset = page * pageSize
        }

        return try context.fetch(fetchDescriptor).map {$0.localIdentifier}
    }

    public func fetchAnalyzed() throws -> [String] {
        let context = ModelContext(container)
        var fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.analyzedAt != nil }
        )
        fetchDescriptor.propertiesToFetch = [\.localIdentifier]
        return try context.fetch(fetchDescriptor).map { $0.localIdentifier }
    }

    public func fetchAnalyzedCount() throws -> Int {
        let context = ModelContext(container)
        return try context.fetchCount(FetchDescriptor<PhotoEntity>(predicate: #Predicate { $0.analyzedAt != nil }))
    }

    public func fetchHasCoordinators() throws -> [Photo] {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.longitude != nil && $0.latitude != nil }
        )
        return try context.fetch(fetchDescriptor).map { $0.toDomain() }
    }

    public func fetchPhoto(localIdentifier: String) throws -> Photo? {
        let context = ModelContext(container)
        var fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.localIdentifier == localIdentifier }
        )
        fetchDescriptor.fetchLimit = 1
        return try context.fetch(fetchDescriptor).first?.toDomain()
    }

    public func fetchLatestLocated() throws -> Photo? {
        let context = ModelContext(container)
        var fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.longitude != nil && $0.latitude != nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        fetchDescriptor.fetchLimit = 1
        return try context.fetch(fetchDescriptor).first?.toDomain()
    }

    public func fetchVideos() throws -> [Photo] {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.isVideo == true }
        )
        return try context.fetch(fetchDescriptor).map { $0.toDomain() }
    }

    public func fetchLocationUnanalyzed() throws -> [Photo] {
        let context = ModelContext(container)
        // 주소 변환이 라벨 분석과 동시에 돌아서, 분석 여부 대신 좌표 유무로 대상을 고른다
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.latitude != nil && $0.isoCountryCode == nil }
        )
        return try context.fetch(fetchDescriptor).map { $0.toDomain() }
    }

    public func fetchSyncPhotoId(byAlbum localIdentifier: UUID) throws -> String? {
        let context = ModelContext(container)
        // 관계 predicate로 조회하면 다른 컨텍스트의 변경이 늦게 반영돼서 앨범을 먼저 찾아 album.photos로 읽는다
        let albumDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == localIdentifier }
        )
        guard let album = try context.fetch(albumDescriptor).first else { return nil }

        // 대표 사진이 앨범에서 없어졌을 때만 다시 고른다(인물 앨범 화질 기준 대표 유지)
        album.repairCoverIfMissing()
        try context.save()
        return album.coverPhotoIdentifier
    }

    public func fetchSyncPhotoCount(byAlbum localIdentifier: UUID) throws -> Int {
        let context = ModelContext(container)
        let albumDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == localIdentifier }
        )
        guard let album = try context.fetch(albumDescriptor).first else { return 0 }

        return album.photos.count
    }

    public func fetchPhotos(from startDate: Date, to endDate: Date) throws -> [Photo] {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.createdAt >= startDate && $0.createdAt <= endDate }
        )
        return try context.fetch(fetchDescriptor).map { $0.toDomain() }
    }

    // 아직 날짜/주소/카테고리 분류를 안 거친 사진 — offset 페이징이라 완료 표시는 순회가 끝난 뒤에
    public func fetchAlbumUnclassified(limit: Int, offset: Int) throws -> [Photo] {
        let context = ModelContext(container)
        var fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.albumsGeneratedAt == nil },
            sortBy: [SortDescriptor(\.localIdentifier)]
        )
        fetchDescriptor.fetchLimit = limit
        fetchDescriptor.fetchOffset = offset
        return try context.fetch(fetchDescriptor).map { $0.toDomainAll() }
    }

    public func fetchAllForClassification(limit: Int, offset: Int) throws -> [Photo] {
        let context = ModelContext(container)
        var fetchDescriptor = FetchDescriptor<PhotoEntity>(
            sortBy: [SortDescriptor(\.localIdentifier)]
        )
        fetchDescriptor.fetchLimit = limit
        fetchDescriptor.fetchOffset = offset
        return try context.fetch(fetchDescriptor).map { $0.toDomainAll() }
    }

    public func markAlbumsGenerated(identifiers: [String]) throws {
        guard !identifiers.isEmpty else { return }
        let context = ModelContext(container)
        let idSet = Set(identifiers)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { idSet.contains($0.localIdentifier) }
        )
        let now = Date()
        for entity in try context.fetch(fetchDescriptor) {
            entity.albumsGeneratedAt = now
        }
        try context.save()
    }

    // 아직 비슷한 사진 비교를 안 거친 사진 전체(시간 윈도우 때문에 페이징 안 함) — 영상 제외
    public func fetchSimilarUnchecked() throws -> [Photo] {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.similarCheckedAt == nil && !$0.isVideo }
        )
        return try context.fetch(fetchDescriptor).map { $0.toDomain() }
    }

    public func markSimilarChecked(identifiers: [String]) throws {
        guard !identifiers.isEmpty else { return }
        let context = ModelContext(container)
        let idSet = Set(identifiers)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { idSet.contains($0.localIdentifier) }
        )
        let now = Date()
        for entity in try context.fetch(fetchDescriptor) {
            entity.similarCheckedAt = now
        }
        try context.save()
    }

    public func deleteBatch(identifiers: [String]) throws {
        guard !identifiers.isEmpty else { return }
        let context = ModelContext(container)
        let idSet = Set(identifiers)
        let fetchDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { idSet.contains($0.localIdentifier) }
        )
        let entities = try context.fetch(fetchDescriptor)
        guard !entities.isEmpty else { return }

        // 영향받는 앨범을 먼저 모아서 앨범당 한 번만 다시 계산한다
        var touchedAlbums: [UUID: AlbumEntity] = [:]
        for entity in entities {
            for album in entity.albums {
                touchedAlbums[album.id] = album
            }
        }

        for entity in entities {
            context.delete(entity)
        }

        for album in touchedAlbums.values {
            album.photos.removeAll { idSet.contains($0.localIdentifier) }
            album.photoCount = album.photos.count
            album.repairCoverIfMissing()
        }

        try context.save()
    }
}
