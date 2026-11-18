//
//  PhotoLibraryUseCase.swift
//  Domain
//
//  Created by sanghyeon on 3/12/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol PhotoLibraryUseCase {
    func fetchPhoto() async throws -> PhotoList
    func checkPermission() async throws -> PhotoPermission
}

public class DefaultPhotoLibraryUseCase: PhotoLibraryUseCase {

    private let repository: PhotoLibraryRepository
    private let dataRepository: PhotoDataRepository

    public init(repository: PhotoLibraryRepository, dataRepository: PhotoDataRepository) {
        self.repository = repository
        self.dataRepository = dataRepository
    }

    public func fetchPhoto() async throws -> PhotoList {

        let library = try await self.repository.fetchPhotos()

        // 미분석 표시에는 id만 있으면 된다 — 위치 같은 사진 정보는 뷰어가 보고 있는 사진 것만 따로 불러온다
        let analyzedIds = Set(try dataRepository.fetchAnalyzed())

        let updatedPhotos = library.photos.map { libraryPhoto -> PhotoInAlbum in
            var updatedPhoto = libraryPhoto
            // 영상은 분석 대상이 아니라 미분석으로 표시하지 않는다
            updatedPhoto.isUnanalysis = !libraryPhoto.isVideo && !analyzedIds.contains(libraryPhoto.localIdentifier)
            return updatedPhoto
        }

        return PhotoList(
            title: library.title,
            photos: updatedPhotos,
            hasNext: library.hasNext,
            totalCount: library.totalCount
        )
    }

    public func checkPermission() async throws -> PhotoPermission {
        try await self.repository.checkPermission()
    }
}
