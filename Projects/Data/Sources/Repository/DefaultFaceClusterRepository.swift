//
//  DefaultFaceClusterRepository.swift
//  Data
//
//  Created by sanghyeon on 5/18/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Domain
import Foundation
import SwiftData
import Accelerate

public final class DefaultFaceClusterRepository: FaceClusterRepository {
    private let container: ModelContainer
    private let clusterService: FaceClusterService

    public init(container: ModelContainer, clusterService: FaceClusterService) {
        self.container = container
        self.clusterService = clusterService
    }

    // MARK: - 전체 클러스터링 및 앨범 저장

    public func clusterAndSaveAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let context = ModelContext(container)

        // 1. 얼굴 임베딩 로드 — 같은 사진이면 같은 결과가 나오게 id 순으로 고정
        var embeddingDescriptor = FetchDescriptor<FaceEmbeddingEntity>(
            predicate: #Predicate { $0.hasGlasses == false }
        )
        // 루프에서 하나씩 읽지 않게(N+1) 관계를 미리 당겨온다
        embeddingDescriptor.relationshipKeyPathsForPrefetching = [\.photo, \.cluster]
        let allEntities = try context.fetch(embeddingDescriptor)
            .sorted { $0.id.uuidString < $1.id.uuidString }

        debugLog("📦 [Repository] 총 \(allEntities.count)개 임베딩 로드")

        guard !allEntities.isEmpty else { return }

        // 블랙리스트 로드
        let blacklists = try context.fetch(FetchDescriptor<ClusterBlacklistEntity>())
        let blacklistSets = blacklists.map { Set($0.embeddingIds) }

