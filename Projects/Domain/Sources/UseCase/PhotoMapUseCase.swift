//
//  PhotoMapUseCase.swift
//  Domain
//
//  Created by sanghyeon on 9/8/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 장소 지도용 — 좌표 있는 사진을 한 번만 조회한다(핀 묶기는 [[PhotoMapClustering]]이 줌마다 계산)
public protocol PhotoMapUseCase {
    func fetchPhotosWithCoordinates() async throws -> [Photo]
}

public final class DefaultPhotoMapUseCase: PhotoMapUseCase {

    private let photoDataRepository: PhotoDataRepository

    public init(photoDataRepository: PhotoDataRepository) {
        self.photoDataRepository = photoDataRepository
    }

    public func fetchPhotosWithCoordinates() async throws -> [Photo] {
        try photoDataRepository.fetchHasCoordinators()
    }
}
