//
//  PhotoImageUseCase.swift
//  Domain
//
//  Created by sanghyeon on 4/25/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol PhotoImageUseCase {
    func loadImage<T>(id: String, type: LoadPhotoOptionType) async throws -> ImageData<T>
    /// 그리드/카드 썸네일 전용 저화질→고화질 순차 로딩
    func loadImageProgressive<T>(id: String, size: CGSize, onImage: @escaping (ImageData<T>, _ isFinal: Bool) -> Void) async
}

public class DefaultPhotoImageUseCase: PhotoImageUseCase {

    private let repository: PhotoLibraryRepository

    public init(repository: PhotoLibraryRepository) {
        self.repository = repository
    }

    public func loadImage<T>(id: String, type: LoadPhotoOptionType) async throws -> ImageData<T> {
        return try await self.repository.loadImage(id: id, type: type)
    }

    public func loadImageProgressive<T>(id: String, size: CGSize, onImage: @escaping (ImageData<T>, Bool) -> Void) async {
        await self.repository.loadImageProgressive(id: id, size: size, onImage: onImage)
    }
}
