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
            // 지도가 실제로 뜨기 전이라 정확한 줌을 모르니, 시/군/구 단위(중간값) 기본으로 먼저
            // 보여주고 — 지도가 뜨면 regionDidChangeAnimated가 실제 줌으로 다시 갱신한다
            recluster(zoomLevel: 10)
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
