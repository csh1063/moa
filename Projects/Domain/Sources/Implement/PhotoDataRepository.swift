//
//  PhotoDataRepository.swift
//  Domain
//
//  Created by sanghyeon on 3/21/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol PhotoDataRepository {
    func savePhoto(photo: Photo) throws
    func saveAllPhotosBase(_ photos: [Photo]) throws
    func saveAndUpdateLabels(photo: Photo, labels: [PhotoLabel]) async throws
    func fetchPhotos(page: Int, pageSize: Int) throws -> [Photo]
    func fetchAll(page: Int, pageSize: Int) throws -> [Photo]
    func fetchPhotoCount() throws -> Int
    func fetchIds(page: Int, pageSize: Int) throws -> [String]
    func fetchHasCoordinators() throws -> [Photo]
    /// 좌표가 있는 가장 최근 사진 하나
    func fetchLatestLocated() throws -> Photo?
    func fetchPhoto(localIdentifier: String) throws -> Photo?
    /// 영상 앨범용 — 라이브러리 전체의 영상 사진
    func fetchVideos() throws -> [Photo]
    func fetchAnalyzed() throws -> [String]
    func fetchAnalyzedCount() throws -> Int
    func fetchLocationUnanalyzed() throws -> [Photo]
    func fetchAlbumUnclassified(limit: Int, offset: Int) throws -> [Photo]
    /// 분류 완료 여부와 상관없이 전체 사진을 offset으로 — 전체 재생성용
    func fetchAllForClassification(limit: Int, offset: Int) throws -> [Photo]
    func markAlbumsGenerated(identifiers: [String]) throws
    func fetchSimilarUnchecked() throws -> [Photo]
    func markSimilarChecked(identifiers: [String]) throws
    func fetchSyncPhotoId(byAlbum localIdentifier: UUID) throws -> String?
    func fetchSyncPhotoCount(byAlbum localIdentifier: UUID) throws -> Int
    /// 여러 장을 한 번에 지운다 — 영향받는 앨범마다 한 번만 정리하고 저장한다
    func deleteBatch(identifiers: [String]) throws
    /// 날짜 범위(양끝 포함) 안의 사진 전체 — 위치 유무와 상관없이
    func fetchPhotos(from startDate: Date, to endDate: Date) throws -> [Photo]
}

extension PhotoDataRepository {
    func fetchAll(page: Int = -1, pageSize: Int = 50) throws -> [Photo] {
        return try fetchAll(page: page, pageSize: pageSize)
    }

    func fetchPhotos(page: Int = -1, pageSize: Int = 300) throws -> [Photo] {
        return try fetchPhotos(page: page, pageSize: pageSize)
    }
}
