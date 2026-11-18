//
//  DefaultAlbumDataRepository.swift
//  Data
//
//  Created by sanghyeon on 3/21/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import SwiftData
import Domain
import Combine
import SQLite3

public final class DefaultAlbumDataRepository: AlbumDataRepository {

    private let container: ModelContainer

    private let albumsSubject = CurrentValueSubject<[Album], Never>([])
    public var albumsPublisher: AnyPublisher<[Album], Never> {
        albumsSubject.eraseToAnyPublisher()
    }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func saveAlbum(album: Album, returnExist: Bool = false) throws -> Album? {

        let context = ModelContext(container)

        let name = album.name
        let from = album.from
        let fetchDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.name == name && $0.from == from }
        )

        let existing = try context.fetch(fetchDescriptor)
        guard existing.isEmpty else { return returnExist ? existing.first?.toDomain():nil }

        let entity = AlbumEntity(
            id: album.id,
            name: album.name,
            displayName: album.displayName,
            startDate: album.startDate,
            endDate: album.endDate,
            isAuto: album.isAuto,
            coverPhotoIdentifier: album.coverPhotoIdentifier,
            from: album.from
        )
        context.insert(entity)

        album.keywords.forEach {
            let keywordEntity = AlbumKeywordEntity(
                keyword: $0,
                weight: 1.0,
                album: entity
            )
            context.insert(keywordEntity)
        }

        try context.save()
        return album
    }

    public func fetchAll() throws -> [Album] {

        let context = ModelContext(container)

        let fetchDescriptor = FetchDescriptor<AlbumEntity>(
//            predicate: #Predicate{$0.from == "travel"},
            sortBy: [
//                SortDescriptor(\.from, order: .forward),
                SortDescriptor(\.photoCount, order: .reverse),
                SortDescriptor(\.displayName, order: .forward)
            ]
        )
        // 비슷한 사진 앨범만 커버 스택용으로 사진까지 읽는다
        return try context.fetch(fetchDescriptor).map {
            $0.from == "similar" ? $0.toDomainWithPhoto() : $0.toDomainWithKey()
        }
    }

    public func fetchAll(from: String) throws -> [Album] {

        let context = ModelContext(container)

        let fetchDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate{$0.from == from},
            sortBy: [
                SortDescriptor(\.photoCount, order: .reverse),
                SortDescriptor(\.displayName, order: .forward)
            ]
        )
        return try context.fetch(fetchDescriptor).map {$0.toDomainWithKey()}
    }

    public func fetchAlbum(id: UUID) throws -> Album? {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.id == id })
        return try context.fetch(fetchDescriptor).first?.toDomainWithKey()
    }

    public func fetchPhotos(by albumId: UUID) throws -> [Photo] {

        let context = ModelContext(container)
        // 관계 predicate로 사진을 직접 조회하면 다른 컨텍스트에서 추가한 관계가 늦게 반영돼서, 앨범을 먼저 찾아 album.photos로 읽는다
        let albumDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == albumId }
        )
        guard let album = try context.fetch(albumDescriptor).first else { return [] }

        return album.photos
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.toDomain() }
    }

    /// 이 인물 앨범 얼굴들의 사진별 boundingBox(정규화, 원점 좌하단) — clusterId는 실제로 album.name
    public func fetchFaceBoundingBoxes(clusterId: String) throws -> [String: CGRect] {

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<FaceEmbeddingEntity>()

        let entities = try context.fetch(fetchDescriptor)

        var result: [String: CGRect] = [:]
        for entity in entities {
            guard entity.cluster?.album?.name == clusterId,
                  let localIdentifier = entity.photo?.localIdentifier else { continue }
            result[localIdentifier] = CGRect(
                x: entity.boundingBoxX,
                y: entity.boundingBoxY,
                width: entity.boundingBoxWidth,
                height: entity.boundingBoxHeight
            )
        }
        return result
    }

    public func fetchAnimalBoundingBoxes(clusterId: String) throws -> [String: CGRect] {

        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AnimalEmbeddingEntity>()

        let entities = try context.fetch(fetchDescriptor)

        var result: [String: CGRect] = [:]
        for entity in entities {
            guard entity.cluster?.album?.name == clusterId,
                  let localIdentifier = entity.photo?.localIdentifier else { continue }
            result[localIdentifier] = CGRect(
                x: entity.boundingBoxX,
                y: entity.boundingBoxY,
                width: entity.boundingBoxWidth,
                height: entity.boundingBoxHeight
            )
        }
        return result
    }

    /// 커버 사진 안에서 이 앨범 클러스터의 얼굴 boundingBox — 저장하지 않고 매번 찾아서 커버와 어긋나지 않게 한다
    public func fetchCoverFaceBoundingBox(albumId: UUID) throws -> CGRect? {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.id == albumId })

        guard let album = try context.fetch(fetchDescriptor).first,
              let coverPhotoIdentifier = album.coverPhotoIdentifier else { return nil }

        for cluster in album.clusters {
            if let entity = cluster.faceEmbeddings.first(where: { $0.photo?.localIdentifier == coverPhotoIdentifier }) {
                return CGRect(
                    x: entity.boundingBoxX,
                    y: entity.boundingBoxY,
                    width: entity.boundingBoxWidth,
                    height: entity.boundingBoxHeight
                )
            }
        }
        return nil
    }

    public func fetchCoverAnimalBoundingBox(albumId: UUID) throws -> CGRect? {
        let context = ModelContext(container)
        let fetchDescriptor = FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.id == albumId })

        guard let album = try context.fetch(fetchDescriptor).first,
              let coverPhotoIdentifier = album.coverPhotoIdentifier else { return nil }

        for cluster in album.animalClusters {
            if let entity = cluster.animalEmbeddings.first(where: { $0.photo?.localIdentifier == coverPhotoIdentifier }) {
                return CGRect(
                    x: entity.boundingBoxX,
                    y: entity.boundingBoxY,
                    width: entity.boundingBoxWidth,
                    height: entity.boundingBoxHeight
                )
            }
        }
        return nil
    }

    public func updateAlbum(album: Album) throws {

        let context = ModelContext(container)

        let id = album.id
        let fetchDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == id }
        )

        guard let entity = try context.fetch(fetchDescriptor).first else {
            throw AlbumRepositoryError.albumNotFound
        }

        entity.name = album.name
        entity.displayName = album.displayName
        // 직접 고른 대표 사진은 자동 갱신으로 덮지 않는다
        if !entity.coverPhotoManuallySet {
            entity.coverPhotoIdentifier = album.coverPhotoIdentifier
        }
        entity.photoCount = album.photoCount

        try context.save()
    }

    public func updateAlbumName(new name: String, id: UUID) throws {

        let context = ModelContext(container)

        let fetchDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == id }
        )

        guard let entity = try context.fetch(fetchDescriptor).first else {
            throw AlbumRepositoryError.albumNotFound
        }

        entity.displayName = name
        entity.isRenamed = true

        try context.save()

        try self.syncAlbums()
    }

    public func updateCoverPhoto(id: UUID, identifier: String) throws {

        let context = ModelContext(container)

        let fetchDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == id }
        )

        guard let entity = try context.fetch(fetchDescriptor).first else {
            throw AlbumRepositoryError.albumNotFound
        }

        // 영상은 대표 사진으로 고를 수 없다 — UI에서도 막지만 데이터 레이어에서도 한 번 더 확인
        let photoDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { $0.localIdentifier == identifier }
        )
        if let photo = try context.fetch(photoDescriptor).first, photo.isVideo {
            throw AlbumRepositoryError.coverPhotoCannotBeVideo
        }

        entity.coverPhotoIdentifier = identifier
        entity.coverPhotoManuallySet = true

        try context.save()

        try self.syncAlbums()
    }

    public func delete(id: UUID) throws {

        let context = ModelContext(container)

        let fetchDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == id }
        )

        guard let entity = try context.fetch(fetchDescriptor).first else {
            throw AlbumRepositoryError.albumNotFound
        }

        context.delete(entity)
        try context.save()

        try self.syncAlbums()
    }

    public func addPhotos(albumId: UUID, photoIdentifiers: [String]) throws {

        let context = ModelContext(container)

        let albumDescriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == albumId }
        )
        guard let album = try context.fetch(albumDescriptor).first else {
            throw AlbumRepositoryError.albumNotFound
        }

        let ids = photoIdentifiers
        let photoDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { ids.contains($0.localIdentifier) }
        )

        let fetchedPhotos = try context.fetch(photoDescriptor)

        // 앨범의 기존 사진 전체 대신, 추가할 사진 쪽 albums 관계로 중복을 확인한다(큰 앨범에서 훨씬 빠르다)
        let uniqueNewPhotos = fetchedPhotos.filter { photo in !photo.albums.contains { $0.id == albumId } }

        guard !uniqueNewPhotos.isEmpty else { return }

        album.photos.append(contentsOf: uniqueNewPhotos)
        album.photoCount = album.photos.count

        let newDates = uniqueNewPhotos.map { $0.createdAt }
        if let newMinDate = newDates.min(), let newMaxDate = newDates.max() {
            album.startDate = min(album.startDate ?? newMinDate, newMinDate)
            album.endDate = max(album.endDate ?? newMaxDate, newMaxDate)
        }

