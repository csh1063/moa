//
//  PhotoMapUseCase.swift
//  Domain
//
//  Created by sanghyeon on 9/8/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 장소 지도 화면 전용 — 좌표가 있는 사진들을 낱장으로 가져온다. 실제로 지도에 몇 개의 핀으로
/// 묶어서 보여줄지는 [[PhotoMapClustering]]이 줌 레벨에 따라 그때그때 계산한다 — 여기서는 DB
/// 조회 한 번만 담당(줌마다 다시 조회하지 않도록 ViewModel이 결과를 메모리에 들고 있는다).
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
