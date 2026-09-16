//
//  LibraryAlbumImportUseCase.swift
//  Domain
//
//  Created by sanghyeon on 9/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 아이폰 기본 사진 앱(스마트 앨범 + 사용자 앨범)에 이미 있는 앨범을 moa 앨범으로 가져온다.
/// 자동 분류 앨범(isAuto: true)과 구분하기 위해 항상 isAuto: false, from: "library"로 저장하고,
/// 그 앨범에 속한 사진 전체를 연결한다.
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

        // saveAllPhotosBase가 기존 PhotoEntity 전체를 훑어 dedup하고, addPhotos도 SwiftData
        // 읽기/쓰기를 동기로 하기 때문에 호출부(ViewModel)가 @MainActor라 그대로 두면 메인 스레드가
        // 그만큼 막힌다 — 사진 많은 앨범/이미 라이브러리가 큰 사용자일수록 체감되므로 detach한다.
        let photoDataRepository = self.photoDataRepository
        let albumDataRepository = self.albumDataRepository

        return try await Task.detached(priority: .userInitiated) {
            // 아직 한 번도 분석된 적 없는 사진(=PhotoEntity 없음)도 앨범에 연결은 돼야 하므로, 기본
            // 메타데이터만이라도 먼저 저장해둔다 — saveAllPhotosBase는 이미 존재하는 localIdentifier는
            // 알아서 건너뛰므로 다시 불러도 안전하다(PhotoAnalysisUseCase.saveAllPhotosBase와 동일 패턴).
            // analyzedAt/albumsGeneratedAt을 안 채우고 nil로 남겨두므로, 나중에 "분석하기"를 돌리면
            // 이 사진들도 미분석 사진과 똑같이 라벨/얼굴/날짜·카테고리 앨범 분류까지 자연스럽게 이어진다.
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
