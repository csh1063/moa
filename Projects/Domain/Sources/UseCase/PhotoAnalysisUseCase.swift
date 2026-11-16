//
//  PhotoAnalysisUseCase.swift
//  Domain
//
//  Created by sanghyeon on 3/17/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol PhotoAnalysisUseCase {
    /// 라벨+얼굴/동물 임베딩 스트림과 주소(지오코딩) 스트림은 내부적으로 이미 동시에 돈다 — 이 둘은
    /// 하나로 합쳐진 진행률만 밖으로 나가서, 호출자는 "지오코딩만 끝났다"/"라벨만 끝났다"를 구분할
    /// 방법이 없었다. 두 콜백은 각 스트림이 (성공이든, 주소 쪽은 실패를 삼키고든) 끝나는 시점에 정확히
    /// 한 번씩 불려서, 호출자가 그 시점에 맞춰 관련 앨범 생성을 조기에 트리거할 수 있게 한다.
    func analysis(
        onBasicScanCompleted: @escaping @Sendable () -> Void,
        onAddressStreamCompleted: @escaping @Sendable () -> Void,
        onLabelStreamCompleted: @escaping @Sendable () -> Void
    ) -> AsyncThrowingStream<ProgressAnalysis, Error>
    /// 분석된 사진이 하나도 없음 — 처음 쓰거나 초기화한 뒤. 개수만 세서 바로 끝난다
    func isFirstAnalysis() throws -> Bool
    /// 분석 시작 안내용 — 이번에 분석할 사진 수(영상 제외)와 예상 시간. 사진첩 전체를 훑어서 시간이 걸린다
    func estimate() async throws -> AnalysisEstimate
    /// 분석이 끝난 뒤 실제 걸린 시간으로 이 기기의 장당 속도를 저장한다 — 다음 안내의 예상 시간에 쓴다
    func recordAnalysisDuration(_ seconds: TimeInterval, photoCount: Int) async throws
}

public struct AnalysisEstimate {
    public let photoCount: Int
    public let estimatedSeconds: TimeInterval

    /// 아직 이 기기에서 잰 적 없을 때의 장당 시간 — 디버그 빌드 실측(13,000장 43분, 0.2초)보다 출시 빌드가 빠를 걸 감안
    static let defaultSecondsPerPhoto: Double = 0.15
    /// 이보다 적게 분석한 결과는 저장하지 않는다 — 앨범 생성 같은 고정 시간이 장당 시간을 크게 부풀린다
    static let minimumSampleCount = 300

    static func estimatedSeconds(photoCount: Int, savedSecondsPerPhoto: Double?) -> TimeInterval {
        Double(photoCount) * (savedSecondsPerPhoto ?? defaultSecondsPerPhoto)
    }
}

extension PhotoAnalysisUseCase {
    public func analysis() -> AsyncThrowingStream<ProgressAnalysis, Error> {
        analysis(onBasicScanCompleted: {}, onAddressStreamCompleted: {}, onLabelStreamCompleted: {})
    }
}

public final class DefaultPhotoAnalysisUseCase: PhotoAnalysisUseCase {

    private let libraryRepository: PhotoLibraryRepository
    private let analysisRepository: PhotoAnalysisRepository
    private let dataRepository: PhotoDataRepository
    private let geoRepository: GeoRepository
    private let userDefaultRepository: UserDefaultRepository

    // 라벨+얼굴 분석과 주소 변환을 동시에 진행할 때의 진행률 가중치 — 분석 게이지 전체(100%) 중
    // 이 둘이 차지하는 85%(지오코딩30/라벨55) 안에서의 상대 비율이다. 나머지 15%(날짜5 + 중복탐지10)는
    // TabbarViewModel이 이 스트림 바깥에서 더한다.
    private let labelWeight: Double = 55.0 / 85.0
    private let addressWeight: Double = 30.0 / 85.0

    public init(
        libraryRepository: PhotoLibraryRepository,
        analysisRepository: PhotoAnalysisRepository,
        dataRepository: PhotoDataRepository,
        geoRepository: GeoRepository,
        userDefaultRepository: UserDefaultRepository
    ) {
        self.libraryRepository = libraryRepository
        self.analysisRepository = analysisRepository
        self.dataRepository = dataRepository
        self.geoRepository = geoRepository
        self.userDefaultRepository = userDefaultRepository
    }

    public func isFirstAnalysis() throws -> Bool {
        try dataRepository.fetchAnalyzedCount() == 0
    }

    public func estimate() async throws -> AnalysisEstimate {
        let analyzedIds = Set(try dataRepository.fetchAnalyzed())
        let photoCount = try await libraryRepository.fetchImageIds().filter { !analyzedIds.contains($0) }.count
        let saved = try await userDefaultRepository.fetchAnalysisSecondsPerPhoto()
        return AnalysisEstimate(
            photoCount: photoCount,
            estimatedSeconds: AnalysisEstimate.estimatedSeconds(photoCount: photoCount, savedSecondsPerPhoto: saved)
        )
    }

