//
//  ImageViewerUseCase.swift
//  Domain
//
//  Created by sanghyeon on 5/10/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol ImageViewerUseCase {
    func loadImage<T>(id: String, type: LoadPhotoOptionType) async throws -> ImageData<T>
    /// 화면 크기 정도의 저화질을 먼저 콜백하고, 뒤이어 최대 해상도로 교체할 때 쓴다
    func loadImageProgressive<T>(id: String, size: CGSize, onImage: @escaping (ImageData<T>, _ isFinal: Bool) -> Void) async
    func loadVideoAsset<T>(id: String) async throws -> T?
    func getLabels(by localIdentifier: String) async throws -> [PhotoLabel]
    /// 뷰어 하단 정보(위치 등)용 — 분석이 끝난 사진만, 아니면 nil(미분석 표시)
    func getAnalyzedPhoto(by localIdentifier: String) async throws -> Photo?
}

public class DefaultImageViewerUseCase: ImageViewerUseCase {

    private let repository: PhotoLibraryRepository
    private let labelRepository: PhotoLabelDataRepository
    private let dataRepository: PhotoDataRepository

    public init(repository: PhotoLibraryRepository,
                labelRepository: PhotoLabelDataRepository,
                dataRepository: PhotoDataRepository) {
        self.repository = repository
        self.labelRepository = labelRepository
        self.dataRepository = dataRepository
    }

    public func loadImage<T>(id: String, type: LoadPhotoOptionType) async throws -> ImageData<T> {
        return try await self.repository.loadImage(id: id, type: type)
    }

    public func loadImageProgressive<T>(id: String, size: CGSize, onImage: @escaping (ImageData<T>, Bool) -> Void) async {
        await self.repository.loadImageProgressive(id: id, size: size, onImage: onImage)
    }

    public func loadVideoAsset<T>(id: String) async throws -> T? {
        return try await self.repository.loadVideoAsset(id: id)
    }

    public func getLabels(by localIdentifier: String) async throws -> [PhotoLabel] {
        return try self.labelRepository.fetchLabelsByPhoto(localIdentifier: localIdentifier)
    }

    public func getAnalyzedPhoto(by localIdentifier: String) async throws -> Photo? {
        guard let photo = try dataRepository.fetchPhoto(localIdentifier: localIdentifier), photo.analyzedAt != nil else { return nil }
        return photo
    }
}