        // 기존 face 앨범 수 기준으로 인물 번호 시작
        let existingAlbumCount = try context.fetchCount(FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.from == "face" }
        ))

        // 기존 클러스터 — 다시 돌려도 같은 사람은 기존 앨범을 재사용한다
        var existingClusters = try context.fetch(FetchDescriptor<ClusterEntity>())

        // 클러스터링 — 남은 임베딩은 최대 3회 재시도 후 전체를 합쳐 최종 병합까지 끝낸 결과
        let embeddings = Array(allEntities.map { $0.toDomain() }.reversed())
        // 진행률: 클러스터링 0~0.9, 앨범 적용 0.9~1
        let outcome = clusterService.clusterWithLeftoverRetry(embeddings: embeddings) { ratio in
            onProgress(ratio * 0.9)
        }

        debugLog("📊 총 \(outcome.clusters.count)개 클러스터 생성 (leftover \(outcome.leftover.count)개)")

        let entityById = Dictionary(uniqueKeysWithValues: allEntities.map { ($0.id, $0) })
        var personIndex = try nextAlbumNumber(context: context)
        let dim = 512

        for result in outcome.clusters {
            applyClusterResult(
                result,
                context: context,
                entityById: entityById,
                blacklistSets: blacklistSets,
                existingClusters: &existingClusters,
                personIndex: &personIndex,
                dim: dim
            )
        }

        // 최초(또는 전체 재생성)일 때만 사진 수 순으로 번호를 다시 매긴다
        if existingAlbumCount == 0 {
            renumberAlbums(context: context)
        }

        try context.save()
        onProgress(1.0)
    }

    /// 인물 앨범을 사진 수 순으로 "인물 1"부터 다시 번호 매긴다 — 직접 이름 지은 앨범은 번호를 건너뛴다
    private func renumberAlbums(context: ModelContext) {
        guard let albums = try? context.fetch(FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.from == "face" }
        )) else { return }

        let sorted = albums.filter { !$0.isRenamed }.sorted { $0.photoCount > $1.photoCount }
        for (index, album) in sorted.enumerated() {
            let newName = "인물 \(index + 1)"
            album.name = newName
            album.displayName = newName
        }
    }

    /// 클러스터 결과 하나를 기존 앨범과 매칭하거나 새 앨범으로 저장한다
    private func applyClusterResult(
        _ result: ClusterResult<FaceEmbedding>,
        context: ModelContext,
        entityById: [UUID: FaceEmbeddingEntity],
        blacklistSets: [Set<UUID>],
        existingClusters: inout [ClusterEntity],
        personIndex: inout Int,
        dim: Int
    ) {
        let embeddingIds = Set(result.embeddings.map { $0.id })

        // 블랙리스트 체크
        let isBlacklisted = blacklistSets.contains { blacklistSet in
            let intersection = embeddingIds.intersection(blacklistSet)
            return Double(intersection.count) / Double(blacklistSet.count) >= 0.5
        }
        guard !isBlacklisted else {
            debugLog("🚫 블랙리스트 클러스터 스킵")
            return
        }

        let cluster: ClusterEntity
        let album: AlbumEntity

        // 기존 클러스터 중 centroid가 충분히 비슷한 게 있으면 새로 안 만들고 재사용
        if let matched = findMatchingCluster(centroid: result.centroid, in: existingClusters, dim: dim),
           let matchedAlbum = matched.album {
            cluster = matched
            album = matchedAlbum
            debugLog("🔄 [\(album.name)] 기존 앨범 재사용")
        } else {
            let centroidData = result.centroid.withUnsafeBytes { Data($0) }
            let albumName = "인물 \(personIndex)"

            album = AlbumEntity(
                id: UUID(),
                name: albumName,
                displayName: albumName,
                isAuto: true,
                coverPhotoIdentifier: nil,
                from: "face"
            )
            context.insert(album)
            personIndex += 1

            cluster = ClusterEntity(centroidData: centroidData)
            context.insert(cluster)
            cluster.album = album
            album.clusters.append(cluster)
            existingClusters.append(cluster)
        }

        var currentPhotoIds = Set(album.photos.map { $0.localIdentifier })
        let excludedPhotoIds = Set(album.clusters.flatMap { $0.excludedPhotoIds })
        var currentEmbeddingIds = Set(cluster.faceEmbeddings.map { $0.id })

        for embedding in result.embeddings {
            guard let entity = entityById[embedding.id] else { continue }
            entity.cluster = cluster
            if !currentEmbeddingIds.contains(entity.id) {
                cluster.faceEmbeddings.append(entity)
                currentEmbeddingIds.insert(entity.id)
            }

            guard let photo = entity.photo else { continue }
            // 사용자가 "이 앨범에서 제외"한 사진은 전체 재클러스터링에서도 다시 넣지 않는다 (증분 경로와 같은 규칙)
            if !excludedPhotoIds.contains(photo.localIdentifier), !currentPhotoIds.contains(photo.localIdentifier) {
                album.photos.append(photo)
                currentPhotoIds.insert(photo.localIdentifier)
            }
        }

        // 재사용된 클러스터는 새로 합쳐진 멤버 기준으로 centroid 갱신
        updateCentroid(cluster: cluster, dim: dim)

        album.photoCount = album.photos.count

        // 대표사진 규칙(직접 고른 것 유지, 아니면 화질 최고)은 AlbumEntity+Cover 참고
        album.refreshCover()
        debugLog("✅ [\(album.name)] \(album.photoCount)장")
    }

    // 새로 계산된 centroid가 기존 클러스터 중 하나와 충분히 비슷하면 그 클러스터를 반환 (없으면 nil)
    private func findMatchingCluster(centroid: [Float], in clusters: [ClusterEntity], dim: Int, threshold: Float = 0.68) -> ClusterEntity? {
        guard !clusters.isEmpty else { return nil }

        let centroidsFlat: [Float] = clusters.flatMap { cluster -> [Float] in
            cluster.centroidData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self).prefix(dim))
            }
        }

        let similarities = computeSimilarities(embedding: centroid, centroids: centroidsFlat, clusterCount: clusters.count, dim: dim)
        guard let maxIndex = similarities.indices.max(by: { similarities[$0] < similarities[$1] }) else { return nil }

        return similarities[maxIndex] >= threshold ? clusters[maxIndex] : nil
    }

    // MARK: - 새 임베딩 클러스터 매칭

    /// 새 얼굴 임베딩을 가장 비슷한 기존 클러스터(유사도 0.68 이상)에 붙인다 — 전체 재클러스터링 없이
    public func matchAndAddNewEmbeddings(embeddingIds: [UUID]) async throws {
        guard !embeddingIds.isEmpty else { return }
        debugLog("🔍 새 임베딩 \(embeddingIds.count)개 매칭 시작")

        let context = ModelContext(container)

        let newEntities = try context.fetch(FetchDescriptor<FaceEmbeddingEntity>()).filter {
            embeddingIds.contains($0.id) && !$0.hasGlasses
        }

        let allClusters = try context.fetch(FetchDescriptor<ClusterEntity>())
        guard !allClusters.isEmpty else { return }

        let dim = 512
        let centroidsFlat: [Float] = allClusters.flatMap { cluster -> [Float] in
            cluster.centroidData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self).prefix(dim))
            }
        }

        for entity in newEntities {
            let embedding: [Float] = entity.embeddingData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self).prefix(dim))
            }

            let similarities = computeSimilarities(
                embedding: embedding,
                centroids: centroidsFlat,
                clusterCount: allClusters.count,
                dim: dim
            )

            guard let maxIndex = similarities.indices.max(by: { similarities[$0] < similarities[$1] }) else { continue }
            let maxSim = similarities[maxIndex]
            guard maxSim >= 0.68 else { continue }

            let matchedCluster = allClusters[maxIndex]

            if let photoId = entity.photo?.localIdentifier,
               matchedCluster.excludedPhotoIds.contains(photoId) {
                debugLog("🚫 제외된 사진 스킵: \(photoId)")
                continue
            }

            entity.cluster = matchedCluster
            matchedCluster.faceEmbeddings.append(entity)

            if let photo = entity.photo, let album = matchedCluster.album {
                if !album.photos.contains(where: { $0.localIdentifier == photo.localIdentifier }) {
                    album.photos.append(photo)
                    album.photoCount = album.photos.count
                }
            }

            updateCentroid(cluster: matchedCluster, dim: dim)
            debugLog("✅ 매칭 성공 (유사도: \(String(format: "%.4f", maxSim)))")
        }

        try context.save()
    }

    // MARK: - 앨범 병합

    public func mergeAlbums(sourceId: UUID, targetId: UUID) async throws {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>())
        guard let source = albums.first(where: { $0.id == sourceId }),
              let target = albums.first(where: { $0.id == targetId }) else { return }

        // 분리할 때 복원하려고 원래 이름을 기억한다 — 이미 있으면 제일 처음 이름을 유지
        for cluster in source.clusters where cluster.originalDisplayName == nil {
            cluster.originalName = source.name
            cluster.originalDisplayName = source.displayName
            cluster.originalIsRenamed = source.isRenamed
        }
        for cluster in target.clusters where cluster.originalDisplayName == nil {
            cluster.originalName = target.name
            cluster.originalDisplayName = target.displayName
            cluster.originalIsRenamed = target.isRenamed
        }

        let identity = resolveMergedIdentity(source: source, target: target)

        for cluster in target.clusters {
            cluster.album = source
            if !source.clusters.contains(where: { $0.id == cluster.id }) {
                source.clusters.append(cluster)
            }
        }
        // 옮긴 클러스터가 target에 남아 있으면 target 삭제 때 cascade로 같이 지워진다
        target.clusters.removeAll()

        let existingPhotoIds = Set(source.photos.map { $0.localIdentifier })
        for photo in target.photos where !existingPhotoIds.contains(photo.localIdentifier) {
            source.photos.append(photo)
        }

        source.name = identity.name
        source.displayName = identity.displayName
        source.isRenamed = identity.isRenamed
        source.photoCount = source.photos.count
        source.isEdited = true

        context.delete(target)
        try context.save()
        debugLog("🔀 병합 완료: \(target.name) → \(source.name), 최종 \(source.photoCount)장")
    }

    /// 합친 앨범의 이름 — 둘 다 자동 번호면 낮은 번호, 직접 지은 이름이 있으면 그 이름
    private func resolveMergedIdentity(source: AlbumEntity, target: AlbumEntity) -> (name: String, displayName: String, isRenamed: Bool) {
        if source.isRenamed && target.isRenamed { return (source.name, source.displayName, true) }
        if target.isRenamed { return (target.name, target.displayName, true) }
        if source.isRenamed { return (source.name, source.displayName, true) }

        let sourceNum = trailingNumber(source.name) ?? Int.max
        let targetNum = trailingNumber(target.name) ?? Int.max
        return targetNum < sourceNum
            ? (target.name, target.displayName, false)
            : (source.name, source.displayName, false)
    }

    private func trailingNumber(_ name: String) -> Int? {
        name.split(separator: " ").last.flatMap { Int($0) }
    }

    // 앨범 "개수 + 1"로 번호를 붙이면 병합 후 분리할 때 이미 있는 번호가 또 나온다 → 가장 큰 번호 + 1
    private func nextAlbumNumber(context: ModelContext) throws -> Int {
        let albums = try context.fetch(FetchDescriptor<AlbumEntity>(predicate: #Predicate { $0.from == "face" }))
        return (albums.compactMap { trailingNumber($0.name) }.max() ?? 0) + 1
    }

    // MARK: - 사진 제외

    public func excludePhoto(photoId: String, fromAlbumId: UUID) async throws {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>())
        guard let album = albums.first(where: { $0.id == fromAlbumId }) else { return }

        for cluster in album.clusters {
            if cluster.faceEmbeddings.contains(where: { $0.photo?.localIdentifier == photoId }) {
                cluster.excludedPhotoIds.append(photoId)
            }
        }

        album.photos.removeAll { $0.localIdentifier == photoId }
        album.photoCount = album.photos.count
        album.isEdited = true
        album.repairCoverIfMissing()

        try context.save()
    }

    // MARK: - 앨범 삭제 + 블랙리스트

    public func deleteAlbum(albumId: UUID) async throws {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>())
        guard let album = albums.first(where: { $0.id == albumId }) else { return }

        for cluster in album.clusters {
            let ids = cluster.faceEmbeddings.map { $0.id }
            guard !ids.isEmpty else { continue }
            let blacklist = ClusterBlacklistEntity(embeddingIds: ids)
            context.insert(blacklist)
        }

        context.delete(album)
        try context.save()
    }

    // MARK: - 합칠 앨범 후보 (centroid 유사도 순 정렬)

    /// 이미 계산되어 저장된 클러스터 centroid끼리 내적만 하면 되므로, 앨범 수가 많아도 사실상 즉시 끝난다
    public func fetchOtherFaceAlbumsSortedBySimilarity(excluding albumId: UUID) async throws -> [AlbumMergeCandidate] {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>(
            predicate: #Predicate { $0.from == "face" }
        ))
        let others = albums.filter { $0.id != albumId }

        guard let current = albums.first(where: { $0.id == albumId }) else {
            return others.map { AlbumMergeCandidate(album: $0.toDomain(), similarity: -1) }
        }

        let dim = 512
        let currentCentroids: [[Float]] = current.clusters.map { cluster in
            cluster.centroidData.withUnsafeBytes { ptr in Array(ptr.bindMemory(to: Float.self).prefix(dim)) }
        }
        guard !currentCentroids.isEmpty else {
            return others.map { AlbumMergeCandidate(album: $0.toDomain(), similarity: -1) }
        }

        func maxSimilarity(to album: AlbumEntity) -> Float {
            var best: Float = -1
            for cluster in album.clusters {
                let centroid = cluster.centroidData.withUnsafeBytes { ptr -> [Float] in
                    Array(ptr.bindMemory(to: Float.self).prefix(dim))
                }
                for candidate in currentCentroids {
                    var dot: Float = 0
                    vDSP_dotpr(candidate, 1, centroid, 1, &dot, vDSP_Length(dim))
                    best = max(best, dot)
                }
            }
            return best
        }

        let ranked = others
            .map { ($0, maxSimilarity(to: $0)) }
            .sorted { $0.1 > $1.1 }

        return ranked.map { AlbumMergeCandidate(album: $0.0.toDomain(), similarity: $0.1) }
    }

    public func fetchFaceAlbumIds(forPhotoIds photoIds: [String]) async throws -> [UUID] {
        let context = ModelContext(container)

        let ids = Set(photoIds)
        let embeddings = try context.fetch(FetchDescriptor<FaceEmbeddingEntity>())
        let matched = embeddings.filter { entity in
            guard let localIdentifier = entity.photo?.localIdentifier else { return false }
            return ids.contains(localIdentifier)
        }

        let albumIds = matched.compactMap { $0.cluster?.album?.id }
        return Array(Set(albumIds))
    }

    // MARK: - 앨범 분리 (병합 되돌리기)

    public func fetchClusters(albumId: UUID) async throws -> [FaceClusterSummary] {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>())
        guard let album = albums.first(where: { $0.id == albumId }) else { return [] }

        return album.clusters.map { cluster in
            let cover = cluster.faceEmbeddings.max(by: { $0.captureQuality < $1.captureQuality })
            let photoCount = Set(cluster.faceEmbeddings.compactMap { $0.photo?.localIdentifier }).count
            return FaceClusterSummary(id: cluster.id, photoCount: photoCount, coverPhotoId: cover?.photo?.localIdentifier)
        }
    }

    /// 고른 클러스터를 새 앨범으로 분리 — 원래 이름이 있으면 복원, 두 사람이 같이 나온 사진은 양쪽에 남긴다
    public func splitAlbum(albumId: UUID, clusterIds: [UUID]) async throws {
        let context = ModelContext(container)

        let albums = try context.fetch(FetchDescriptor<AlbumEntity>())
        guard let album = albums.first(where: { $0.id == albumId }) else { return }

        let clustersToSplit = album.clusters.filter { clusterIds.contains($0.id) }
        // 전부 떼어내면 원본 앨범이 텅 비므로, 최소 1개 클러스터는 남아있어야 분리가 성립한다
        guard !clustersToSplit.isEmpty, clustersToSplit.count < album.clusters.count else { return }

        // 분리 대상이 모두 같은 원래 이름을 기억하면 그 이름으로 복원, 아니면 새 번호
        let origins = Set(clustersToSplit.map { $0.originalDisplayName })
        let newAlbumName: String
        let newDisplayName: String
        let newIsRenamed: Bool
        if origins.count == 1,
           let originalDisplayName = clustersToSplit.first?.originalDisplayName,
           let originalName = clustersToSplit.first?.originalName {
            newAlbumName = originalName
            newDisplayName = originalDisplayName
            newIsRenamed = clustersToSplit.first?.originalIsRenamed ?? false
            // 집으로 돌아왔으니 기록 초기화 — 다음에 또 합쳐지면 그때 다시 기록된다
            for cluster in clustersToSplit {
                cluster.originalName = nil
                cluster.originalDisplayName = nil
                cluster.originalIsRenamed = false
            }
        } else {
            newAlbumName = "인물 \(try nextAlbumNumber(context: context))"
            newDisplayName = newAlbumName
            newIsRenamed = false
        }
        let newAlbum = AlbumEntity(
            id: UUID(),
            name: newAlbumName,
            displayName: newDisplayName,
            isAuto: true,
            coverPhotoIdentifier: nil,
            from: "face"
        )
        newAlbum.isRenamed = newIsRenamed
        context.insert(newAlbum)

        let movingPhotoIds = Set(clustersToSplit.flatMap { $0.faceEmbeddings.compactMap { $0.photo?.localIdentifier } })

        for cluster in clustersToSplit {
            cluster.album = newAlbum
            newAlbum.clusters.append(cluster)
            album.clusters.removeAll { $0.id == cluster.id }
        }

        // 남은 클러스터에도 걸쳐있는 사진(한 사진에 두 사람 얼굴)은 원본 앨범에도 계속 남겨둔다
        let remainingPhotoIds = Set(album.clusters.flatMap { $0.faceEmbeddings.compactMap { $0.photo?.localIdentifier } })
        let photoEntities = Dictionary(uniqueKeysWithValues: album.photos.map { ($0.localIdentifier, $0) })

        for photoId in movingPhotoIds {
            guard let photo = photoEntities[photoId] else { continue }
            if !newAlbum.photos.contains(where: { $0.localIdentifier == photoId }) {
                newAlbum.photos.append(photo)
            }
            if !remainingPhotoIds.contains(photoId) {
                album.photos.removeAll { $0.localIdentifier == photoId }
            }
        }

        album.photoCount = album.photos.count
        newAlbum.photoCount = newAlbum.photos.count
        album.isEdited = true

        // 원래 앨범은 직접 고른 사진이 남아 있으면 유지, 새 앨범은 화질 기준
        album.refreshCover()
        newAlbum.refreshCover()

        try context.save()
        debugLog("✂️ 분리 완료 — \(album.name): \(album.photoCount)장 / \(newAlbum.name): \(newAlbum.photoCount)장")
    }

    // MARK: - Private Helpers

    private func computeSimilarities(embedding: [Float], centroids: [Float], clusterCount: Int, dim: Int) -> [Float] {
        var result = [Float](repeating: 0, count: clusterCount)
        embedding.withUnsafeBufferPointer { embPtr in
            centroids.withUnsafeBufferPointer { centPtr in
                result.withUnsafeMutableBufferPointer { resPtr in
                    cblas_sgemm(
                        CblasRowMajor, CblasNoTrans, CblasTrans,
                        1, Int32(clusterCount), Int32(dim),
                        1.0,
                        embPtr.baseAddress!, Int32(dim),
                        centPtr.baseAddress!, Int32(dim),
                        0.0,
                        resPtr.baseAddress!, Int32(clusterCount)
                    )
                }
            }
        }
        return result
    }

    private func updateCentroid(cluster: ClusterEntity, dim: Int) {
        let embeddings = cluster.faceEmbeddings.compactMap { entity -> [Float]? in
            entity.embeddingData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self).prefix(dim))
            }
        }
        guard !embeddings.isEmpty else { return }

        var centroid = [Float](repeating: 0, count: dim)
        for emb in embeddings {
            vDSP_vadd(centroid, 1, emb, 1, &centroid, 1, vDSP_Length(dim))
        }
        var count = Float(embeddings.count)
        vDSP_vsdiv(centroid, 1, &count, &centroid, 1, vDSP_Length(dim))
        var normSquared: Float = 0
        vDSP_svesq(centroid, 1, &normSquared, vDSP_Length(dim))
        var norm = sqrt(normSquared)
        if norm > 0 { vDSP_vsdiv(centroid, 1, &norm, &centroid, 1, vDSP_Length(dim)) }
        cluster.centroidData = centroid.withUnsafeBytes { Data($0) }
    }
}