//        let allPhotos = album.photos.sorted {$0.createdAt < $1.createdAt}
//        album.startDate = allPhotos.first?.createdAt ?? Date()
//        album.endDate = allPhotos.last?.createdAt ?? Date()
//        
//        album.coverPhotoIdentifier = album.photos.sorted {
//            $0.createdAt > $1.createdAt
//        }.first?.localIdentifier

        album.refreshCover()

        try context.save()
    }

    public func deletePhotos(albumId: UUID, photoIdentifiers: [String]) throws {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.id == albumId }
        )
        guard let album = try context.fetch(descriptor).first else { return }

        // 이 앨범과의 연결만 끊는다 — PhotoEntity 자체를 지우면 다른 앨범/라벨/임베딩까지 같이 사라진다
        let ids = Set(photoIdentifiers)
        album.photos.removeAll { ids.contains($0.localIdentifier) }
        album.photoCount = album.photos.count
        // 사용자가 직접 뺀 것 — 여행 앨범 증분 갱신이 이 앨범을 지우고 다시 만들어 사진을 되살리지 않게 표시
        album.isEdited = true

        album.repairCoverIfMissing()

        try context.save()
    }

    public func deleteAutoAlbums(by from: String, onProgress: (Double) -> Void) throws {

        let context = ModelContext(container)

        let albumDescriptor: FetchDescriptor<AlbumEntity>
        if from == "all" {
            albumDescriptor = FetchDescriptor<AlbumEntity>(
                predicate: #Predicate { $0.isAuto == true }
            )
        } else {
            albumDescriptor = FetchDescriptor<AlbumEntity>(
                predicate: #Predicate { $0.isAuto == true && $0.from == from }
            )
        }

        let autoAlbums = try context.fetch(albumDescriptor)
        onProgress(0.1)

        // 진행률: 조회 10% / 앨범별 정리 80% / 저장 10%
        for (index, album) in autoAlbums.enumerated() {
            album.photos.removeAll()
            context.delete(album)
            onProgress(0.1 + 0.8 * Double(index + 1) / Double(autoAlbums.count))
        }
        try context.save()
        onProgress(1.0)
    }

    public func syncAlbums() throws {
        let updated = try fetchAll()
        albumsSubject.send(updated)
    }

    public func updateLinkedFaceAlbums(albumId: UUID, faceAlbumIds: [UUID]) throws {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.id == albumId })
        guard let entity = try context.fetch(descriptor).first else { return }

        entity.linkedFaceAlbumIds = faceAlbumIds
        try context.save()
    }

    public func fetchLinkedFaceAlbums(albumId: UUID) throws -> [Album] {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.id == albumId })
        guard let entity = try context.fetch(descriptor).first else { return [] }

        let ids = Set(entity.linkedFaceAlbumIds)
        guard !ids.isEmpty else { return [] }

        let faceAlbums = try context.fetch(FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.from == "face" }
        ))
        return faceAlbums.filter { ids.contains($0.id) }.map { $0.toDomainWithKey() }
    }

    public func updateLinkedAnimalAlbums(albumId: UUID, animalAlbumIds: [UUID]) throws {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.id == albumId })
        guard let entity = try context.fetch(descriptor).first else { return }

        entity.linkedAnimalAlbumIds = animalAlbumIds
        try context.save()
    }

    public func fetchLinkedAnimalAlbums(albumId: UUID) throws -> [Album] {
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.id == albumId })
        guard let entity = try context.fetch(descriptor).first else { return [] }

        let ids = Set(entity.linkedAnimalAlbumIds)
        guard !ids.isEmpty else { return [] }

        let animalAlbums = try context.fetch(FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.from == "animal" }
        ))
        return animalAlbums.filter { ids.contains($0.id) }.map { $0.toDomainWithKey() }
    }

    public func fetchOtherTravelAlbums(excluding albumId: UUID) throws -> [AlbumMergeCandidate] {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.from == "travel" }
        ))
        let others = albums.filter { $0.id != albumId }

        guard let current = albums.first(where: { $0.id == albumId }),
              let currentStart = current.startDate, let currentEnd = current.endDate
        else {
            return others.map { AlbumMergeCandidate(album: $0.toDomainWithKey(), similarity: -1) }
        }

        // 두 기간이 겹치면 0, 아니면 가까운 경계까지 간격(초) — 가까울수록 위로. similarity엔 정렬용으로 음수 간격을 넣는다
        func gap(to album: AlbumEntity) -> TimeInterval {
            guard let start = album.startDate, let end = album.endDate else { return .greatestFiniteMagnitude }
            if end < currentStart {
                return currentStart.timeIntervalSince(end)
            } else if start > currentEnd {
                return start.timeIntervalSince(currentEnd)
            } else {
                return 0
            }
        }

        return others
            .sorted { gap(to: $0) < gap(to: $1) }
            .map { AlbumMergeCandidate(album: $0.toDomainWithKey(), similarity: Float(-gap(to: $0))) }
    }

    public func mergeTravelAlbums(
        sourceId: UUID,
        targetId: UUID,
        photoIdentifiers: [String],
        startDate: Date,
        endDate: Date,
        displayName: String,
        linkedFaceAlbumIds: [UUID],
        linkedAnimalAlbumIds: [UUID]
    ) throws {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>())
        guard let source = albums.first(where: { $0.id == sourceId }),
              let target = albums.first(where: { $0.id == targetId }) else { return }

        let photoDescriptor = FetchDescriptor<PhotoEntity>(
            predicate: #Predicate { photoIdentifiers.contains($0.localIdentifier) }
        )
        let photos = try context.fetch(photoDescriptor)

        source.photos = photos
        source.photoCount = photos.count
        source.startDate = startDate
        source.endDate = endDate
        source.displayName = displayName
        source.isEdited = true
        source.linkedFaceAlbumIds = linkedFaceAlbumIds
        source.linkedAnimalAlbumIds = linkedAnimalAlbumIds
        // 기준 앨범(source)의 대표사진을 유지 — 합쳐진 사진에 없을 때만 다시 고른다
        source.repairCoverIfMissing()

        context.delete(target)
        try context.save()
    }

    public func deleteAll(onProgress: (Double) -> Void) throws {
        convertToAutoVacuumIfNeeded()

        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>())

        // 테이블 단위로 통째로 지우는 작업이라 더 잘게 쪼갤 신호가 없다 — 단계 하나가 끝날 때마다 진행률을 올린다
        let steps: [() throws -> Void] = [
            {
                albums.forEach { $0.photos.removeAll() }
                try context.save()
            },
            // cascade로 같이 지워지기 전에 자식부터 지워서 삭제 개수가 로그에 맞게 찍히게 한다
            { try self.deleteAllLogged(AlbumKeywordEntity.self, context: context) },
            { try self.deleteAllLogged(ClusterEntity.self, context: context) },
            { try self.deleteAllLogged(AnimalClusterEntity.self, context: context) },
            {
                debugLog("🗑️ AlbumEntity 삭제: \(albums.count)개")
                albums.forEach { context.delete($0) }
                try context.save()
            },
            // cascade로 같이 지워지기 전에 자식부터 지운다
            { try self.deleteAllLogged(PhotoLabelEntity.self, context: context) },
            { try self.deleteAllLogged(FaceEmbeddingEntity.self, context: context) },
            { try self.deleteAllLogged(AnimalEmbeddingEntity.self, context: context) },
            { try self.deleteAllLogged(PhotoEntity.self, context: context) },
            { try self.deleteAllLogged(ClusterBlacklistEntity.self, context: context) },
            { try self.deleteAllLogged(AnimalClusterBlacklistEntity.self, context: context) },
            // 직접 추가한 "자주가는 동네"는 사용자 설정이라 초기화해도 남긴다 — 자동 측정분만 지운다
            {
                try context.delete(model: HomeZoneEntity.self, where: #Predicate { $0.isManual == false })
                try context.save()
            },
            {
                try self.syncAlbums()
                self.incrementalVacuum()
            }
        ]

        for (index, step) in steps.enumerated() {
            try step()
            onProgress(Double(index + 1) / Double(steps.count))
        }
    }

    public func dataStoreSize() -> Int64 {
        guard let url = container.configurations.first?.url else { return 0 }

        let directory = url.deletingLastPathComponent()
        let fileName = url.lastPathComponent
        let candidates = [fileName, "\(fileName)-wal", "\(fileName)-shm"]
            .map { directory.appendingPathComponent($0) }

        return candidates.reduce(Int64(0)) { total, fileURL in
            let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
            return total + (size.flatMap { $0 } ?? 0)
        }
    }

    // MARK: - Vacuum

    // 삭제 후 파일 크기가 줄도록 최초 1회 auto_vacuum을 INCREMENTAL로 바꾼다 — 플래그 대신 실제 모드를 매번 조회
    private func convertToAutoVacuumIfNeeded() {
        guard currentAutoVacuumMode() == 0 else { return } // 0 = NONE(미적용), 1 = FULL, 2 = INCREMENTAL

        executeRawSQL("PRAGMA auto_vacuum = INCREMENTAL;", "VACUUM;", "PRAGMA wal_checkpoint(TRUNCATE);")
    }

    private func currentAutoVacuumMode() -> Int32? {
        guard let url = container.configurations.first?.url else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA auto_vacuum;", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return sqlite3_column_int(statement, 0)
    }

    // SwiftData 내부 변경 기록(ACHANGE/ATRANSACTION) 테이블도 같이 비운다 — 앱에서 쓰지 않는다
    private func incrementalVacuum() {
        executeRawSQL(
            "DELETE FROM ACHANGE;",
            "DELETE FROM ATRANSACTION;",
            "DELETE FROM ATRANSACTIONSTRING;",
            "PRAGMA incremental_vacuum;",
            "PRAGMA wal_checkpoint(TRUNCATE);"
        )
    }

    // 평소에도 쌓이는 변경 기록은 앱 실행 때마다 7일 지난 것만 지운다
    private static let historyRetentionInterval: TimeInterval = 7 * 24 * 60 * 60

    public func pruneOldHistory() {
        let cutoff = Date().addingTimeInterval(-Self.historyRetentionInterval).timeIntervalSinceReferenceDate
        executeRawSQL(
            "DELETE FROM ACHANGE WHERE ZTRANSACTIONID IN (SELECT Z_PK FROM ATRANSACTION WHERE ZTIMESTAMP < \(cutoff));",
            "DELETE FROM ATRANSACTION WHERE ZTIMESTAMP < \(cutoff);",
            "PRAGMA incremental_vacuum;",
            "PRAGMA wal_checkpoint(TRUNCATE);"
        )
    }

    // VACUUM은 SwiftData API가 없어서 스토어 파일에 직접 연결해 실행한다 — 모든 save가 끝난 뒤에만 호출
    private func executeRawSQL(_ statements: String...) {
        guard let url = container.configurations.first?.url else { return }

        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            sqlite3_close(db)
            return
        }
        defer { sqlite3_close(db) }

        for sql in statements {
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }

    // 타입 단위 일괄 삭제는 필수 역관계가 있으면 실패해서 하나씩 지운다
    private func deleteAllLogged<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        items.forEach { context.delete($0) }
        try context.save()
        debugLog("🗑️ \(T.self) 삭제: \(items.count)개")
    }
}
