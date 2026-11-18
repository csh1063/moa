//
//  SimilarPhotoClusterRepository.swift
//  Domain
//
//  Created by sanghyeon on 6/24/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

public protocol SimilarPhotoClusterRepository {
    func clusterAndSaveAlbums(photos: [Photo], existingAlbums: [Album], onProgress: @escaping @Sendable (Double) -> Void) async throws

    /// 새 사진의 시간 윈도우 안 사진만 비교해서 기존 앨범에 더하거나 새로 만든다(기존 앨범은 안 지움)
    /// - allPhotos: 시간 윈도우 이웃을 찾을 전체 사진(id+createdAt이면 충분)
    func clusterNewPhotos(
        newPhotos: [Photo],
        allPhotos: [Photo],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}
