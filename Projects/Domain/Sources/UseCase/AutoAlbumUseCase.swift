//
//  AutoAlbumUseCase.swift
//  Domain
//
//  Created by sanghyeon on 3/22/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol AutoAlbumUseCase {
    /// fullRegenerate: true면 albumsGeneratedAt 플래그를 무시하고 전체 사진의 날짜/주소/카테고리를
    /// 다시 분류한다 — "자동 앨범 전체 재생성"처럼 앨범만 지우고 이 플래그는 그대로인 상황에서
    /// 날짜/주소/카테고리 앨범이 재생성되지 않는 문제를 피하기 위함
    func generateAllAlbums(fullRegenerate: Bool) -> AsyncThrowingStream<ProgressAlbum, Error>

    // MARK: - 점진적 앨범 노출용 (분석 진행 중 단계별로 호출)

    /// 날짜 앨범만 즉시 생성 — 사진 기본 스캔 직후, 라벨/지오코딩을 기다리지 않고 안전하게 부를 수
    /// 있다("이미 처리됨" 플래그를 안 건드리는 순수 추가 연산이라 나중에 분류가 다시 돌아도 안전).
    func createDateAlbumsEarly() async throws
    /// 영상만 모아두는 단일 앨범 — 라벨/좌표 안 기다리고 날짜 앨범과 같은 타이밍(기본 스캔 직후)에 생성
    func createVideoAlbumEarly() async throws
    /// 여행 앨범 생성(빈 여행자로) + 지역 앨범 분류 — 지오코딩(주소) 스트림이 끝나는 대로 부른다.
    /// 지역 분류는 주소 데이터만 있으면 되고 라벨을 안 써서, 라벨 스트림을 기다릴 필요가 없다.
    func createTravelAlbumsEarly() async throws
    /// 카테고리 앨범 분류(+날짜 안전망, "분류 완료" 표시까지) — 라벨+임베딩 스트림이 끝나는 대로,
    /// 얼굴/동물·중복탐지보다 먼저 부른다. 카테고리는 라벨만 있으면 되므로 그 둘을 기다릴 필요가 없다.
    func createCategoryAlbumsEarly() async throws
    /// 얼굴/동물 앨범 생성 + 여행자 연결 — 라벨+임베딩 스트림이 끝나는 대로, 카테고리 다음에 부른다.
    /// onProgress(0~1)는 얼굴/동물 앨범 생성 자체의 진행률만 나타낸다(여행자 연결은 빠른 patch
    /// 연산이라 별도 신호 없음).
    func createPersonAndSimilarAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// 중복(비슷한) 사진 탐지 — 전체 임베딩 추출 + 쌍대 비교가 대부분의 시간을 차지하는 "분석"의 일부로
    /// 취급한다(앨범 저장 자체는 이 호출 안에서 같이 끝나며 빠르다). 라벨 스트림이 끝나는 대로, 얼굴/동물
    /// 다음에 부른다 — 라벨/임베딩과 무관하게 독립적으로 자체 특징벡터를 추출하지만, "분석 완료"의
    /// 마지막 단계로 노출하기 위해 여기서 부른다.
    func detectDuplicatePhotos(onProgress: @escaping @Sendable (Double) -> Void) async throws

    // 개별 재생성 — onProgress는 각자 0~1
    func createDateAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createLocationAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createCategoryAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createFaceAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createAnimalAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func createTravelAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws
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

    // 날짜/주소/카테고리 분류 시 페이지 단위로 끊어서 처리 (전체를 한 번에 메모리에 올리면 사진이 많을 때 오래 걸림)
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

    /// 새로 분석된 사진만 대상으로 (날짜+주소+카테고리) → 얼굴 → 여행 → 비슷한사진 순으로 앨범을 갱신한다.
    /// 날짜/주소/카테고리는 아직 분류되지 않은 사진만, 비슷한사진은 시간 윈도우 안에서만 증분 처리한다.
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

                    // 여행 앨범이 "누가 포함되는지"(사람+동물)를 계산하려면 얼굴/동물 앨범이 먼저 만들어져 있어야 한다
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
            // for try await로 소비하던 쪽이 자기 Task가 취소돼서 중간에 소비를 그만두면 이 스트림도
            // 종료(termination)되는데, 그것만으로는 위 Task { ... }가 알아서 안 멈춘다(별개의 detached
            // Task라 밖에서 소비를 그만해도 자기가 취소됐다는 걸 모른다) — onTermination에서 명시적으로
            // task를 취소해서, 위 각 단계 사이의 checkCancellation()이 이걸 감지하고 실제로 멈추게 한다.
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
        // 지역 분류는 주소만 있으면 되고 라벨이 필요 없어서, 라벨 스트림을 기다리지 않고 여행 앨범
        // 바로 다음에 처리한다(둘 다 "주소 트랙"이 끝나야 의미 있는 작업이라 같이 묶었다).
        try await classifyLocationOnlyCore()
        // 얼굴/동물 앨범이 여행 앨범보다 먼저 끝났을 수 있어서 여기서도 여행자 연결 (반대 순서는 createPersonAndSimilarAlbums가 맡음)
        try await linkTravelersToTravelAlbumsCore()
        try albumDataRepository.syncAlbums()
        try await userDefaultRepository.saveLocationAnalyzedDate()
    }

    // 카테고리는 라벨만 있으면 되고 얼굴/동물 클러스터링이나 중복탐지 결과가 필요 없어서, 그 둘보다
    // 먼저 처리한다. classifyCategoryAndFinalizeCore가 날짜 안전망 처리 + markAlbumsGenerated로
    // "분류 완료" 표시까지 담당한다. 표시된 사진은 지역 패스가 못 보므로, 호출하는 쪽(TabbarViewModel)이
    // 여행+지역(createTravelAlbumsEarly)이 끝난 뒤에 이걸 부른다.
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
        // 여행 앨범이 얼굴/동물보다 먼저 만들어졌을 수 있어서, 방금 끝난 얼굴/동물 앨범 기준으로
        // 여행자 연결을 다시 채운다(이미 있으면 그대로, 여행 앨범이 아직 없으면 조용히 no-op).
        try await linkTravelersToTravelAlbumsCore()
    }

    // 중복(비슷한) 사진의 "전체 임베딩 추출 + 비교" 구간이 대부분의 시간을 차지해서 분석 게이지의
    // 일부로 노출한다 — 앨범 저장 자체는 이 함수 안에서 같이 끝나며 빠르므로 별도 신호가 필요 없다.
    public func detectDuplicatePhotos(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await updateSimilarAlbumsIncrementalCore(onProgress: onProgress)
    }

    // MARK: - 앨범 타입별 단독 재생성 (테스트/개별 재생성용)

    // "앨범 재생성" 버튼용 — 여행/비슷한사진과 동일하게, 해당 타입 앨범을 전부 지우고 나서 다시 만든다.
    // (generateAllAlbums()의 증분 경로는 이 함수들이 아니라 classifyNewPhotosCore/createFaceAlbumsCore를
    // 직접 쓰고 있어서, 여기서 삭제를 추가해도 이어서분석 흐름에는 영향이 없다)
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
        try albumDataRepository.syncAlbums()
    }

    public func createAnimalAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try self.albumDataRepository.deleteAutoAlbums(by: "animal")
        try await createAnimalAlbumsCore(onProgress: onProgress)
        try albumDataRepository.syncAlbums()
    }

    public func createSimilarAlbum(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let allPhotos = try photoDataRepository.fetchPhotos()
        try await createSimilarAlbumsCore(from: allPhotos, onProgress: onProgress)
    }

    public func createTravelAlbums(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await createTravelAlbumsCore(onProgress: onProgress)
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

    // 라벨이 필요 없는 분류(날짜/주소)는 라벨을 실어오지 않는 가벼운 fetchPhotos로 페이지 단위 처리
    /// 개별 재생성 진행률 중 페이지 스캔 몫 — 스캔 80% / 앨범에 쓰기 20%
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

    // 영상은 라벨/카테고리/얼굴/동물/중복탐지 대상이 아니라서 별도 규칙 매칭 없이 "영상" 단일 앨범
    // 하나에 그냥 다 모은다 — saveAlbum(returnExist: true)라 이미 있으면 그 앨범에 새 영상만 이어붙임
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

    // 카테고리는 라벨이 필요해서 fetchAll(라벨 포함)로 페이지 단위 처리
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

    // generateAllAlbums()에서만 쓰는 증분 버전 — 아직 date/category/location 분류를 거치지 않은 사진만
    // fetchAlbumUnclassified로 가져와서 세 종류를 한 번에 처리하고, 처리한 사진은 markAlbumsGenerated로 표시한다.
    // (재생성 테스트 버튼용 createDateAlbums 등은 이 메서드를 쓰지 않고 위의 전체 재계산 버전을 그대로 사용한다.)
    // fullRegenerate가 true면 "이미 분류됨" 플래그를 무시하고 전체 사진을 offset 페이지네이션으로 다시 훑는다 —
    // "자동 앨범 재생성" 버튼이 날짜/주소/카테고리 앨범을 지워도 이 플래그는 그대로 남아있어서 아무것도
    // 다시 안 만들어지는 문제 때문에 필요. 전체 사진을 nil로 리셋하는 대신 이 조회 방식만 바꾸는 쪽이
    // 불필요한 전체 테이블 갱신 없이 같은 결과를 낸다.
    private func classifyNewPhotosCore(fullRegenerate: Bool = false, onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let ruleCategories: [String: AlbumRule] = try await photoCategoryRepository.fetchRuleCategories()

        var dateAlbums = try albumDataRepository.fetchAll(from: "date")
        var locationAlbums = try albumDataRepository.fetchAll(from: "location")
        var categoryAlbums = try albumDataRepository.fetchAll(from: "category")

        var dateAlbumPhotoMap: [UUID: [String]] = [:]
        var locationAlbumPhotoMap: [UUID: [String]] = [:]
        var categoryAlbumPhotoMap: [UUID: [String]] = [:]

        // 전체 재생성일 때만 전체 사진 수를 알 수 있어서(증분 경로는 "아직 안 된 것만" 조회라 총량을 모름)
        // 그때만 페이지 단위로 진행률을 보고한다 — 안 그러면 이 단계는 끝날 때까지 진행률 표시가 안 움직인다
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

        // 스캔이 끝난 뒤 앨범마다 한 번씩만 모아서 쓴다 — 페이지마다 쓰면 그때마다 그 앨범의 기존 사진
        // 배열 전체를 다시 건드려서 앨범이 커질수록 느려진다. 완료 표시는 쓰기가 다 끝난 뒤에 해서, 중간에
        // 죽으면 다음 실행에서 처음부터 다시 처리된다(addPhotos가 중복을 걸러서 안전).
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

    // classifyPhotosFinal()에서만 쓰는, 진행률 표시를 위해 지역만 먼저 분류하는 패스 — 카테고리 패스가
    // 끝난 뒤에만 markAlbumsGenerated로 "처리 완료"를 표시하므로(classifyCategoryAndFinalizeCore 참고),
    // 이 패스만 끝나고 앱이 죽어도 다음 실행에서 지역+카테고리가 다시 시도된다.
    private func classifyLocationOnlyCore(fullRegenerate: Bool = false) async throws {
        debugLog("📍 [지역 전용] 시작")
        let locationStartedAt = Date()
        var locationAlbums = try albumDataRepository.fetchAll(from: "location")
        var locationAlbumPhotoMap: [UUID: [String]] = [:]

        // 이 패스는 markAlbumsGenerated를 안 부른다(카테고리 패스가 끝난 뒤에만 최종 표시하려고 일부러
        // 미룸, classifyCategoryAndFinalizeCore 참고). 대상 목록은 한 번만 통째로 가져오고, 페이지
        // 분할은 메모리 안에서만 한다.
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

    // classifyPhotosFinal()에서만 쓰는, 지역 패스 다음에 도는 카테고리 패스 — 날짜는 createDateAlbumsEarly로
    // 대부분 이미 처리됐겠지만 그 이후 추가된 사진을 위한 안전망으로 여기서도 같이 처리한다(addPhotos가
    // dedup이라 중복 호출해도 안전). 지역+날짜+카테고리가 전부 끝난 이 시점에만 markAlbumsGenerated로
    // "처리 완료"를 표시한다.
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

        // 스캔이 끝난 뒤 앨범마다 한 번씩만 모아서 쓴다 — classifyNewPhotosCore와 같은 이유
        debugLog("🏷️ [카테고리] 스캔 완료, 앨범에 쓰기 시작 — 날짜 \(dateAlbumPhotoMap.count)개/카테고리 \(categoryAlbumPhotoMap.count)개 앨범")
        for (albumId, photoIdentifiers) in dateAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("📅 [날짜] '\(dateAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        for (albumId, photoIdentifiers) in categoryAlbumPhotoMap {
            try albumDataRepository.addPhotos(albumId: albumId, photoIdentifiers: photoIdentifiers)
            debugLog("🏷️ [카테고리] '\(categoryAlbums.first { $0.id == albumId }?.displayName ?? albumId.uuidString)'에 \(photoIdentifiers.count)장 추가")
        }
        // 쓰기가 다 끝난 뒤에 표시 — 중간에 죽으면 다음 실행에서 처음부터 다시 처리된다
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

    /// onProgress: 홈존 10% / 여행 후보 처리 70% / 앨범 저장 20% (편집된 마지막 여행을 이어붙이는 경로는 저장 몫 생략)
    private func createTravelAlbumsCore(onProgress: (Double) -> Void = { _ in }) async throws {
        // 지난 실행이 "삭제 → 재클러스터링 → 재저장" 도중에 죽었으면(체크포인트가 남아있으면), 여기
        // DB에 남아있는 여행 앨범 상태를 못 믿는다 — 별도 복구 경로로 처리한다.
        if let pendingCheckpoint = try? await userDefaultRepository.fetchTravelAlbumCheckpoint() {
            try await resumeCrashedTravelAlbumRebuild(anchorDate: pendingCheckpoint.anchorDate)
            return
        }

        let existingTravelAlbums = try albumDataRepository.fetchAll(from: "travel")

        // 끝난 날짜(endDate)를 아는 여행 앨범(=이 증분 로직 도입 이후 만들어진 앨범)을 최신순으로 정렬 —
        // 가장 최근 것만 갱신 대상으로 삼는다. 새 사진이 추가된다고 몇 달 전 여행까지 통째로 다시 만들
        // 필요는 없다. 하나도 없으면(최초 실행이거나, endDate가 비어있던 예전 앨범만 있는 경우) 안전하게
        // 전체를 다시 훑는다 — 이번에 새로 저장되는 앨범부터는 startDate/endDate가 채워지므로 다음
        // 실행부터는 자연스럽게 증분 경로를 타게 된다.
        let sortedByEndDate = existingTravelAlbums
            .compactMap { album -> (Album, Date)? in album.endDate.map { (album, $0) } }
            .sorted { $0.1 < $1.1 }
        let lastTravelAlbum = sortedByEndDate.last?.0
        // 체크포인트에 남길 안전 기준점 — 지금 재계산 대상(곧 삭제될) lastTravelAlbum이 아니라, 그
        // 바로 이전(이번에 안 건드리는) 여행 앨범의 끝 날짜. 없으면(여행 앨범이 0~1개뿐이면) nil.
        let safeAnchorForCheckpoint = sortedByEndDate.count >= 2 ? sortedByEndDate[sortedByEndDate.count - 2].1 : nil

        let targetPhotos: [PhotoLocationSnapshot]
        let albumIdToReplace: UUID?

        if let lastTravelAlbum, let lastEndDate = lastTravelAlbum.endDate {
            let existingPhotos = try albumDataRepository.fetchPhotos(by: lastTravelAlbum.id)
            // 마지막 여행 이후, 좌표는 있는데 아직 어느 여행 앨범에도 안 들어간 사진만 새로 본다.
            // 이 사진들이 마지막 여행에 이어지는지 아니면 아직 만들어지지 않은 새 여행인지는 아래
            // detect()가 마지막 여행의 기존 사진들과 "같이" 재클러스터링해서 알아서 판단하게 둔다.
            let newPhotos = try photoDataRepository.fetchHasCoordinators()
                .filter { $0.createdAt > lastEndDate }
            guard !newPhotos.isEmpty else {
                // 마지막 여행 이후로 새로 좌표가 붙은 사진이 없으면 다시 계산할 게 없다
                return
            }
            targetPhotos = (existingPhotos + newPhotos).map { PhotoLocationSnapshot(from: $0) }
            albumIdToReplace = lastTravelAlbum.id
        } else {
            targetPhotos = try photoDataRepository.fetchHasCoordinators().map { PhotoLocationSnapshot(from: $0) }
            albumIdToReplace = nil
        }

        // 홈존 만들기
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

        // 사용자가 손댄(이름/대표사진 변경, 병합, 사진 빼기) 마지막 여행은 지우고 다시 만들면 편집이 날아간다 —
        // 지우지 않고 이어지는 새 사진만 더한다
        if let lastTravelAlbum, let lastEndDate = lastTravelAlbum.endDate, albumIdToReplace != nil,
           lastTravelAlbum.isRenamed || lastTravelAlbum.coverPhotoManuallySet || lastTravelAlbum.isEdited {
            try await extendEditedTravelAlbum(lastTravelAlbum, lastEndDate: lastEndDate, clusters: clusters, existingTravelAlbums: existingTravelAlbums)
            return
        }

        // 여기서부터 삭제 → 재저장이 시작된다 — 이 사이에 앱이 죽으면 다음 실행이 safeAnchorForCheckpoint
        // 기준으로 안전하게 복구할 수 있도록 체크포인트를 남긴다(성공하면 맨 끝에서 지운다)
        try? await userDefaultRepository.beginTravelAlbumCheckpoint(anchorDate: safeAnchorForCheckpoint)

        if let albumIdToReplace {
            try albumDataRepository.delete(id: albumIdToReplace)
        } else {
            try albumDataRepository.deleteAutoAlbums(by: "travel")
        }

        // 다른(이번에 안 건드리는) 여행 앨범과 내부 식별용 name이 겹치지 않도록, 기존 앨범들의
        // "장소 N" 카운트를 먼저 읽어와 이어서 매긴다 — 안 그러면 saveAlbum(returnExist: true)이
        // 이름이 겹치는 엉뚱한 기존 앨범에 이번 사진들을 잘못 합쳐버릴 수 있다.
        var placeCounts = placeCounts(of: existingTravelAlbums.filter { $0.id != albumIdToReplace })

        try await saveTravelClusters(clusters, placeCounts: &placeCounts) { ratio in
            onProgress(0.8 + 0.2 * ratio)
        }

        try albumDataRepository.syncAlbums()
        try? await userDefaultRepository.clearTravelAlbumCheckpoint()
    }

    /// 지난 실행이 여행 앨범 재계산(삭제 → 재클러스터링 → 재저장) 도중 죽었을 때의 복구 경로.
    /// anchorDate(그 이전까지는 안전하다고 기록해둔 기준점) 이후에 남아있는 여행 앨범은 그 실패한
    /// 시도가 절반쯤 저장해놓은 부산물일 수 있으므로 먼저 정리하고, anchorDate 이후 구간을 통째로
    /// 다시 그러모아 재계산한다(개별 앨범이 아니라 날짜 범위로 다시 모으므로, 그 앨범이 이미 지워졌어도
    /// 안전하게 동작한다).
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

        // anchorDate 이후 앨범은 위에서 이미 다 지웠으므로 추가로 지울 게 없다 — anchorDate 이전(안전한)
        // 앨범들의 "장소 N" 카운트만 이어받는다
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

    /// 편집된 마지막 여행 앨범을 유지한 채 갱신 — 그 앨범 사진이 섞인 클러스터는 "이어지는 여행"으로 보고
    /// 끝 날짜 이후 사진만 더하고(사용자가 뺀 예전 사진은 안 돌아옴), 새 사진만으로 된 클러스터는 새 여행으로 저장한다
    private func extendEditedTravelAlbum(_ album: Album, lastEndDate: Date, clusters: [TravelCluster], existingTravelAlbums: [Album]) async throws {
        let albumPhotoIds = Set(try albumDataRepository.fetchPhotos(by: album.id).map { $0.localIdentifier })
        var newTripClusters: [TravelCluster] = []

        for cluster in clusters {
            guard cluster.photos.contains(where: { albumPhotoIds.contains($0.localIdentifier) }) else {
                newTripClusters.append(cluster)
                continue
            }
            // 좌표 없는 사진도 기간 안이면 같이 넣는 건 saveTravelClusters와 같은 규칙
            let periodPhotos = try photoDataRepository.fetchPhotos(from: lastEndDate, to: cluster.endDate)
            let addedIds = Set(cluster.photos.filter { $0.createdAt > lastEndDate }.map { $0.localIdentifier })
                .union(periodPhotos.filter { $0.createdAt > lastEndDate }.map { $0.localIdentifier })
            guard !addedIds.isEmpty else { continue }
            try albumDataRepository.addPhotos(albumId: album.id, photoIdentifiers: Array(addedIds))

            // 이름을 직접 안 바꿨으면 기간이 늘어난 데 맞춰 "나들이"/"여행"만 다시 정한다
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

    /// 클러스터링 결과를 여행 앨범으로 저장하는 공통 로직 — 정상 경로/체크포인트 복구 경로가 같이 쓴다
    private func saveTravelClusters(
        _ clusters: [TravelCluster],
        placeCounts: inout [String: Int],
        onProgress: (Double) -> Void = { _ in }
    ) async throws {
        for (index, cluster) in clusters.enumerated() {
            defer { onProgress(Double(index + 1) / Double(clusters.count)) }
            // 하루짜리 여행은 "여행"보다 "나들이"가 더 자연스럽다 (출발/도착 구분이 무의미한 짧은 일정)
            let isSingleDay = Calendar.current.isDate(cluster.startDate, inSameDayAs: cluster.endDate)
            let duration = cluster.endDate.timeIntervalSince(cluster.startDate)
            // 3시간 이하의 짧은 나들이는 앨범으로 묶을 만큼 의미 있는 일정이 아니라고 보고 건너뛴다
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
                // 좌표 기반으로 뽑힌 사진들 외에, 이 여행 기간(시작~끝, 양끝 포함) 안에 있는 사진은
                // 좌표 유무 상관없이 전부 같이 넣는다 — 비행기모드/실내 등으로 위치 정보가 안 붙은
                // 사진도 여행 기간 안이면 놓치지 않기 위함. addPhotos는 중복 추가에 안전하다.
                let coordinatedIdentifiers = Set(cluster.photos.map { $0.localIdentifier })
                let periodPhotos = try photoDataRepository.fetchPhotos(from: cluster.startDate, to: cluster.endDate)
                let allIdentifiers = coordinatedIdentifiers.union(periodPhotos.map { $0.localIdentifier })
                try albumDataRepository.addPhotos(albumId: saved.id, photoIdentifiers: Array(allIdentifiers))
            }
        }
    }

    /// 여행 앨범들에 얼굴/동물 앨범 연결 정보를 채운다(또는 다시 채운다) — 얼굴/동물 클러스터링이
    /// 여행 앨범 생성보다 늦게 끝나는 경우를 위해 별도 단계로 분리했다. 여러 번 불러도 안전하다
    /// (매번 다시 계산해서 덮어쓰는 단순 patch라 중복/누락 걱정 없음).
    private func linkTravelersToTravelAlbumsCore() async throws {
        let travelAlbums = try albumDataRepository.fetchAll(from: "travel")
        guard !travelAlbums.isEmpty else {
            debugLog("🔗 [여행자 연결] 대상 여행 앨범 없음")
            return
        }
        debugLog("🔗 [여행자 연결] 시작 — 여행 앨범 \(travelAlbums.count)개")
        let linkStartedAt = Date()

        // 얼굴 앨범들의 사진 id 집합을 미리 한 번만 만들어둔다 — 여행 앨범마다 매번 다시 조회하지 않도록.
        // "누가 포함되는지"는 이 시점에 고정되고(재생성해야 갱신), 그 사람 이름은 항상 얼굴 앨범을
        // 다시 조회해서 보여주므로 나중에 이름을 바꿔도 자동으로 반영된다
        let faceAlbums = try albumDataRepository.fetchAll(from: "face")
        let faceAlbumPhotoSets: [(id: UUID, photoIds: Set<String>)] = try faceAlbums.map { album in
            let photos = try albumDataRepository.fetchPhotos(by: album.id)
            return (album.id, Set(photos.map { $0.localIdentifier }))
        }

        // 반려동물도 "이 여행에 함께 있었는지" 같은 방식으로 연결한다
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

    // generateAllAlbums()에서만 쓰는 증분 버전 — 아직 비교하지 않은 새 사진만 시간 윈도우 기준으로 처리하고,
    // 기존 비슷한사진 앨범은 삭제하지 않는다 (createSimilarAlbum()은 재생성 테스트 버튼용으로 위 전체 재계산 버전을 그대로 씀).
    // fullRegenerate가 true면(자동 앨범 재생성 — 이 시점엔 이미 "similar" 앨범이 전부 삭제된 상태)
    // "이미 비교함" 플래그를 무시하고 전체 사진을 다시 비교 대상으로 삼는다 — 안 그러면 이미 체크된
    // 사진들만 있어서 newPhotos가 비어 그냥 아무 것도 안 만들어지고 끝나버린다(중복 앨범이 재생성
    // 후에는 하나도 안 생기던 버그의 원인).
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

    // 홈존 분석 필요 여부 체크 후 실행
    // 여행 판정 대상(증분이면 일부 사진뿐)이 아니라 전체 좌표 사진으로 본다 — 일부만 보면 홈존이 0개로 나와 기존 홈존을 지워버림
    private func analyzeIfNeeded() throws {
        let existing = try homeZoneRepository.fetchHomeZones()
        if let last = existing.first, Date().timeIntervalSince(last.analyzedAt) < HomeZoneDetection.reanalyzePeriod {
            debugLog("🏠 홈존 재분석 스킵 (마지막 분석: \(last.analyzedAt), 아직 3개월 안 지남)")
            return
        }
        try analyze(from: photoDataRepository.fetchHasCoordinators().map { PhotoLocationSnapshot(from: $0) })
    }

    // 강제 재분석
    private func analyze(from photos: [PhotoLocationSnapshot]) throws {
        let zones = HomeZoneDetection.zones(from: photos)

        debugLog("🏠 홈존 분석 결과 → \(zones.count)개")
        // 0개면 기존 홈존을 유지 — 지우면 이후 동네 사진이 전부 여행으로 잡힌다
        guard !zones.isEmpty else { return }
        for zone in zones {
            debugLog("   - \(zone.addressDescription(in: photos))")
        }

        try homeZoneRepository.saveHomeZones(zones)
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
