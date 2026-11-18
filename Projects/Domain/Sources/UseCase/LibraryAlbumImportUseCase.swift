//
//  LibraryAlbumImportUseCase.swift
//  Domain
//
//  Created by sanghyeon on 9/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 사진 앱의 앨범을 moa 앨범(isAuto: false, from: "library")으로 가져온다
public protocol LibraryAlbumImportUseCase {
    func fetchDeviceAlbums() async throws -> [AlbumAsset]
    func importAlbum(_ albumAsset: AlbumAsset) async throws -> Album
}

public final class DefaultLibraryAlbumImportUseCase: LibraryAlbumImportUseCase {

    private let photoLibraryRepository: PhotoLibraryRepository
    private let photoDataRepository: PhotoDataRepository
    private let albumDataRepository: AlbumDataRepository

    public init(
        photoLibraryRepository: PhotoLibraryRepository,
        photoDataRepository: PhotoDataRepository,
        albumDataRepository: AlbumDataRepository
    ) {
        self.photoLibraryRepository = photoLibraryRepository
        self.photoDataRepository = photoDataRepository
        self.albumDataRepository = albumDataRepository
    }

    public func fetchDeviceAlbums() async throws -> [AlbumAsset] {
        try await photoLibraryRepository.fetchDeviceAlbums()
    }

    public func importAlbum(_ albumAsset: AlbumAsset) async throws -> Album {
        guard let collection = albumAsset.collection else {
            throw AlbumRepositoryError.albumNotFound
        }

        let libraryPhotos = try await photoLibraryRepository.fetchAllPhotos(in: collection)
        let albumName = albumAsset.name

        // 동기 SwiftData 작업이라 메인 스레드가 막히지 않게 분리한다
        let photoDataRepository = self.photoDataRepository
        let albumDataRepository = self.albumDataRepository

        return try await Task.detached(priority: .userInitiated) {
            // 분석 안 된 사진도 연결되게 기본 정보부터 저장한다 — 나중에 분석하기에서 이어서 분석된다
            let basePhotos = libraryPhotos.map { item -> Photo in
                let createdAt = item.createdDate ?? Date()
                let components = Calendar.current.dateComponents([.year, .month], from: createdAt)
                return Photo(
                    localIdentifier: item.localIdentifier,
                    createdAt: createdAt,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    year: components.year.map { String($0) },
                    month: components.month.map { String($0) },
                    isVideo: item.isVideo
                )
            }
            try photoDataRepository.saveAllPhotosBase(basePhotos)

            let identifiers = libraryPhotos.map { $0.localIdentifier }
            let album = Album(
                name: albumName,
                displayName: albumName,
                isAuto: false,
                photoCount: identifiers.count,
                from: "library"
            )
            // returnExist: true — 같은 이름으로 이미 가져온 적 있으면 새로 안 만들고 기존 앨범에 이어붙인다
            guard let saved = try albumDataRepository.saveAlbum(album: album, returnExist: true) else {
                throw AlbumRepositoryError.albumNotFound
            }

            try albumDataRepository.addPhotos(albumId: saved.id, photoIdentifiers: identifiers)
            try albumDataRepository.syncAlbums()

            return saved
        }.value
    }
}
