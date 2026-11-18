//
//  PhotoLibraryService.swift
//  Data
//
//  Created by sanghyeon on 3/11/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Domain
import Photos
import PhotosUI
import AVFoundation

public final class PhotoLibraryService {

    private let imageManager = PHCachingImageManager()

    private var pHResultMap: [PHCollection: PHFetchResult<PHAsset>] = [:]
    private var allPhotos: PHFetchResult<PHAsset>?

    // 여행 앨범 "사진 추가" 피커용 — 기준 날짜 이전/이후 캐시 (같은 날짜로 여러 페이지 넘길 때 매번 새로 조회하지 않도록)
    private var beforeResultMap: [Date: PHFetchResult<PHAsset>] = [:]
    private var afterResultMap: [Date: PHFetchResult<PHAsset>] = [:]

//    private var assetCache: [String: PHAsset] = [:]
    private let assetCache = AssetCache()

    public init() {}

    /// "사진첩 앨범 불러오기"용 — 사용자가 만든 앨범만(스마트 앨범 제외)
    public func getAlbumList() async throws -> [AlbumAssetEntity] {

        return await Task.detached(priority: .userInitiated) {

            var albumModelList = [AlbumAssetEntity]()

            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)

            let albums = [userAlbums]
            for album in albums {
                album.enumerateObjects { (collection, _, _) in
                    let opt = PHFetchOptions()
                    let assets = PHAsset.fetchAssets(in: collection, options: opt)
                    // PHFetchResult에는 isEmpty가 없음 — swiftlint --fix가 !isEmpty로 잘못 고치지 않도록 disable
                    // swiftlint:disable:next empty_count
                    if assets.count > 0 {
                        let fetchOptions = PHFetchOptions()
                        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                        fetchOptions.predicate = PHFetchOptions.mediaTypePredicate

                        let newAlbum = AlbumAssetEntity(
                            name: collection.localizedTitle ?? "",
                            count: assets.count,
                            collection: collection)

                        albumModelList.append(newAlbum)
                    }
                }
            }

            return albumModelList
        }.value
    }

    public func getPhotoList(from collection: PHAssetCollection? = nil, page: Int = -1, pageCount: Int = 300, reload: Bool = false) async throws -> PhotoAssetListEntity {

        let result: PHFetchResult<PHAsset>

        if let collection {
            if let savedResult = self.pHResultMap[collection], !reload {
                result = savedResult
            } else {
                result = PHAsset.fetchAssets(in: collection, options: .defaultOptions)
                self.pHResultMap[collection] = result
            }
        } else {
            if let savedAll = self.allPhotos, !reload {
                result = savedAll
            } else {
                result = PHAsset.fetchAssets(with: .defaultOptions)
            }
        }

        let totalCount = result.count
        let rangeStart: Int
        let rangeEnd: Int

        if page < 0 {
            rangeStart = 0
            rangeEnd = totalCount
        } else {
            let realPage = max(1, page)
            let start = (realPage - 1) * pageCount
            let end = start + pageCount
            rangeStart = min(start, totalCount)
            rangeEnd = min(end, totalCount)
        }

        let photos = (rangeStart..<rangeEnd).map { PhotoAssetEntity(asset: result.object(at: $0)) }
        // 사진마다 캐시용 Task를 따로 만들던 걸(수만 개) 한 번에 넣는다
        await assetCache.set(photos.map { $0.asset })

        let sortedPhotos = photos.sorted {
            let created0 = $0.asset.creationDate ?? Date.distantPast
            let created1 = $1.asset.creationDate ?? Date.distantPast

            if created0 == created1 {
                return $0.asset.modificationDate ?? Date.distantPast
                    > $1.asset.modificationDate ?? Date.distantPast
            } else {
                return created0 > created1
            }
        }

        return PhotoAssetListEntity(
            title: collection?.localizedTitle ?? "",
            photos: sortedPhotos,
            hasNext: rangeEnd < totalCount,
            totalCount: totalCount
        )
    }

    /// 기준 날짜보다 이전 사진들을 최신순(날짜 내림차순)으로 페이지 단위로 반환
    public func getPhotosBefore(_ date: Date, page: Int, pageCount: Int) async throws -> PhotoAssetListEntity {
        let result: PHFetchResult<PHAsset>
        if let cached = beforeResultMap[date] {
            result = cached
        } else {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                PHFetchOptions.mediaTypePredicate,
                NSPredicate(format: "creationDate < %@", date as NSDate)
            ])
            result = PHAsset.fetchAssets(with: options)
            beforeResultMap[date] = result
        }
        return await makeList(from: result, title: "", page: page, pageCount: pageCount)
    }

    /// 기준 날짜보다 이후 사진들을 오래된순(날짜 오름차순)으로 페이지 단위로 반환
    public func getPhotosAfter(_ date: Date, page: Int, pageCount: Int) async throws -> PhotoAssetListEntity {
        let result: PHFetchResult<PHAsset>
        if let cached = afterResultMap[date] {
            result = cached
        } else {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                PHFetchOptions.mediaTypePredicate,
                NSPredicate(format: "creationDate > %@", date as NSDate)
            ])
            result = PHAsset.fetchAssets(with: options)
            afterResultMap[date] = result
        }
        return await makeList(from: result, title: "", page: page, pageCount: pageCount)
    }

    private func makeList(from result: PHFetchResult<PHAsset>, title: String, page: Int, pageCount: Int) async -> PhotoAssetListEntity {
        let totalCount = result.count
        let realPage = max(1, page)
        let start = min((realPage - 1) * pageCount, totalCount)
        let end = min(start + pageCount, totalCount)

        let photos = (start..<end).map { PhotoAssetEntity(asset: result.object(at: $0)) }
        await assetCache.set(photos.map { $0.asset })

        return PhotoAssetListEntity(title: title, photos: photos, hasNext: end < totalCount, totalCount: totalCount)
    }

    public func getPhotoCount(from collection: PHAssetCollection? = nil) async throws -> Int {

        let result: PHFetchResult<PHAsset>

        if let collection {
            if let savedResult = self.pHResultMap[collection] {
                result = savedResult
            } else {
                result = PHAsset.fetchAssets(in: collection, options: .defaultOptions)
                self.pHResultMap[collection] = result
            }
        } else {
            if let savedAll = self.allPhotos {
                result = savedAll
            } else {
                result = PHAsset.fetchAssets(with: .defaultOptions)
            }
        }

        return result.count
    }

    /// 분석 대상 사진 id — 영상은 분석하지 않아서 뺀다
    public func getImageIds() async throws -> [String] {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        return (0..<result.count).map { result.object(at: $0).localIdentifier }
    }

    public func getPhotoIds() async throws -> [String] {

        let result: PHFetchResult<PHAsset>
        if let savedAll = self.allPhotos {
            result = savedAll
        } else {
            result = PHAsset.fetchAssets(with: .defaultOptions)
        }

        let totalCount = result.count

        return (0..<totalCount).map { index -> String in
            return result.object(at: index).localIdentifier
        }
    }

    // 시스템 문제로 콜백이 영영 안 올 수 있어서, 배치 전체가 멈추지 않게 타임아웃을 둔다
    private static let loadImageTimeout: TimeInterval = 8

    public func loadImage(id: String, type: LoadPhotoOptionType) async throws -> CGImage? {
        guard let asset = await getAsset(id: id) else { return nil }

        let options = PHImageRequestOptions()
        let size: CGSize
        let contentMode: PHImageContentMode
        switch type {
        case .maxSize:
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            size = PHImageManagerMaximumSize
            contentMode = .default
        case .specialSize(let specialSize):
            options.resizeMode = .fast
            // 고화질 콜백만 요청한다 — opportunistic은 고화질 콜백이 안 오는 자산이 있어 무한 대기할 수 있다
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            size = specialSize
            contentMode = .aspectFit
        }

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            func resumeOnce(_ work: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                work()
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.loadImageTimeout) {
                resumeOnce { continuation.resume(returning: nil) }
            }

            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: contentMode,
                options: options) { image, info in
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    if isDegraded { return }  // 저화질 중간 콜백은 무시(위 주석 참고)

                    if let error = info?[PHImageErrorKey] as? Error {
                        resumeOnce { continuation.resume(throwing: error) }
                        return
                    }
                    resumeOnce { continuation.resume(returning: image?.cgImage) }
            }
        }
    }

    /// 그리드/카드 썸네일 전용 — 저화질을 먼저 보여주고 고화질 콜백이 오면 바꾼다
    public func loadImageProgressive(
        id: String,
        targetSize: CGSize,
        onImage: @escaping (CGImage?, _ isFinal: Bool) -> Void
    ) async {
        guard let asset = await getAsset(id: id) else {
            onImage(nil, true)
            return
        }

        let options = PHImageRequestOptions()
        options.resizeMode = .fast
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
            onImage(image?.cgImage, !isDegraded)
        }
    }

    /// 상세화면 실제 재생용 — 영상 PHAsset을 AVPlayerItem으로 불러온다
    public func loadPlayerItem(id: String) async throws -> AVPlayerItem? {
        guard let asset = await getAsset(id: id) else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        return await withCheckedContinuation { continuation in
            imageManager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                continuation.resume(returning: playerItem)
            }
        }
    }

    public func getLocationPhoto(ids: [String]) async throws -> [PHAsset] {
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: ids,
            options: nil
        )

        var photosWithLocation: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            if asset.location != nil {
                photosWithLocation.append(asset)
            }
        }
        return photosWithLocation
    }

    public func deletePhotos(localIdentifiers: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        let assetsArray = assets.objects(at: IndexSet(0..<assets.count)) as NSArray

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assetsArray)
        }
    }

    private func getAsset(id: String) async -> PHAsset? {

//        if let cached = assetCache[id] { return cached }
        if let cached = await assetCache.get(id) { return cached }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        if let asset = fetched {
            await assetCache.set(id, asset: asset)
        }
//        if let asset = fetched {
//            self.assetCache[id] = asset
//        }
        return fetched
    }

    func startCaching(for assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCaching(for assets: [PHAsset], targetSize: CGSize) {
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }
}

extension PHFetchOptions {
    static var defaultOptions: PHFetchOptions {
        let option = PHFetchOptions()
        option.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false),
            NSSortDescriptor(key: "modificationDate", ascending: false)
        ]
        option.predicate = mediaTypePredicate
        return option
    }

    /// 사진 + 영상 — 영상은 날짜/지역/여행 앨범에는 들어가고 분석 대상에서만 빠진다
    static var mediaTypePredicate: NSPredicate {
        NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
    }
}

actor AssetCache {
    private var cache: [String: PHAsset] = [:]

    func get(_ id: String) -> PHAsset? { cache[id] }
    func set(_ id: String, asset: PHAsset) { cache[id] = asset }
    func set(_ assets: [PHAsset]) {
        for asset in assets { cache[asset.localIdentifier] = asset }
    }
}
