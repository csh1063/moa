//
//  DefaultPhotoLibraryRepository.swift
//  Data
//
//  Created by sanghyeon on 3/11/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Domain
import Photos

public final class DefaultPhotoLibraryRepository: PhotoLibraryRepository {

    private let libraryService: PhotoLibraryService
    private let permissionService: PermissionService

    public init(
        libraryService: PhotoLibraryService,
        permissionService: PermissionService
    ) {
        self.libraryService = libraryService
        self.permissionService = permissionService
    }

    public func fetchPhotoCount() async throws -> Int {
        return try await self.libraryService.getPhotoCount()
    }

    public func fetchPhotos(page: Int, pageCount: Int) async throws -> PhotoList {
        return try await self.libraryService.getPhotoList(page: page, pageCount: pageCount).toDomain()
    }

    public func fetchPhotoIds() async throws -> [String] {
        return try await self.libraryService.getPhotoIds()
    }

    public func checkPermission() async throws -> PhotoPermission {
        try await self.permissionService.checkPermission()
    }

    public func deletePhotos(by ids: [String]) async throws {
        try await self.libraryService.deletePhotos(localIdentifiers: ids)
    }

    public func loadImage<T>(id: String, type: LoadPhotoOptionType) async throws -> ImageData<T> {
        let cgImage = try await self.libraryService.loadImage(id: id, type: type)
        return ImageData(cgImage: cgImage as? T)
    }

    public func loadVideoAsset<T>(id: String) async throws -> T? {
        let playerItem = try await self.libraryService.loadPlayerItem(id: id)
        return playerItem as? T
    }

    public func fetchPhotos(before date: Date, page: Int, pageCount: Int) async throws -> PhotoList {
        try await self.libraryService.getPhotosBefore(date, page: page, pageCount: pageCount).toDomain()
    }

    public func fetchPhotos(after date: Date, page: Int, pageCount: Int) async throws -> PhotoList {
        try await self.libraryService.getPhotosAfter(date, page: page, pageCount: pageCount).toDomain()
    }

    public func fetchDeviceAlbums() async throws -> [AlbumAsset] {
        try await self.libraryService.getAlbumList().map { $0.toDomain() }
    }

    public func fetchAllPhotos(in collection: PHAssetCollection) async throws -> [PhotoInAlbum] {
        // page: -1은 페이지네이션 없이 전체를 한 번에 반환 (PhotoLibraryService.getPhotoList 참고)
        try await self.libraryService.getPhotoList(from: collection, page: -1).toDomain().photos
    }

    public func loadImageProgressive<T>(id: String, size: CGSize, onImage: @escaping (ImageData<T>, Bool) -> Void) async {
        await self.libraryService.loadImageProgressive(id: id, targetSize: size) { cgImage, isFinal in
            onImage(ImageData(cgImage: cgImage as? T), isFinal)
        }
    }
}
