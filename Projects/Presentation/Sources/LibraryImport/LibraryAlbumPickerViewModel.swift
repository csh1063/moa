//
//  LibraryAlbumPickerViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 9/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Combine
import Domain

enum LibraryAlbumPickerAction {
    case pop
}

@MainActor
final class LibraryAlbumPickerViewModel: BaseViewModel {

    enum Input {
        case appear
        case selectAlbum(AlbumAsset)
        case importAll
        case dismiss
    }

    struct Output {
        let albums: AnyPublisher<[AlbumAsset], Never>
    }

    @Published private var albums: [AlbumAsset] = []

    let input = PassthroughSubject<Input, Never>()
    var onAction: ((LibraryAlbumPickerAction) -> Void)?

    private let useCase: LibraryAlbumImportUseCase
    private var cancellables = Set<AnyCancellable>()

    init(useCase: LibraryAlbumImportUseCase) {
        self.useCase = useCase

        super.init()

        self.bind()
    }

    func transform() -> Output {
        Output(albums: $albums.eraseToAnyPublisher())
    }

    func send(_ input: Input) {
        self.input.send(input)
    }

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
            await loadAlbums()
        case .selectAlbum(let albumAsset):
            await importAlbum(albumAsset)
        case .importAll:
            await importAllAlbums()
        case .dismiss:
            onAction?(.pop)
        }
    }

    private func loadAlbums() async {
        do {
            self.isLoading = true
            self.albums = try await useCase.fetchDeviceAlbums()
            self.isLoading = false
        } catch {
            self.isLoading = false
            debugLog("사진첩 앨범 목록 로딩 실패: \(error)")
        }
    }

    private func importAllAlbums() async {
        guard !albums.isEmpty else { return }
        self.isLoading = true

        var importedCount = 0
        var totalPhotoCount = 0
        for albumAsset in albums {
            do {
                let saved = try await useCase.importAlbum(albumAsset)
                importedCount += 1
                totalPhotoCount += saved.photoCount
            } catch {
                debugLog("전체 가져오기 중 \"\(albumAsset.name)\" 실패: \(error)")
            }
        }

        self.isLoading = false
        showAlert(
            title: String(localized: "가져오기 완료", bundle: .module),
            message: String(localized: "앨범 \(importedCount)개, 사진 \(totalPhotoCount)장을 가져왔어요", bundle: .module),
            buttons: [
                AlertButtonConfig(title: String(localized: "확인", bundle: .module), style: .default) { [weak self] in
                    self?.onAction?(.pop)
                }
            ]
        )
    }

    private func importAlbum(_ albumAsset: AlbumAsset) async {
        do {
            self.isLoading = true
            let saved = try await useCase.importAlbum(albumAsset)
            self.isLoading = false
            showAlert(
                title: String(localized: "가져오기 완료", bundle: .module),
                message: String(localized: "\"\(saved.displayName)\" 앨범을 \(saved.photoCount)장 가져왔어요", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "확인", bundle: .module), style: .default) { [weak self] in
                        self?.onAction?(.pop)
                    }
                ]
            )
        } catch {
            self.isLoading = false
            debugLog("앨범 가져오기 실패: \(error)")
            showAlert(
                title: String(localized: "가져오기 실패", bundle: .module),
                message: String(localized: "앨범을 가져오지 못했어요. 다시 시도해주세요", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "확인", bundle: .module), style: .default, action: nil)
                ]
            )
        }
    }
}
