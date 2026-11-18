//
//  PhotoCheckUseCase.swift
//  Domain
//
//  Created by sanghyeon on 4/4/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol PhotoCheckUseCase {
    func checkDeletedPhoto() async throws -> AsyncThrowingStream<ProgressState, Error>
    func syncCoverAndCount() async throws -> AsyncThrowingStream<ProgressState, Error>
}

public class DefaultPhotoCheckUseCase: PhotoCheckUseCase {

    private let photoLibraryRepository: PhotoLibraryRepository
    private let photoDataRepository: PhotoDataRepository
    private let albumDataRepository: AlbumDataRepository

    public init(photoLibraryRepository: PhotoLibraryRepository,
                photoDataRepository: PhotoDataRepository,
                albumDataRepository: AlbumDataRepository) {
        self.photoLibraryRepository = photoLibraryRepository
        self.photoDataRepository = photoDataRepository
        self.albumDataRepository = albumDataRepository
    }

    /// 사진첩에서 지워진 사진을 DB에서도 지운다 — DB id를 페이지로 읽어 사진첩에 없는 것만 모아 한 번에 삭제
    public func checkDeletedPhoto() async throws -> AsyncThrowingStream<ProgressState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {

                    let photoCount = try photoDataRepository.fetchPhotoCount()
                    guard photoCount > 0 else {
                        // 분석 이력이 없으면 비교할 게 없어서 사진첩 접근도 하지 않는다
                        continuation.yield(.completed)
                        continuation.finish()
                        return
                    }

                    let libraryIds = Set(try await photoLibraryRepository.fetchPhotos().photos.map {$0.localIdentifier})
                    let countPerPage = 1000
                    let maxPage = Double(photoCount) / Double(countPerPage)

                    var page = 0
                    var deletedPhoto: [String] = []
                    while true {
                        let savedPhotos = try photoDataRepository.fetchIds(page: page, pageSize: countPerPage)
                        debugLog("savedPhotos page: \(page) count: \(savedPhotos.count)")
                        if savedPhotos.isEmpty { break }

                        deletedPhoto.append(contentsOf: savedPhotos.filter { !libraryIds.contains($0) })

                        page += 1

                        let ratio = Double(page) / maxPage * 0.8
                        continuation.yield(.progress(ratio))
                    }

                    debugLog("deletedPhoto \(deletedPhoto.count)")

                    continuation.yield(.progress(0.9))
                    try photoDataRepository.deleteBatch(identifiers: deletedPhoto)
                    continuation.yield(.progress(1.0))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    debugLog("error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func syncCoverAndCount() async throws -> AsyncThrowingStream<ProgressState, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let albums = try albumDataRepository.fetchAll()

                    for (index, album) in albums.enumerated() {
                        let coverPhotoIdentifier = try photoDataRepository.fetchSyncPhotoId(byAlbum: album.id)
                        let photoCount = try photoDataRepository.fetchSyncPhotoCount(byAlbum: album.id)
                        let newAlbum = Album(id: album.id,
                                               name: album.name,
                                               displayName: album.displayName,
                                               coverPhotoIdentifier: coverPhotoIdentifier,
                                               photoCount: photoCount,
                                               from: album.from)

                        try albumDataRepository.updateAlbum(album: newAlbum)

                        let ratio = Double(index) / Double(albums.count)
                        continuation.yield(.progress(ratio))
                    }

                    continuation.yield(.progress(1.0))
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    debugLog("error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
