//
//  PhotoLibraryRepository.swift
//  Domain
//
//  Created by sanghyeon on 3/11/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Photos

public protocol PhotoLibraryRepository {
    func fetchPhotos(page: Int, pageCount: Int) async throws -> PhotoList
    func fetchPhotoCount() async throws -> Int
    func fetchPhotoIds() async throws -> [String]
    func checkPermission() async throws -> PhotoPermission
    func loadImage<T>(id: String, type: LoadPhotoOptionType) async throws -> ImageData<T>
    /// 상세화면 실제 재생용 — 영상만 해당, T는 호출부에서 AVPlayerItem으로 캐스트한다
    /// (다른 로딩 경로와 마찬가지로 Domain이 AVFoundation을 직접 알 필요 없게 제네릭으로 타입 소거)
    func loadVideoAsset<T>(id: String) async throws -> T?
    func deletePhotos(by ids: [String]) async throws
    /// 여행 앨범 "사진 추가" 피커용 — 기준 날짜 이전 사진(최신순)/이후 사진(오래된순)을 페이지 단위로 조회
    func fetchPhotos(before date: Date, page: Int, pageCount: Int) async throws -> PhotoList
    func fetchPhotos(after date: Date, page: Int, pageCount: Int) async throws -> PhotoList
    /// "사진첩 앨범 불러오기" 피커용 — 기기의 스마트 앨범 + 사용자 앨범 목록
    func fetchDeviceAlbums() async throws -> [AlbumAsset]
    /// 특정 기기 앨범에 속한 사진 전체(페이지 없이 한 번에) — 이 앨범을 moa 앨범으로 가져올 때 사용
    func fetchAllPhotos(in collection: PHAssetCollection) async throws -> [PhotoInAlbum]
}

extension PhotoLibraryRepository {
    func fetchPhotos(page: Int = -1, pageCount: Int = 300) async throws -> PhotoList {
        try await fetchPhotos(page: page, pageCount: pageCount)
    }
}
