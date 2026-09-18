//
//  ImageViewerViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 5/7/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import AVFoundation
import Combine
import Domain

enum ImageViewerViewModelAction {
    case pageChanged(String)
    case selectionChanged(Set<String>)
}

final class ImageViewerViewModel: BaseViewModel {

    enum Input {
        case appear
        case pageChanged(Int)
        case toggleSelection(id: String)
    }

    struct Output {
        let currentPhoto: AnyPublisher<PhotoDetail?, Never>
        let selectedIdentifiers: AnyPublisher<Set<String>, Never>
    }

    // MARK: - Properties

    @Published var currentIndex: Int
    @Published private var currentPhoto: PhotoDetail?
    @Published private(set) var selectedIdentifiers: Set<String>

    let photoDetails: [PhotoDetail]
    let isSelectionMode: Bool

    let input = PassthroughSubject<Input, Never>()
    var onAction: ((ImageViewerViewModelAction) -> Void)?

    private var imageCache: [String: UIImage] = [:]
    private let imageUseCase: ImageViewerUseCase
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(photoDetails: [PhotoDetail],
         initialIndex: Int,
         imageUseCase: ImageViewerUseCase,
         isSelectionMode: Bool = false,
         selectedIdentifiers: Set<String> = []) {
        self.photoDetails = photoDetails
        self.imageUseCase = imageUseCase
        self.currentIndex = initialIndex
        self.isSelectionMode = isSelectionMode
        self.selectedIdentifiers = selectedIdentifiers
        super.init()
        bind()
    }

    // MARK: - Transform

    func transform() -> Output {
        Output(
            currentPhoto: $currentPhoto.eraseToAnyPublisher(),
            selectedIdentifiers: $selectedIdentifiers.eraseToAnyPublisher()
        )
    }

    func send(_ input: Input) {
        self.input.send(input)
    }

    // MARK: - Image Loading

    func loadImage(for index: Int, size: CGSize) async -> UIImage? {
        let id = photoDetails[index].id
        return await loadImage(id: id, size: size)
    }

    func loadImage(id: String, size: CGSize) async -> UIImage? {
        if let cached = imageCache[id] { return cached }
        do {
            guard let cgImage: CGImage = try await imageUseCase.loadImage(id: id, type: .maxSize).cgImage else { return nil }
            let image = UIImage(cgImage: cgImage)
            imageCache[id] = image
            return image
        } catch {
            return nil
        }
    }

    /// 화면 크기 정도의 저화질을 먼저 보여주고(빠르게 스와이프해도 안 밀리게), 뒤이어 최대 해상도로
    /// 교체한다. 캐시에는 최종 고화질만 남긴다 — 안 그러면 나중에 다시 돌아왔을 때 저화질이 뜬다.
    func loadImageProgressive(id: String, size: CGSize, onImage: @escaping (UIImage?, Bool) -> Void) {
        if let cached = imageCache[id] {
            onImage(cached, true)
            return
        }

        Task {
            await imageUseCase.loadImageProgressive(id: id, size: size) { [weak self] (data: ImageData<CGImage>, _) in
                guard let self else { return }
                let image = data.cgImage.map { UIImage(cgImage: $0) }
                Task { @MainActor in
                    // 이 사이 최대 해상도가 먼저 도착해서 캐시에 이미 들어있다면, 뒤늦게 온 저화질로
                    // 덮어쓰지 않는다
                    guard self.imageCache[id] == nil else { return }
                    onImage(image, false)
                }
            }

            do {
                guard let cgImage: CGImage = try await self.imageUseCase.loadImage(id: id, type: .maxSize).cgImage else { return }
                let image = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.imageCache[id] = image
                    onImage(image, true)
                }
            } catch {
                // 실패해도 이미 화면엔 저화질이 떠 있으니 조용히 무시
            }
        }
    }

    /// 영상 셀 전용 — 매번 새 AVPlayerItem을 만들어야 재생 위치가 꼬이지 않아서 캐시하지 않는다
    func loadVideoPlayerItem(id: String) async -> AVPlayerItem? {
        try? await imageUseCase.loadVideoAsset(id: id)
    }

    // MARK: - Private

    private func bind() {
        input.sink { [weak self] input in
            guard let self else { return }
            Task { @MainActor in await self.handle(input) }
        }
        .store(in: &cancellables)
    }

    private func handle(_ input: Input) async {
        switch input {
        case .appear:
            await setCurrentPhoto(index: currentIndex, isAction: false)
        case .pageChanged(let index):
            await setCurrentPhoto(index: index)

        case .toggleSelection(let id):
            if selectedIdentifiers.contains(id) {
                selectedIdentifiers.remove(id)
            } else {
                selectedIdentifiers.insert(id)
            }
            onAction?(.selectionChanged(selectedIdentifiers))
        }
    }

    private func setCurrentPhoto(index: Int, isAction: Bool = true) async {
        currentIndex = index
        let detail = photoDetails[index]
        currentPhoto = detail
//        await loadLabels(by: detail.id)
        if isAction {
            onAction?(.pageChanged(detail.id))
        }
    }

    private func loadLabels(by id: String) async {
        do {
            let labels = try await imageUseCase.getLabels(by: id)
            currentPhoto?.labels = labels
        } catch {
            debugLog("labels load error: \(error.localizedDescription)")
        }
    }
}

extension ImageViewerViewModel: ImageLoadable {}