    public func recordAnalysisDuration(_ seconds: TimeInterval, photoCount: Int) async throws {
        guard photoCount >= AnalysisEstimate.minimumSampleCount, seconds > 0 else { return }
        try await userDefaultRepository.saveAnalysisSecondsPerPhoto(seconds / Double(photoCount))
    }

    // 사진 기본 정보 저장 → 라벨+얼굴 분석과 주소 변환 동시 진행 (4:1 가중 진행률)
    public func analysis(
        onBasicScanCompleted: @escaping @Sendable () -> Void,
        onAddressStreamCompleted: @escaping @Sendable () -> Void,
        onLabelStreamCompleted: @escaping @Sendable () -> Void
    ) -> AsyncThrowingStream<ProgressAnalysis, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await saveAllPhotosBase()
                    onBasicScanCompleted()

                    let combiner = ProgressCombiner(labelWeight: labelWeight, addressWeight: addressWeight)

                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { [weak self] in
                            guard let self else { return }
                            for try await progress in self.labelAndFaceStream() {
                                switch progress.state {
                                case .progress(let ratio):
                                    let combined = await combiner.updateLabel(ratio)
                                    continuation.yield(ProgressAnalysis(photo: progress.photo, state: .progress(combined)))
                                case .completed:
                                    let combined = await combiner.updateLabel(1.0)
                                    continuation.yield(ProgressAnalysis(photo: progress.photo, state: .progress(combined)))
                                case .unavailable(let reason):
                                    continuation.yield(ProgressAnalysis(photo: progress.photo, state: .unavailable(reason: reason)))
                                }
                            }
                            onLabelStreamCompleted()
                        }
                        group.addTask { [weak self] in
                            guard let self else { return }
                            // 주소(네트워크) 분석이 실패해도 라벨/얼굴 분석과 앨범 생성은 계속 진행돼야 한다 —
                            // 여기서 던지면 group.waitForAll()이 통째로 실패해서 아래 앨범 생성 자체가 안 불린다
                            do {
                                for try await progress in self.addressStream() {
                                    switch progress.state {
                                    case .progress(let ratio):
                                        let combined = await combiner.updateAddress(ratio)
                                        continuation.yield(ProgressAnalysis(photo: progress.photo, state: .progress(combined)))
                                    case .completed:
                                        let combined = await combiner.updateAddress(1.0)
                                        continuation.yield(ProgressAnalysis(photo: progress.photo, state: .progress(combined)))
                                    case .unavailable(let reason):
                                        continuation.yield(ProgressAnalysis(photo: progress.photo, state: .unavailable(reason: reason)))
                                    }
                                }
                            } catch {
                                debugLog("⚠️ 주소 분석 실패, 무시하고 계속 진행: \(error)")
                                _ = await combiner.updateAddress(1.0)
                            }
                            onAddressStreamCompleted()
                        }
                        try await group.waitForAll()
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    /// 라이브러리 전체 사진의 기본 메타데이터(id/createdAt/lat/lng/year/month)를 분석 전에 미리 저장
    private func saveAllPhotosBase() async throws {
        let allPhotos = try await libraryRepository.fetchPhotos()
        let photos = allPhotos.photos.map { item -> Photo in
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
        try dataRepository.saveAllPhotosBase(photos)
    }

    // 라벨 + 얼굴 임베딩 분석
    private func labelAndFaceStream() -> AsyncThrowingStream<ProgressAnalysis, Error> {
        execute { [weak self] in
            guard let self else { throw PhotoRepositoryError.photoNotFound }
            let analyzedIds: [String] = try self.dataRepository.fetchAnalyzed()
            return self.analysisRepository.analyze(excludingIds: analyzedIds)
        }
    }

    // 주소 변환
    private func addressStream() -> AsyncThrowingStream<ProgressAnalysis, Error> {
        execute { [weak self] in
            AsyncThrowingStream { continuation in
                Task.detached(priority: .userInitiated) {
                    do {
                        guard let self else { throw PhotoRepositoryError.photoNotFound }

                        let unanalyzedPhotos = try self.dataRepository.fetchLocationUnanalyzed()

                        var koreaPhotos: [Photo] = []
                        var etcPhotos: [Photo] = []
                        var noCodePhotos: [Photo] = []
                        for unanalyzedPhoto in unanalyzedPhotos {
                            if let latitude = unanalyzedPhoto.latitude,
                               let longitude = unanalyzedPhoto.longitude {
                                if self.isKorea(latitude: latitude, longitude: longitude) {
                                    koreaPhotos.append(unanalyzedPhoto)
                                } else {
                                    etcPhotos.append(unanalyzedPhoto)
                                }
                            }
                        }

                        let total = koreaPhotos.count + etcPhotos.count

                        // 한국 주소 — 실패해도 외국 주소 조회는 이어서 시도해야 한다
                        let koreaAddress: [String: PhotoLocation]
                        do {
                            koreaAddress = try await self.geoRepository.locationToaddress(koreaPhotos)
                        } catch {
                            debugLog("⚠️ 한국 주소 조회 실패, 무시하고 계속 진행: \(error)")
                            koreaAddress = [:]
                        }

                        var index: Double = 0
                        for koreaPhoto in koreaPhotos {
                            if let address = koreaAddress[koreaPhoto.localIdentifier] {

                                index += 1
                                continuation.yield(
                                    ProgressAnalysis(
                                        photo: Photo(
                                            localIdentifier: koreaPhoto.localIdentifier,
                                            createdAt: koreaPhoto.createdAt,
                                            latitude: koreaPhoto.latitude,
                                            longitude: koreaPhoto.longitude,
                                            isoCountryCode: address.isoCountryCode,
                                            address: address),
                                        state: .progress(index/Double(total))
                                    )
                                )

                            } else {
                                etcPhotos.append(koreaPhoto)
                            }
                        }

                        // 외국 주소
                        let unique = Dictionary(grouping: etcPhotos) {
                            if let lat = $0.latitude, let lng = $0.longitude {
                                return "\((lat * 10000).rounded() / 10000),\((lng * 10000).rounded() / 10000)"
                            }
                            return ""
                        }

                        let batchSize = 50
                        let uniqueArray = Array(unique)
                        let batches = stride(from: 0, to: uniqueArray.count, by: batchSize).map {
                            Array(uniqueArray[$0..<min($0 + batchSize, uniqueArray.count)])
                        }

                        var overseasAddress: [String: PhotoLocation] = [:]
                        for batch in batches {
                            let batchDict = Dictionary(uniqueKeysWithValues: batch)
                            do {
                                let batchResult = try await self.geoRepository.locationOverseas(batchDict)
                                overseasAddress.merge(batchResult) { _, new in new }
                            } catch {
                                debugLog("⚠️ 해외 주소 배치 조회 실패, 이 배치만 건너뜀: \(error)")
                            }
                        }

                        for etcPhoto in etcPhotos {
                            if let address = overseasAddress[etcPhoto.localIdentifier],
                               let isoCountryCode = address.isoCountryCode,
                               address.isoCountryCode != "none" {

                                index += 1
                                continuation.yield(
                                    ProgressAnalysis(
                                        photo: Photo(
                                            localIdentifier: etcPhoto.localIdentifier,
                                            createdAt: etcPhoto.createdAt,
                                            latitude: etcPhoto.latitude,
                                            longitude: etcPhoto.longitude,
                                            isoCountryCode: isoCountryCode,
                                            address: address),
                                        state: .progress(index/Double(total))
                                    )
                                )
                            } else {
                                noCodePhotos.append(etcPhoto)
                            }
                        }

                        for photo in noCodePhotos {

                            guard let latitude = photo.latitude, let longitude = photo.longitude else {
                                continue
                            }

                            let address: PhotoLocation
                            do {
                                guard let resolved = try await self.analysisRepository.geocoderAnalyze(
                                    latitude: latitude, longitude: longitude) else {
                                    continue
                                }
                                address = resolved
                            } catch {
                                debugLog("⚠️ 개별 사진 주소 조회 실패, 이 사진만 건너뜀: \(error)")
                                continue
                            }

                            index += 1
                            continuation.yield(
                                ProgressAnalysis(
                                    photo: Photo(
                                        localIdentifier: photo.localIdentifier,
                                        createdAt: photo.createdAt,
                                        latitude: photo.latitude,
                                        longitude: photo.longitude,
                                        isoCountryCode: address.isoCountryCode == "" ? "NO":address.isoCountryCode ?? "NO",
                                        address: address),
                                    state: .progress(index / Double(total))
                                )
                            )

                            try await Task.sleep(nanoseconds: 1_500_000_000)
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    private func execute(
        stream: @escaping () async throws -> AsyncThrowingStream<ProgressAnalysis, Error>?
    ) -> AsyncThrowingStream<ProgressAnalysis, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let analysisStream = try await stream() else {
                        continuation.finish()
                        return
                    }

                    for try await progress in analysisStream {
                        try await dataRepository.saveAndUpdateLabels(
                            photo: progress.photo,
                            labels: progress.photo.labels
                        )
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func isKorea(latitude: Double, longitude: Double) -> Bool {
        // 한국 바운딩 박스로 1차 필터 — 폴리곤 순회보다 훨씬 빠름
        return (32.0...39.5).contains(latitude) &&
               (123.5...132.5).contains(longitude)
    }
}

/// 라벨+얼굴 분석과 주소 변환이 동시에 진행될 때 각각의 최신 진행률을 가중합해서 하나의 진행률로 합친다.
private actor ProgressCombiner {
    private let labelWeight: Double
    private let addressWeight: Double

    private var labelRatio: Double = 0
    private var addressRatio: Double = 0

    init(labelWeight: Double, addressWeight: Double) {
        self.labelWeight = labelWeight
        self.addressWeight = addressWeight
    }

    private var combined: Double {
        labelRatio * labelWeight + addressRatio * addressWeight
    }

    func updateLabel(_ ratio: Double) -> Double {
        labelRatio = ratio
        return combined
    }

    func updateAddress(_ ratio: Double) -> Double {
        addressRatio = ratio
        return combined
    }
}
