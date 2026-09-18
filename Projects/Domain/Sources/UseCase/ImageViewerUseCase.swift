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
}

public class DefaultImageViewerUseCase: ImageViewerUseCase {

    private let repository: PhotoLibraryRepository
    private let labelRepository: PhotoLabelDataRepository

    public init(repository: PhotoLibraryRepository,
                labelRepository: PhotoLabelDataRepository) {
        self.repository = repository
        self.labelRepository = labelRepository
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
}
