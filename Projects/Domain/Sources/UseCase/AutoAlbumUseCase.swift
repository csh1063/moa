//
//  AutoAlbumUseCase.swift
//  Domain
//
//  Created by sanghyeon on 3/22/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol AutoAlbumUseCase {
    /// fullRegenerate: true면 "이미 분류됨" 표시를 무시하고 전체 사진을 다시 분류한다(앨범만 지운 재생성용)
    func generateAllAlbums(fullRegenerate: Bool) -> AsyncThrowingStream<ProgressAlbum, Error>

    // MARK: - 점진적 앨범 노출용 (분석 진행 중 단계별로 호출)

    /// 날짜 앨범만 즉시 생성 — 기본 스캔 직후 호출
    func createDateAlbumsEarly() async throws
    /// 영상만 모은 단일 앨범 — 기본 스캔 직후 호출
    func createVideoAlbumEarly() async throws
    /// 여행 + 지역 앨범 — 주소(지오코딩) 스트림이 끝나면 호출
    func createTravelAlbumsEarly() async throws
    /// 카테고리 앨범(+날짜 안전망, 분류 완료 표시) — 라벨 스트림이 끝나면 얼굴/동물보다 먼저 호출
    func createCategoryAlbumsEarly() async throws
    /// 얼굴/동물 앨범 + 여행자 연결 — onProgress는 앨범 생성 진행률만
    func createPersonAndSimilarAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// 비슷한 사진 탐지 — 임베딩 추출과 비교가 대부분이라 분석 게이지의 일부로 보여준다
    func detectDuplicatePhotos(onProgress: @escaping @Sendable (Double) -> Void) async throws

    // 개별 재생성 — onProgress는 각자 0~1
    func createDateAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createLocationAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createCategoryAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createFaceAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createAnimalAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// 여행 앨범을 전부 지우고 좌표 있는 사진 전체로 다시 만든다(편집한 여행 포함)
    func rebuildAllTravelAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createSimilarAlbum(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func deletePhotos(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// types의 자동 앨범을 순서대로 지운다 — "all"이면 전체 자동 앨범
    func deleteAutoAlbums(from types: [String], onProgress: @escaping @Sendable (Double) -> Void) async throws
}

extension AutoAlbumUseCase {
    public func generateAllAlbums() -> AsyncThrowingStream<ProgressAlbum, Error> {
        generateAllAlbums(fullRegenerate: false)
    }
}

public final class DefaultAutoAlbumUseCase: AutoAlbumUseCase {

    private let photoDataRepository: PhotoDataRepository
    private let albumDataRepository: AlbumDataRepository
    private let photoCategoryRepository: PhotoCategoryRepository
    private let userDefaultRepository: UserDefaultRepository
    private let travelRepository: TravelDetectionRepository
    private let homeZoneRepository: HomeZoneRepository
    private let faceClusterRepository: FaceClusterRepository
    private let animalClusterRepository: AnimalClusterRepository
    private let similarRepository: SimilarPhotoClusterRepository

    // 날짜/주소/카테고리 분류의 페이지 크기
    private let classificationPageSize = 300

    public init(
        photoDataRepository: PhotoDataRepository,
        albumDataRepository: AlbumDataRepository,
        photoCategoryRepository: PhotoCategoryRepository,
        userDefaultRepository: UserDefaultRepository,
        travelRepository: TravelDetectionRepository,
        homeZoneRepository: HomeZoneRepository,
        faceClusterRepository: FaceClusterRepository,
        animalClusterRepository: AnimalClusterRepository,
        similarRepository: SimilarPhotoClusterRepository
    ) {
        self.photoDataRepository = photoDataRepository
        self.albumDataRepository = albumDataRepository
        self.photoCategoryRepository = photoCategoryRepository
        self.userDefaultRepository = userDefaultRepository
        self.travelRepository = travelRepository
        self.homeZoneRepository = homeZoneRepository
        self.faceClusterRepository = faceClusterRepository
        self.animalClusterRepository = animalClusterRepository
        self.similarRepository = similarRepository
    }

    // MARK: - 통합 파이프라인

    /// 앨범 생성 전체 플로우: 날짜·주소·카테고리 → 영상 → 얼굴 → 동물 → 여행(+여행자 연결) → 비슷한 사진
    /// 날짜·주소·카테고리는 아직 분류 안 된 사진만, 비슷한 사진은 시간 윈도우 안에서만 증분 처리한다
    public func generateAllAlbums(fullRegenerate: Bool) -> AsyncThrowingStream<ProgressAlbum, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let totalSteps = 5.0
                    let overallStartedAt = Date()
                    debugLog("🚀 [전체 재생성] 시작 — fullRegenerate: \(fullRegenerate), \(overallStartedAt)")

                    try Task.checkCancellation()
                    try await classifyNewPhotosCore(fullRegenerate: fullRegenerate) { ratio in
                        continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: ratio * (1 / totalSteps)))
                    }
                    // 영상 앨범도 isAuto라 전체 재생성 때 지워지므로 여기서 다시 만든다
                    try createVideoAlbumCore()
                    continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 1 / totalSteps))

                    try Task.checkCancellation()
                    try await createFaceAlbumsCore { ratio in
                        continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 1 / totalSteps + ratio * (1 / totalSteps)))
                    }
                    continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 2 / totalSteps))

                    try Task.checkCancellation()
                    try await createAnimalAlbumsCore { ratio in
                        continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 2 / totalSteps + ratio * (1 / totalSteps)))
                    }
                    continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 3 / totalSteps))

                    // 여행자 연결에 얼굴/동물 앨범이 필요해서 그 다음에 만든다
                    try Task.checkCancellation()
                    try await createTravelAlbumsCore()
                    try await linkTravelersToTravelAlbumsCore()
                    continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 4 / totalSteps))

                    try Task.checkCancellation()
                    try await updateSimilarAlbumsIncrementalCore(fullRegenerate: fullRegenerate) { ratio in
                        continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 4 / totalSteps + ratio * (1 / totalSteps)))
                    }
                    continuation.yield(ProgressAlbum(step: .creatingAlbums, ratio: 1.0))

                    try albumDataRepository.syncAlbums()
                    try await userDefaultRepository.saveAnalyzedDate()
                    try await userDefaultRepository.saveLocationAnalyzedDate()

                    let finishedAt = Date()
                    debugLog("🚀 [전체 재생성] 완료 — \(finishedAt), 총 \(String(format: "%.1f", finishedAt.timeIntervalSince(overallStartedAt)))초")
                    continuation.yield(ProgressAlbum(step: .completed, ratio: 1.0))
                    continuation.finish()
                } catch {
                    debugLog("🚀 [전체 재생성] 실패 — \(Date())")
                    continuation.finish(throwing: error)
                }
            }
            // 소비하는 쪽이 취소되면 안쪽 Task도 멈추게 한다
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - 점진적 앨범 노출용

    public func createDateAlbumsEarly() async throws {
        try createDateAlbumsCore()
        try albumDataRepository.syncAlbums()
    }

    public func createVideoAlbumEarly() async throws {
        try createVideoAlbumCore()
        try albumDataRepository.syncAlbums()
    }

    public func createTravelAlbumsEarly() async throws {
        try await createTravelAlbumsCore()
        // 지역은 주소만 있으면 돼서 라벨을 기다리지 않고 여행 다음에 처리한다
        try await classifyLocationOnlyCore()
        // 얼굴/동물이 먼저 끝났을 수 있어서 여기서도 연결한다
        try await linkTravelersToTravelAlbumsCore()
        try albumDataRepository.syncAlbums()
        try await userDefaultRepository.saveLocationAnalyzedDate()
    }

    // 분류 완료로 표시된 사진은 지역 패스가 못 보므로, 호출하는 쪽이 여행+지역이 끝난 뒤에 부른다
    public func createCategoryAlbumsEarly() async throws {
        try await classifyCategoryAndFinalizeCore()
        try albumDataRepository.syncAlbums()
        try await userDefaultRepository.saveAnalyzedDate()
    }

    public func createPersonAndSimilarAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        // 얼굴 50% / 동물 50%
        try await createFaceAlbumsCore { ratio in onProgress(ratio * 0.5) }
        try await createAnimalAlbumsCore { ratio in onProgress(0.5 + ratio * 0.5) }
        onProgress(1.0)
        // 여행 앨범이 먼저 만들어졌을 수 있어서 여기서도 연결한다
        try await linkTravelersToTravelAlbumsCore()
    }

    public func detectDuplicatePhotos(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await updateSimilarAlbumsIncrementalCore(onProgress: onProgress)
    }

    // MARK: - 앨범 타입별 단독 재생성 (테스트/개별 재생성용)

    // 개별 재생성 — 해당 타입 앨범을 지우고 전체를 다시 만든다(분석하기의 증분 경로는 별도)
    public func createDateAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try self.albumDataRepository.deleteAutoAlbums(by: "date")
        try createDateAlbumsCore(onProgress: onProgress)
        try albumDataRepository.syncAlbums()
    }

    public func createLocationAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try self.albumDataRepository.deleteAutoAlbums(by: "location")
        try createLocationAlbumsCore(onProgress: onProgress)
        try albumDataRepository.syncAlbums()
    }

    public func createCategoryAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try self.albumDataRepository.deleteAutoAlbums(by: "category")
        try await createCategoryAlbumsCore(onProgress: onProgress)
        try albumDataRepository.syncAlbums()
    }

    public func createFaceAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try self.albumDataRepository.deleteAutoAlbums(by: "face")
        try await createFaceAlbumsCore(onProgress: onProgress)
        // 새 인물 앨범은 id가 바뀌어서 여행 동행자 연결을 다시 채운다
        try await linkTravelersToTravelAlbumsCore()
        try albumDataRepository.syncAlbums()
    }

    public func createAnimalAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try self.albumDataRepository.deleteAutoAlbums(by: "animal")
        try await createAnimalAlbumsCore(onProgress: onProgress)
        try await linkTravelersToTravelAlbumsCore()
        try albumDataRepository.syncAlbums()
    }

    public func createSimilarAlbum(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let allPhotos = try photoDataRepository.fetchPhotos()
        try await createSimilarAlbumsCore(from: allPhotos, onProgress: onProgress)
    }

    public func rebuildAllTravelAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try albumDataRepository.deleteAutoAlbums(by: "travel")
        try await createTravelAlbumsCore { onProgress($0 * 0.9) }
        // 지우면서 끊긴 여행자 연결을 다시 채운다
        try await linkTravelersToTravelAlbumsCore()
        try albumDataRepository.syncAlbums()
        onProgress(1.0)
    }

    public func deletePhotos(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try self.albumDataRepository.deleteAll(onProgress: onProgress)
        try await userDefaultRepository.resetAnalyzedDate()
    }

    public func deleteAutoAlbums(from types: [String], onProgress: @escaping @Sendable (Double) -> Void) async throws {
        for (index, type) in types.enumerated() {
            try albumDataRepository.deleteAutoAlbums(by: type) { ratio in
                onProgress((Double(index) + ratio) / Double(types.count))
            }
        }
    }

    // MARK: - 앨범 생성 코어 로직

    /// 개별 재생성 진행률 중 스캔 몫 — 스캔 80% / 쓰기 20%
    private func scanRatio(processed: Int, total: Int) -> Double {
        guard total > 0 else { return 0.8 }
        return min(Double(processed) / Double(total), 1) * 0.8
    }

    private func createDateAlbumsCore(onProgress: (Double) -> Void = { _ in }) throws {
        var albums = try albumDataRepository.fetchAll(from: "date")
        var albumPhotoMap: [UUID: [String]] = [:]
        var page = 0
        let totalCount = (try? photoDataRepository.fetchPhotoCount()) ?? 0

        while true {
            let photos = try photoDataRepository.fetchPhotos(page: page, pageSize: classificationPageSize)
            if photos.isEmpty { break }

            let years = Set(photos.compactMap { $0.year })
            for year in years {
                let album = Album(
                    name: year,
                    displayName: "\(year)",
                    isAuto: true,
                    keywords: ["\(year)", "\(year)년"],
                    photoCount: 0,
                    from: "date"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    albums.append(saved)
                }
            }

            for album in albums {
                let matchedIdentifiers = photos
                    .filter { album.keywords.contains($0.year ?? "") }
                    .map { $0.localIdentifier }
                albumPhotoMap[album.id, default: []].append(contentsOf: matchedIdentifiers)
            }

            page += 1
            onProgress(scanRatio(processed: page * classificationPageSize, total: totalCount))
        }

        for (index, (albumId, photoIdentifiers)) in albumPhotoMap.enumerated() {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            onProgress(0.8 + 0.2 * Double(index + 1) / Double(albumPhotoMap.count))
        }
    }

    // 영상은 분석 대상이 아니라 "영상" 앨범 하나에 모은다
    private func createVideoAlbumCore() throws {
        let videoPhotos = try photoDataRepository.fetchVideos()
        guard !videoPhotos.isEmpty else {
            debugLog("🎬 [영상 앨범] 대상 없음")
            return
        }
        debugLog("🎬 [영상 앨범] \(videoPhotos.count)개 처리 시작")

        let album = Album(
            name: "video",
            displayName: "영상",
            isAuto: true,
            photoCount: 0,
            from: "video"
        )
        if let saved = try albumDataRepository.saveAlbum(album: album, returnExist: true) {
            try albumDataRepository.addPhotos(albumId: saved.id, photoIdentifiers: videoPhotos.map { $0.localIdentifier })
        }
        debugLog("🎬 [영상 앨범] 완료")
    }

    /// 지역 앨범 전체 재계산 — 사진을 주소 키로 묶어 앨범마다 한 번에 쓴다
    private func createLocationAlbumsCore(onProgress: (Double) -> Void = { _ in }) throws {
        var albums = try albumDataRepository.fetchAll(from: "location")
        var albumPhotoMap: [UUID: [String]] = [:]
        var page = 0
        let totalCount = (try? photoDataRepository.fetchPhotoCount()) ?? 0

        while true {
            let photos = try photoDataRepository.fetchPhotos(page: page, pageSize: classificationPageSize)
            if photos.isEmpty { break }

            var addressCount: [String: [String]] = [:]
            for photo in photos {
                guard let address = photo.address, let (key, addressText) = addressKeyValue(address) else { continue }
                if !addressText.isEmpty && !addressCount[key, default: []].contains(addressText) {
                    addressCount[key, default: []].append(addressText)
                }
            }

            for (address, areas) in addressCount {
                let album = Album(
                    name: address,
                    displayName: address,
                    isAuto: true,
                    keywords: areas,
                    photoCount: 0,
                    from: "location"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    albums.append(saved)
                }
            }

            for album in albums {
                let matchedIdentifiers = photos
                    .filter {
                        if let address = $0.address, let (_, addressText) = addressKeyValue(address) {
                            return album.keywords.contains(addressText)
                        }
                        return false
                    }
                    .map { $0.localIdentifier }
                albumPhotoMap[album.id, default: []].append(contentsOf: matchedIdentifiers)
            }

            page += 1
            onProgress(scanRatio(processed: page * classificationPageSize, total: totalCount))
        }

        for (index, (albumId, photoIdentifiers)) in albumPhotoMap.enumerated() {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            onProgress(0.8 + 0.2 * Double(index + 1) / Double(albumPhotoMap.count))
        }
    }

    // 카테고리는 라벨이 필요해서 라벨 포함 조회로 처리
    private func createCategoryAlbumsCore(onProgress: (Double) -> Void = { _ in }) async throws {
        let ruleCategories: [String: AlbumRule] = try await photoCategoryRepository.fetchRuleCategories()
        var albums = try albumDataRepository.fetchAll(from: "category")
        var albumPhotoMap: [UUID: [String]] = [:]
        var page = 0
        let totalCount = (try? photoDataRepository.fetchPhotoCount()) ?? 0

        while true {
            let photos = try photoDataRepository.fetchAll(page: page, pageSize: classificationPageSize)
            if photos.isEmpty { break }

            for (albumName, rule) in ruleCategories {
                let matchedPhotos = photos.filter { matchesRule($0, rule: rule) }
                guard !matchedPhotos.isEmpty else { continue }

                let album = Album(
                    name: albumName,
                    displayName: albumName,
                    isAuto: true,
                    photoCount: 0,
                    from: "category"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    albums.append(saved)
                }
            }

            for album in albums {
                guard let rule = ruleCategories[album.name] else { continue }
                let matchedIdentifiers = photos
                    .filter { matchesRule($0, rule: rule) }
                    .map { $0.localIdentifier }
                albumPhotoMap[album.id, default: []].append(contentsOf: matchedIdentifiers)
            }

            page += 1
            onProgress(scanRatio(processed: page * classificationPageSize, total: totalCount))
        }

        for (index, (albumId, photoIdentifiers)) in albumPhotoMap.enumerated() {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            onProgress(0.8 + 0.2 * Double(index + 1) / Double(albumPhotoMap.count))
        }
    }

    // 분석하기용 증분 분류 — 아직 분류 안 된 사진만 날짜/주소/카테고리를 한 번에 처리하고 완료 표시한다
    // fullRegenerate면 완료 표시를 무시하고 전체를 offset으로 다시 훑는다
    private func classifyNewPhotosCore(fullRegenerate: Bool = false, onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let ruleCategories: [String: AlbumRule] = try await photoCategoryRepository.fetchRuleCategories()

        var dateAlbums = try albumDataRepository.fetchAll(from: "date")
        var locationAlbums = try albumDataRepository.fetchAll(from: "location")
        var categoryAlbums = try albumDataRepository.fetchAll(from: "category")

        var dateAlbumPhotoMap: [UUID: [String]] = [:]
        var locationAlbumPhotoMap: [UUID: [String]] = [:]
        var categoryAlbumPhotoMap: [UUID: [String]] = [:]

        // 총량을 아는 전체 재생성일 때만 진행률을 보고한다
        let totalCount = fullRegenerate ? ((try? photoDataRepository.fetchPhotoCount()) ?? 0) : 0
        debugLog("📅 [날짜/지역/카테고리] 시작 — fullRegenerate: \(fullRegenerate), 전체 \(totalCount)장")
        let classifyStartedAt = Date()

        var allProcessedIdentifiers: [String] = []
        var offset = 0
        while true {
            let photos = fullRegenerate
                ? try photoDataRepository.fetchAllForClassification(limit: classificationPageSize, offset: offset)
                : try photoDataRepository.fetchAlbumUnclassified(limit: classificationPageSize, offset: offset)
            if photos.isEmpty { break }

            // 날짜
            let years = Set(photos.compactMap { $0.year })
            for year in years {
                let album = Album(
                    name: year,
                    displayName: "\(year)",
                    isAuto: true,
                    keywords: ["\(year)", "\(year)년"],
                    photoCount: 0,
                    from: "date"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    dateAlbums.append(saved)
                }
            }
            for album in dateAlbums {
                let matched = photos
                    .filter { album.keywords.contains($0.year ?? "") }
                    .map { $0.localIdentifier }
                guard !matched.isEmpty else { continue }
                dateAlbumPhotoMap[album.id, default: []].append(contentsOf: matched)
            }

            // 주소
            var addressCount: [String: [String]] = [:]
            for photo in photos {
                guard let address = photo.address, let (key, addressText) = addressKeyValue(address) else { continue }
                if !addressText.isEmpty && !addressCount[key, default: []].contains(addressText) {
                    addressCount[key, default: []].append(addressText)
                }
            }
            for (address, areas) in addressCount {
                let album = Album(
                    name: address,
                    displayName: address,
                    isAuto: true,
                    keywords: areas,
                    photoCount: 0,
                    from: "location"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    locationAlbums.append(saved)
                }
            }
            for album in locationAlbums {
                let matched = photos
                    .filter {
                        if let address = $0.address, let (_, addressText) = addressKeyValue(address) {
                            return album.keywords.contains(addressText)
                        }
                        return false
                    }
                    .map { $0.localIdentifier }
                guard !matched.isEmpty else { continue }
                locationAlbumPhotoMap[album.id, default: []].append(contentsOf: matched)
            }

            // 카테고리
            for (albumName, rule) in ruleCategories {
                let matchedPhotos = photos.filter { matchesRule($0, rule: rule) }
                guard !matchedPhotos.isEmpty else { continue }

                let album = Album(
                    name: albumName,
                    displayName: albumName,
                    isAuto: true,
                    photoCount: 0,
                    from: "category"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    categoryAlbums.append(saved)
                }
            }
            for album in categoryAlbums {
                guard let rule = ruleCategories[album.name] else { continue }
                let matched = photos
                    .filter { matchesRule($0, rule: rule) }
                    .map { $0.localIdentifier }
                guard !matched.isEmpty else { continue }
                categoryAlbumPhotoMap[album.id, default: []].append(contentsOf: matched)
            }

            allProcessedIdentifiers.append(contentsOf: photos.map { $0.localIdentifier })
            offset += photos.count
            if fullRegenerate, totalCount > 0 {
                onProgress(min(Double(offset) / Double(totalCount) * 0.8, 0.8))
            }
            debugLog("📅 [날짜/지역/카테고리] 스캔 \(photos.count)장(누적 \(offset)/\(totalCount)) — 누적 \(String(format: "%.1f", Date().timeIntervalSince(classifyStartedAt)))초")
        }

        // 앨범마다 한 번에 모아서 쓴다. 완료 표시는 쓰기가 끝난 뒤에 해서 중간에 죽으면 다시 처리된다
        debugLog("📅 [날짜/지역/카테고리] 스캔 완료, 앨범에 쓰기 시작 — 날짜 \(dateAlbumPhotoMap.count)개/지역 \(locationAlbumPhotoMap.count)개/카테고리 \(categoryAlbumPhotoMap.count)개 앨범")
        for (albumId, photoIdentifiers) in dateAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("📅 [날짜] '\(dateAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        for (albumId, photoIdentifiers) in locationAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("📍 [지역] '\(locationAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        for (albumId, photoIdentifiers) in categoryAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("🏷️ [카테고리] '\(categoryAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        try photoDataRepository.markAlbumsGenerated(identifiers: allProcessedIdentifiers)
        if fullRegenerate { onProgress(1.0) }
        debugLog("📅 [날짜/지역/카테고리] 완료 — 총 \(String(format: "%.1f", Date().timeIntervalSince(classifyStartedAt)))초")
    }

    // 지역만 먼저 분류하는 패스 — 완료 표시는 카테고리 패스가 끝난 뒤에 한다
    private func classifyLocationOnlyCore(fullRegenerate: Bool = false) async throws {
        debugLog("📍 [지역 전용] 시작")
        let locationStartedAt = Date()
        var locationAlbums = try albumDataRepository.fetchAll(from: "location")
        var locationAlbumPhotoMap: [UUID: [String]] = [:]

        let allTargetPhotos = fullRegenerate
            ? try photoDataRepository.fetchAllForClassification(limit: Int.max, offset: 0)
            : try photoDataRepository.fetchAlbumUnclassified(limit: Int.max, offset: 0)

        for pageStart in stride(from: 0, to: allTargetPhotos.count, by: classificationPageSize) {
            let photos = Array(allTargetPhotos[pageStart..<min(pageStart + classificationPageSize, allTargetPhotos.count)])

            var addressCount: [String: [String]] = [:]
            for photo in photos {
                guard let address = photo.address, let (key, addressText) = addressKeyValue(address) else { continue }
                if !addressText.isEmpty && !addressCount[key, default: []].contains(addressText) {
                    addressCount[key, default: []].append(addressText)
                }
            }
            for (address, areas) in addressCount {
                let album = Album(
                    name: address,
                    displayName: address,
                    isAuto: true,
                    keywords: areas,
                    photoCount: 0,
                    from: "location"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    locationAlbums.append(saved)
                }
            }
            for album in locationAlbums {
                let matched = photos
                    .filter {
                        if let address = $0.address, let (_, addressText) = addressKeyValue(address) {
                            return album.keywords.contains(addressText)
                        }
                        return false
                    }
                    .map { $0.localIdentifier }
                guard !matched.isEmpty else { continue }
                locationAlbumPhotoMap[album.id, default: []].append(contentsOf: matched)
            }
            debugLog("📍 [지역 전용] \(photos.count)장 처리 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(locationStartedAt)))초")
        }

        for (albumId, photoIdentifiers) in locationAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("📍 [지역] '\(locationAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        debugLog("📍 [지역 전용] 완료 — 총 \(String(format: "%.1f", Date().timeIntervalSince(locationStartedAt)))초")
    }

    // 지역 다음에 도는 카테고리 패스 — 날짜 안전망도 같이 처리하고, 끝나면 분류 완료로 표시한다
    private func classifyCategoryAndFinalizeCore(fullRegenerate: Bool = false) async throws {
        debugLog("🏷️ [카테고리] 시작 — fullRegenerate: \(fullRegenerate)")
        let categoryStartedAt = Date()
        let ruleCategories: [String: AlbumRule] = try await photoCategoryRepository.fetchRuleCategories()

        var dateAlbums = try albumDataRepository.fetchAll(from: "date")
        var categoryAlbums = try albumDataRepository.fetchAll(from: "category")
        var dateAlbumPhotoMap: [UUID: [String]] = [:]
        var categoryAlbumPhotoMap: [UUID: [String]] = [:]
        var allProcessedIdentifiers: [String] = []
        var offset = 0

        while true {
            let photos = fullRegenerate
                ? try photoDataRepository.fetchAllForClassification(limit: classificationPageSize, offset: offset)
                : try photoDataRepository.fetchAlbumUnclassified(limit: classificationPageSize, offset: offset)
            if photos.isEmpty { break }

            let years = Set(photos.compactMap { $0.year })
            for year in years {
                let album = Album(
                    name: year,
                    displayName: "\(year)",
                    isAuto: true,
                    keywords: ["\(year)", "\(year)년"],
                    photoCount: 0,
                    from: "date"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    dateAlbums.append(saved)
                }
            }
            for album in dateAlbums {
                let matched = photos
                    .filter { album.keywords.contains($0.year ?? "") }
                    .map { $0.localIdentifier }
                guard !matched.isEmpty else { continue }
                dateAlbumPhotoMap[album.id, default: []].append(contentsOf: matched)
            }

            for (albumName, rule) in ruleCategories {
                let matchedPhotos = photos.filter { matchesRule($0, rule: rule) }
                guard !matchedPhotos.isEmpty else { continue }

                let album = Album(
                    name: albumName,
                    displayName: albumName,
                    isAuto: true,
                    photoCount: 0,
                    from: "category"
                )
                if let saved = try albumDataRepository.saveAlbum(album: album) {
                    categoryAlbums.append(saved)
                }
            }
            for album in categoryAlbums {
                guard let rule = ruleCategories[album.name] else { continue }
                let matched = photos
                    .filter { matchesRule($0, rule: rule) }
                    .map { $0.localIdentifier }
                guard !matched.isEmpty else { continue }
                categoryAlbumPhotoMap[album.id, default: []].append(contentsOf: matched)
            }

            allProcessedIdentifiers.append(contentsOf: photos.map { $0.localIdentifier })
            offset += photos.count
            debugLog("🏷️ [카테고리] 스캔 \(photos.count)장 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(categoryStartedAt)))초")
        }

        // 앨범마다 한 번에 모아서 쓴다
        debugLog("🏷️ [카테고리] 스캔 완료, 앨범에 쓰기 시작 — 날짜 \(dateAlbumPhotoMap.count)개/카테고리 \(categoryAlbumPhotoMap.count)개 앨범")
        for (albumId, photoIdentifiers) in dateAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("📅 [날짜] '\(dateAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        for (albumId, photoIdentifiers) in categoryAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("🏷️ [카테고리] '\(categoryAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        // 쓰기가 끝난 뒤에 표시 — 중간에 죽으면 다시 처리된다
        try photoDataRepository.markAlbumsGenerated(identifiers: allProcessedIdentifiers)
        debugLog("🏷️ [카테고리] 완료 — 총 \(String(format: "%.1f", Date().timeIntervalSince(categoryStartedAt)))초")
    }

    private func createFaceAlbumsCore(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        debugLog("🙂 [얼굴 앨범] 시작")
        let faceStartedAt = Date()
        try await faceClusterRepository.clusterAndSaveAlbums(onProgress: onProgress)
        try albumDataRepository.syncAlbums()
        debugLog("🙂 [얼굴 앨범] 완료 — \(String(format: "%.1f", Date().timeIntervalSince(faceStartedAt)))초")
    }

    private func createAnimalAlbumsCore(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        debugLog("🐾 [동물 앨범] 시작")
        let animalStartedAt = Date()
        try await animalClusterRepository.clusterAndSaveAlbums(onProgress: onProgress)
        try albumDataRepository.syncAlbums()
        debugLog("🐾 [동물 앨범] 완료 — \(String(format: "%.1f", Date().timeIntervalSince(animalStartedAt)))초")
    }

    /// 여행 앨범 생성 — 마지막 여행과 그 이후 사진만 다시 계산(여행 앨범이 없으면 전체)
    /// onProgress: 홈존 10% / 여행 후보 처리 70% / 앨범 저장 20%
    private func createTravelAlbumsCore(onProgress: (Double) -> Void = { _ in }) async throws {
        // 지난 재계산이 도중에 죽었으면 복구 경로로 처리한다
        if let pendingCheckpoint = try? await userDefaultRepository.fetchTravelAlbumCheckpoint() {
            try await resumeCrashedTravelAlbumRebuild(anchorDate: pendingCheckpoint.anchorDate)
            return
        }

        let existingTravelAlbums = try albumDataRepository.fetchAll(from: "travel")

        // 끝 날짜가 있는 여행 중 가장 최근 것만 다시 계산한다 — 없으면 전체
        let sortedByEndDate = existingTravelAlbums
            .compactMap { album -> (Album, Date)? in album.endDate.map { (album, $0) } }
            .sorted { $0.1 < $1.1 }
        let lastTravelAlbum = sortedByEndDate.last?.0
        // 체크포인트 기준점 — 이번에 안 건드리는 바로 이전 여행의 끝 날짜
        let safeAnchorForCheckpoint = sortedByEndDate.count >= 2 ? sortedByEndDate[sortedByEndDate.count - 2].1 : nil

        let targetPhotos: [PhotoLocationSnapshot]
        let albumIdToReplace: UUID?

        if let lastTravelAlbum, let lastEndDate = lastTravelAlbum.endDate {
            let existingPhotos = try albumDataRepository.fetchPhotos(by: lastTravelAlbum.id)
            // 마지막 여행 사진과 그 이후 좌표 사진을 같이 다시 묶어서, 이어지는 여행인지 새 여행인지 정한다
            let newPhotos = try photoDataRepository.fetchHasCoordinators()
                .filter { $0.createdAt > lastEndDate }
            guard !newPhotos.isEmpty else {
                return
            }
            targetPhotos = (existingPhotos + newPhotos).map { PhotoLocationSnapshot(from: $0) }
            albumIdToReplace = lastTravelAlbum.id
        } else {
            targetPhotos = try photoDataRepository.fetchHasCoordinators().map { PhotoLocationSnapshot(from: $0) }
            albumIdToReplace = nil
        }

        try analyzeIfNeeded()

        let homeZones = try fetchHomeZones()
        debugLog("🏠 이번 여행 판정에 사용되는 홈존 \(homeZones.count)개")
        for zone in homeZones {
            debugLog("   - \(zone.addressDescription(in: targetPhotos)) (분석일: \(zone.analyzedAt))")
        }
        onProgress(0.1)

        debugLog("🧳 [여행앨범] 감지 시작 — 대상 사진 \(targetPhotos.count)장")
        let travelDetectStartedAt = Date()
        let clusters = try await travelRepository.detect(from: targetPhotos, homeZones: homeZones) { ratio in
            onProgress(0.1 + 0.7 * ratio)
        }
        debugLog("🧳 [여행앨범] 감지 완료 — 클러스터 \(clusters.count)개, \(String(format: "%.1f", Date().timeIntervalSince(travelDetectStartedAt)))초")

        // 사용자가 편집한 마지막 여행은 지우지 않고 새 사진만 더한다
        if let lastTravelAlbum, let lastEndDate = lastTravelAlbum.endDate, albumIdToReplace != nil,
           lastTravelAlbum.isRenamed || lastTravelAlbum.coverPhotoManuallySet || lastTravelAlbum.isEdited {
            try await extendEditedTravelAlbum(lastTravelAlbum, lastEndDate: lastEndDate, clusters: clusters, existingTravelAlbums: existingTravelAlbums)
            return
        }

        // 삭제 → 재저장 중 죽으면 다음 실행에서 복구하도록 체크포인트를 남긴다
        try? await userDefaultRepository.beginTravelAlbumCheckpoint(anchorDate: safeAnchorForCheckpoint)

        if let albumIdToReplace {
            try albumDataRepository.delete(id: albumIdToReplace)
        } else {
            try albumDataRepository.deleteAutoAlbums(by: "travel")
        }

        // 내부 이름 "장소 N"이 기존 앨범과 겹치지 않게 번호를 이어서 매긴다
        var placeCounts = placeCounts(of: existingTravelAlbums.filter { $0.id != albumIdToReplace })

        try await saveTravelClusters(clusters, placeCounts: &placeCounts) { ratio in
            onProgress(0.8 + 0.2 * ratio)
        }

        try albumDataRepository.syncAlbums()
        try? await userDefaultRepository.clearTravelAlbumCheckpoint()
    }

    /// 여행 재계산이 도중에 죽었을 때 — 기준 날짜 이후 앨범을 지우고 그 구간을 다시 계산한다
    private func resumeCrashedTravelAlbumRebuild(anchorDate: Date?) async throws {
        let existingTravelAlbums = try albumDataRepository.fetchAll(from: "travel")
        for album in existingTravelAlbums {
            let endDate = album.endDate ?? .distantPast
            guard anchorDate == nil || endDate > anchorDate! else { continue }
            try albumDataRepository.delete(id: album.id)
        }

        let targetPhotos: [PhotoLocationSnapshot]
        if let anchorDate {
            let photosAfterAnchor = try photoDataRepository.fetchHasCoordinators()
                .filter { $0.createdAt > anchorDate }
            guard !photosAfterAnchor.isEmpty else {
                try? await userDefaultRepository.clearTravelAlbumCheckpoint()
                return
            }
            targetPhotos = photosAfterAnchor.map { PhotoLocationSnapshot(from: $0) }
        } else {
            targetPhotos = try photoDataRepository.fetchHasCoordinators().map { PhotoLocationSnapshot(from: $0) }
        }

        try analyzeIfNeeded()
        let homeZones = try fetchHomeZones()
        debugLog("🏠 [여행 앨범 복구] 이번 여행 판정에 사용되는 홈존 \(homeZones.count)개")

        debugLog("🧳 [여행앨범] 감지 시작 — 대상 사진 \(targetPhotos.count)장")
        let travelDetectStartedAt = Date()
        let clusters = try await travelRepository.detect(from: targetPhotos, homeZones: homeZones)
        debugLog("🧳 [여행앨범] 감지 완료 — 클러스터 \(clusters.count)개, \(String(format: "%.1f", Date().timeIntervalSince(travelDetectStartedAt)))초")

        // 기준 날짜 이전 앨범들의 "장소 N" 번호만 이어받는다
        let remainingAlbums = existingTravelAlbums.filter { album in
            guard let anchorDate else { return false }
            return (album.endDate ?? .distantPast) <= anchorDate
        }
        var placeCounts = placeCounts(of: remainingAlbums)

        try await saveTravelClusters(clusters, placeCounts: &placeCounts)

        try albumDataRepository.syncAlbums()
        try? await userDefaultRepository.clearTravelAlbumCheckpoint()
    }

    /// 여행 앨범 내부 이름 "장소 N"에서 장소별 다음 번호를 뽑는다 — 새 앨범 이름이 기존 앨범과 겹치지 않게
    private func placeCounts(of albums: [Album]) -> [String: Int] {
        var placeCounts: [String: Int] = [:]
        for album in albums {
            guard let lastSpaceIndex = album.name.lastIndex(of: " "),
                  let count = Int(album.name[album.name.index(after: lastSpaceIndex)...]) else { continue }
            let place = String(album.name[..<lastSpaceIndex])
            placeCounts[place] = max(placeCounts[place] ?? 0, count + 1)
        }
        return placeCounts
    }

    /// 편집된 마지막 여행 앨범 유지 — 이어지는 여행이면 끝 날짜 이후 사진만 더하고, 새 사진만 있으면 새 여행으로 저장
    private func extendEditedTravelAlbum(_ album: Album, lastEndDate: Date, clusters: [TravelCluster], existingTravelAlbums: [Album]) async throws {
        let albumPhotoIds = Set(try albumDataRepository.fetchPhotos(by: album.id).map { $0.localIdentifier })
        var newTripClusters: [TravelCluster] = []

        for cluster in clusters {
            guard cluster.photos.contains(where: { albumPhotoIds.contains($0.localIdentifier) }) else {
                newTripClusters.append(cluster)
                continue
            }
            // 좌표 없는 사진도 기간 안이면 같이 넣는다
            let periodPhotos = try photoDataRepository.fetchPhotos(from: lastEndDate, to: cluster.endDate)
            let addedIds = Set(cluster.photos.filter { $0.createdAt > lastEndDate }.map { $0.localIdentifier })
                .union(periodPhotos.filter { $0.createdAt > lastEndDate }.map { $0.localIdentifier })
            guard !addedIds.isEmpty else { continue }
            try albumDataRepository.addPhotos(albumId: album.id, photoIdentifiers: Array(addedIds))

            // 이름을 직접 안 바꿨으면 늘어난 기간에 맞춰 "나들이"/"여행"만 다시 정한다
            if !album.isRenamed,
               var updated = try albumDataRepository.fetchAlbum(id: album.id),
               let start = updated.startDate, let end = updated.endDate,
               let lastSpaceIndex = album.name.lastIndex(of: " ") {
                updated.displayName = TravelAlbumNaming.displayName(place: String(album.name[..<lastSpaceIndex]), startDate: start, endDate: end)
                try albumDataRepository.updateAlbum(album: updated)
            }
        }

        var placeCounts = placeCounts(of: existingTravelAlbums)
        try await saveTravelClusters(newTripClusters, placeCounts: &placeCounts)
        try albumDataRepository.syncAlbums()
    }

    /// 클러스터 결과를 여행 앨범으로 저장 — 정상 경로와 복구 경로가 같이 쓴다
    private func saveTravelClusters(
        _ clusters: [TravelCluster],
        placeCounts: inout [String: Int],
        onProgress: (Double) -> Void = { _ in }
    ) async throws {
        for (index, cluster) in clusters.enumerated() {
            defer { onProgress(Double(index + 1) / Double(clusters.count)) }
            // 하루짜리는 "나들이"
            let isSingleDay = Calendar.current.isDate(cluster.startDate, inSameDayAs: cluster.endDate)
            let duration = cluster.endDate.timeIntervalSince(cluster.startDate)
            // 3시간 이하 나들이는 건너뛴다
            if isSingleDay && duration <= 3 * 60 * 60 {
                continue
            }

            let place = TravelAlbumNaming.cleanAreaName(cluster.address, isoCode: cluster.isoCountryCode)

            let currentCount = placeCounts[place, default: 0]
            let albumName = "\(place) \(currentCount)"
            placeCounts[place] = currentCount + 1

            let displayName = TravelAlbumNaming.displayName(place: place, startDate: cluster.startDate, endDate: cluster.endDate)

            let album = Album(
                name: albumName,
                displayName: displayName,
                startDate: cluster.startDate,
                endDate: cluster.endDate,
                isAuto: true,
                coverPhotoIdentifier: cluster.photos.first?.localIdentifier,
                photoCount: cluster.photos.count,
                from: "travel"
            )
            if let saved = try albumDataRepository.saveAlbum(album: album, returnExist: true) {
                // 여행 기간 안의 사진은 좌표가 없어도 같이 넣는다
                let coordinatedIdentifiers = Set(cluster.photos.map { $0.localIdentifier })
                let periodPhotos = try photoDataRepository.fetchPhotos(from: cluster.startDate, to: cluster.endDate)
                let allIdentifiers = coordinatedIdentifiers.union(periodPhotos.map { $0.localIdentifier })
                try albumDataRepository.addPhotos(albumId: saved.id, photoIdentifiers: Array(allIdentifiers))
            }
        }
    }

    /// 여행 앨범마다 함께 찍힌 얼굴/동물 앨범을 다시 계산해서 덮어쓴다 — 여러 번 불러도 안전
    private func linkTravelersToTravelAlbumsCore() async throws {
        let travelAlbums = try albumDataRepository.fetchAll(from: "travel")
        guard !travelAlbums.isEmpty else {
            debugLog("🔗 [여행자 연결] 대상 여행 앨범 없음")
            return
        }
        debugLog("🔗 [여행자 연결] 시작 — 여행 앨범 \(travelAlbums.count)개")
        let linkStartedAt = Date()

        // 얼굴 앨범별 사진 id를 한 번만 만들어둔다
        let faceAlbums = try albumDataRepository.fetchAll(from: "face")
        let faceAlbumPhotoSets: [(id: UUID, photoIds: Set<String>)] = try faceAlbums.map { album in
            let photos = try albumDataRepository.fetchPhotos(by: album.id)
            return (album.id, Set(photos.map { $0.localIdentifier }))
        }

        let animalAlbums = try albumDataRepository.fetchAll(from: "animal")
        let animalAlbumPhotoSets: [(id: UUID, photoIds: Set<String>)] = try animalAlbums.map { album in
            let photos = try albumDataRepository.fetchPhotos(by: album.id)
            return (album.id, Set(photos.map { $0.localIdentifier }))
        }

        for travelAlbum in travelAlbums {
            let travelPhotoIds = Set(try albumDataRepository.fetchPhotos(by: travelAlbum.id).map { $0.localIdentifier })

            let linkedFaceAlbumIds = TravelerLinking.linkedAlbumIds(tripPhotoIds: travelPhotoIds, candidates: faceAlbumPhotoSets)
            try albumDataRepository.updateLinkedFaceAlbums(albumId: travelAlbum.id, faceAlbumIds: linkedFaceAlbumIds)

            let linkedAnimalAlbumIds = TravelerLinking.linkedAlbumIds(tripPhotoIds: travelPhotoIds, candidates: animalAlbumPhotoSets)
            try albumDataRepository.updateLinkedAnimalAlbums(albumId: travelAlbum.id, animalAlbumIds: linkedAnimalAlbumIds)
        }
        debugLog("🔗 [여행자 연결] 완료 — \(String(format: "%.1f", Date().timeIntervalSince(linkStartedAt)))초")
    }

    private func createSimilarAlbumsCore(
        from photos: [Photo],
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try self.albumDataRepository.deleteAutoAlbums(by: "similar")
        let similarAlbum = try albumDataRepository.fetchAll(from: "similar")
        try await similarRepository.clusterAndSaveAlbums(photos: photos, existingAlbums: similarAlbum, onProgress: onProgress)
        try albumDataRepository.syncAlbums()
    }

    // 분석하기용 증분 버전 — 아직 비교 안 한 새 사진만 시간 윈도우 안에서 비교한다
    // fullRegenerate면 비교 완료 표시를 무시하고 전체를 다시 비교한다
    private func updateSimilarAlbumsIncrementalCore(
        fullRegenerate: Bool = false,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let allPhotos = try photoDataRepository.fetchPhotos()
        let newPhotos = fullRegenerate ? allPhotos : try photoDataRepository.fetchSimilarUnchecked()
        guard !newPhotos.isEmpty else {
            debugLog("🪞 [비슷한 사진] 대상 없음")
            return
        }
        debugLog("🪞 [비슷한 사진] 시작 — 대상 \(newPhotos.count)장 / 전체 \(allPhotos.count)장")
        let similarStartedAt = Date()

        try await similarRepository.clusterNewPhotos(newPhotos: newPhotos, allPhotos: allPhotos, onProgress: onProgress)
        try photoDataRepository.markSimilarChecked(identifiers: newPhotos.map { $0.localIdentifier })
        debugLog("🪞 [비슷한 사진] 완료 — \(String(format: "%.1f", Date().timeIntervalSince(similarStartedAt)))초")
    }

    // MARK: - 여행 관련 함수

    // 홈존 재측정 — 증분 대상 일부가 아니라 전체 좌표 사진으로 본다
    private func analyzeIfNeeded() throws {
        // 자동 측정분 날짜로만 판단한다
        let existing = try homeZoneRepository.fetchHomeZones().filter { !$0.isManual }
        if let last = existing.first, Date().timeIntervalSince(last.analyzedAt) < HomeZoneDetection.reanalyzePeriod {
            debugLog("🏠 홈존 재분석 스킵 (마지막 분석: \(last.analyzedAt), 아직 3개월 안 지남)")
            return
        }
        try analyze(from: photoDataRepository.fetchHasCoordinators().map { PhotoLocationSnapshot(from: $0) })
    }

    // 강제 재분석
    private func analyze(from photos: [PhotoLocationSnapshot]) throws {
        let zones = HomeZoneDetection.zones(from: photos).map { zone -> HomeZone in
            var zone = zone
            zone.address = zone.nearestShortAddress(in: photos)
            return zone
        }

        debugLog("🏠 홈존 분석 결과 → \(zones.count)개")
        // 0개면 기존 홈존 유지
        guard !zones.isEmpty else { return }
        for zone in zones {
            debugLog("   - \(zone.address ?? zone.addressDescription(in: photos))")
        }

        try homeZoneRepository.replaceAutoHomeZones(zones)
    }

    // 홈존 목록 반환 (여행 필터링용)
    private func fetchHomeZones() throws -> [HomeZone] {
        try homeZoneRepository.fetchHomeZones()
    }

    // MARK: - 장소 관련 함수

    private func matchesRule(_ photo: Photo, rule: AlbumRule) -> Bool {
        // 1. 전체 태그 맵 생성 (이름 검색 속도 최적화 및 원본 점수 보존)
        let labelMap = Dictionary(uniqueKeysWithValues: photo.labels.map { ($0.name, $0.confidence) })

        // [검증 2] label_filters (특정 태그의 수치 범위 제한 검사 - minConfidence 제한을 받지 않음)
        if let filters = rule.labelFilters {
            let passed = filters.allSatisfy { filter in
                let score = labelMap[filter.name] ?? 0.0
                if let min = filter.min, score < min { return false }
                if let max = filter.max, score > max { return false }
                return true
            }
            if !passed { return false }
        }

        // [검증 3] 기준 점수(minConfidence) 이상을 기록한 유효 태그들만 추출
        let validLabels = Set(photo.labels
            .filter { $0.confidence >= rule.minConfidence }
            .map { $0.name }
        )

        guard !validLabels.isEmpty else { return false }

        // [검증 4] 타입별 매칭 (AND_OR_COMBINED vs OR)
        if rule.type == "AND_OR_COMBINED", let mustHaveList = rule.mustHaveOneOf {
            return !validLabels.isDisjoint(with: Set(mustHaveList))
                && !validLabels.isDisjoint(with: Set(rule.matchTags))
        } else {
            return !validLabels.isDisjoint(with: Set(rule.matchTags))
        }
    }

    private func addressKeyValue(_ address: PhotoLocation) -> (key: String, value: String)? {
        AddressGrouping.keyValue(for: address)
    }
}
