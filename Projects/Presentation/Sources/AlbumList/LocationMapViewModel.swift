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
        /// 지도 팬/줌이 끝날 때마다 컨트롤러가 계산해서 넘겨주는 줌 레벨 — 값 자체가 아니라
        /// tier(구간)가 바뀔 때만 실제로 다시 클러스터링한다
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
    /// 지도가 실제로 레이아웃되며 보고한 최신 줌 레벨 — 사진 로딩이 끝나기 전에 먼저 도착해도
    /// 여기 저장만 해두고, 사진이 준비되면 이 값으로 최초 클러스터링을 한다(가짜 기본값 대신)
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
            // 사진이 아직 로딩 전이면 여기서 tier를 확정 짓지 않는다 — currentTier가 먼저
            // 정해져버리면 이후 loadPhotos()의 최초 recluster가 "이미 같은 tier"로 오인해
            // 실제 사진 목록으로는 한 번도 클러스터링을 안 하는 경우가 생긴다
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
            // 지도가 이미 최초 레이아웃을 마치고 실제 줌을 한 번이라도 보고했다면(대개는 DB
            // 조회가 지도 레이아웃보다 느려서 이 경우다) 그 값으로 처음부터 정확히 클러스터링한다.
            // 아주 드물게 사진 로딩이 지도 레이아웃보다 먼저 끝나 아직 실제 줌을 모르는 경우에만
            // 시/군/구 단위(중간값) 기본으로 먼저 보여주고, 뒤이어 regionDidChangeAnimated가
            // 도착하면 실제 줌으로 다시 갱신한다
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
