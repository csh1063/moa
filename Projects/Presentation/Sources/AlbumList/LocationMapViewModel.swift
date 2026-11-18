//
//  LocationMapViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 9/7/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Combine
import Domain
import UIKit

enum LocationMapViewModelAction {
    case selectPhoto(_ photoDetails: [PhotoDetail], index: Int)
    case pop
}

@MainActor
final class LocationMapViewModel: BaseViewModel {

    enum Input {
        case appear
        case dismiss
        case selectCluster(id: String)
        /// 팬/줌이 끝날 때의 줌 레벨 — 구간(tier)이 바뀔 때만 다시 클러스터링한다
        case zoomLevelChanged(Double)
    }

    struct Output {
        let clusters: AnyPublisher<[PhotoMapCluster], Never>
    }

    @Published private var clusters: [PhotoMapCluster] = []

    /// DB 조회는 화면 진입 시 한 번만 — 줌마다 다시 쿼리하지 않고 이 목록을 재클러스터링만 한다
    private var photos: [Photo] = []
    private var currentTier: Int?
    private var photosLoaded = false
    /// 사진 로딩 전에 도착한 실제 줌 레벨 — 로딩이 끝나면 이 값으로 처음 클러스터링한다
    private var latestZoomLevel: Double?

    let input = PassthroughSubject<Input, Never>()
    var onAction: ((LocationMapViewModelAction) -> Void)?

    private let photoMapUseCase: PhotoMapUseCase
    private let imageUseCase: PhotoImageUseCase

    private var cancellables = Set<AnyCancellable>()

    init(photoMapUseCase: PhotoMapUseCase, imageUseCase: PhotoImageUseCase) {
        self.photoMapUseCase = photoMapUseCase
        self.imageUseCase = imageUseCase

        super.init()

        self.bind()
    }

    func transform() -> Output {
        Output(clusters: $clusters.eraseToAnyPublisher())
    }

    func send(_ input: Input) {
        self.input.send(input)
    }

    private func bind() {
        self.input.sink { [weak self] input in
            guard let self else { return }
            Task { @MainActor in await self.handle(input) }
        }
        .store(in: &cancellables)
    }

    private func handle(_ input: Input) async {
        switch input {
        case .appear:
            await loadPhotos()
        case .zoomLevelChanged(let zoomLevel):
            latestZoomLevel = zoomLevel
            // 사진 로딩 전엔 tier를 정하지 않는다 — 정해버리면 첫 클러스터링이 건너뛰어진다
            guard photosLoaded else { return }
            recluster(zoomLevel: zoomLevel)
        case .dismiss:
            onAction?(.pop)
        case .selectCluster(let id):
            guard let cluster = clusters.first(where: { $0.id == id }) else { return }
            let photoDetails = cluster.photos.map {
                PhotoDetail(id: $0.localIdentifier, createdDate: $0.createdAt, photo: $0, isVideo: $0.isVideo)
            }
            onAction?(.selectPhoto(photoDetails, index: 0))
        }
    }

    private func loadPhotos() async {
        do {
            photos = try await photoMapUseCase.fetchPhotosWithCoordinates()
            photosLoaded = true
            // 실제 줌을 이미 받았으면 그 값으로, 아니면 시/군/구 단위로 먼저 보여준다
            recluster(zoomLevel: latestZoomLevel ?? 10)
        } catch {
            debugLog("장소 지도 로딩 실패: \(error)")
        }
    }

    private func recluster(zoomLevel: Double) {
        let tier = PhotoMapClustering.tier(for: zoomLevel)
        guard tier != currentTier else { return }
        currentTier = tier
        clusters = PhotoMapClustering.cluster(photos: photos, zoomLevel: zoomLevel)
    }

    func loadImage(id: String, size: CGSize) async -> UIImage? {
        do {
            guard let cgImage: CGImage = try await imageUseCase.loadImage(
                id: id,
                type: .specialSize(size)
            ).cgImage else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
