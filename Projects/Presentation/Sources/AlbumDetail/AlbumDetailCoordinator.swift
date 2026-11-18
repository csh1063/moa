//
//  AlbumDetailCoordinator.swift
//  Presentation
//
//  Created by sanghyeon on 3/28/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Domain

@MainActor
public final class AlbumDetailCoordinator: BaseCoordinator {

    private let diContainer: AlbumDetailDIContainer
    private let navigationController: UINavigationController

    weak var delegate: AlbumDetailViewModelDelegate?

    /// 길게 누르기 메뉴의 viewModel을 붙잡아 둔다 — delegate가 weak라 로컬 변수면 바로 해제된다
    private var menuViewModel: AlbumDetailViewModel?

    init(diContainer: AlbumDetailDIContainer,
         navigationController: UINavigationController) {
        self.diContainer = diContainer
        self.navigationController = navigationController

        super.init()
    }

    public override func start() {
        let viewModel = diContainer.makeAlbumDetailViewModel()
        wireActions(of: viewModel)

        let vc = AlbumDetailViewController(viewModel: viewModel)

        navigationController.pushViewController(vc, animated: true)
        self.viewController = vc
    }

    /// 앨범을 길게 눌렀을 때 — 상세 화면 진입 없이 "..." 메뉴와 같은 메뉴를 바로 띄운다
    func presentAlbumMenu(album: Album) {
        let viewModel = diContainer.makeAlbumDetailViewModel()
        self.menuViewModel = viewModel
        wireActions(of: viewModel)
        showAlbumOptions(album: album)
    }

    private func wireActions(of viewModel: AlbumDetailViewModel) {
        self.delegate = viewModel
        viewModel.onAction = { [weak self] action in
            switch action {
            case .options(let album):
                self?.showAlbumOptions(album: album)
            case .optionsFiltered(let photos):
                self?.showFilteredOptions(photos: photos)
            case .pop:
                self?.pop()
            case .selectPhoto(let photoDetails, let index, let inSelectionMode):
                self?.showDetail(photoDetails, index: index, inSelectionMode: inSelectionMode)
            case .pickMergeTarget(let candidates, let isTravel, let currentAlbum):
                self?.showMergeTargetPicker(candidates: candidates, isTravel: isTravel, currentAlbum: currentAlbum)
            case .pickSplitClusters(let clusters):
                self?.showClusterSplitPicker(clusters: clusters)
            case .pickTravelerManagement(let travelers, let others):
                self?.showTravelerManagement(travelers: travelers, others: others)
            case .previewCover(let album, let candidateId):
                self?.showCoverPreview(album: album, candidateId: candidateId)
            case .showFiltered(let title, let photos, let sourceAlbumId):
                self?.startFiltered(title: title, photos: photos, sourceAlbumId: sourceAlbumId)
            case .share(let photos):
                self?.presentShareSheet(for: photos)
            }
        }

        bindAlert(from: viewModel)
    }

    private func pop() {
        navigationController.popViewController(animated: true)
        self.remove(coordinator: self)
    }

    func showAlbumRenameSheet(album: Album) {
        // 인물/동물은 직접 지은 이름이 없으면 입력칸을 비워서 보여준다
        let sheet: AlbumRenameSheet
        if album.from == "face" || album.from == "animal" {
            sheet = AlbumRenameSheet(
                albumName: album.isRenamed ? album.displayName : "",
                title: String(localized: "이름 변경", bundle: .module),
                subtitle: String(localized: "이름을 정해주세요", bundle: .module)
            )
        } else {
            // 다른 타입은 자동 이름도 의미가 있어서 그대로 채운다
            sheet = AlbumRenameSheet(albumName: album.displayName)
        }
        sheet.onSave = { [weak self] newName in
            self?.delegate?.save(name: newName)
        }
        sheet.onCancel = { }

        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.custom { _ in 260 }]
            presentation.preferredCornerRadius = 28
        }

        navigationController.present(sheet, animated: true)
    }

    func showAlbumOptions(album: Album) {
        var options: [OptionRowConfig] = []

        // 날짜/카테고리/장소/중복은 이름과 대표 사진이 분류 기준이라 바꿀 수 없다 — 인물/동물/여행만
        let editableCoverTypes: Set<String> = ["face", "animal", "travel"]
        if editableCoverTypes.contains(album.from) {
            options.append(
                OptionRowConfig(icon: "lucide_pencil_line", title: String(localized: "앨범명 변경", bundle: .module), style: .normal) { [weak self] in
                    self?.showAlbumRenameSheet(album: album)
                }
            )

            // 대표 사진 고르기는 상세 화면 그리드가 있어야 해서 길게 누르기 메뉴에선 뺀다
            if viewController != nil {
                options.append(
                    OptionRowConfig(icon: "lucide_images", title: String(localized: "대표 사진 변경", bundle: .module), style: .normal) { [weak self] in
                        self?.delegate?.changeMode(.pickCover)
                    }
                )
            }
        }

        if album.from == "face" || album.from == "animal" {
            options.append(
                OptionRowConfig(icon: "lucide_merge", title: String(localized: "앨범 합치기", bundle: .module), style: .normal) { [weak self] in
                    self?.delegate?.mergeTapped()
                }
            )
            options.append(
                OptionRowConfig(icon: "lucide_split", title: String(localized: "앨범 분리", bundle: .module), style: .normal) { [weak self] in
                    self?.delegate?.splitTapped()
                }
            )
        }

        if album.from == "travel" {
            options.append(
                OptionRowConfig(icon: "lucide_image_plus", title: String(localized: "사진 추가", bundle: .module), style: .normal) { [weak self] in
                    self?.showAddPhotos(album: album)
                }
            )
            options.append(
                OptionRowConfig(icon: "lucide_users", title: String(localized: "여행자 관리", bundle: .module), style: .normal) { [weak self] in
                    self?.delegate?.travelerManagementTapped()
                }
            )
            options.append(
                OptionRowConfig(icon: "lucide_merge", title: String(localized: "여행 합치기", bundle: .module), style: .normal) { [weak self] in
                    self?.delegate?.mergeTapped()
                }
            )
        }

        // 대표 사진 변경과 같은 이유로 그리드가 실제로 떠 있어야 공유할 사진 목록을 알 수 있다
        if viewController != nil {
            options.append(
                OptionRowConfig(icon: "lucide_share_2", title: String(localized: "전체 공유", bundle: .module), style: .normal) { [weak self] in
                    self?.delegate?.shareAllTapped()
                }
            )
        }

        if album.from == "similar" {
            options.append(
                OptionRowConfig(icon: "lucide_circle_check", title: String(localized: "정리 완료", bundle: .module), style: .normal) { [weak self] in
                    self?.delegate?.deleteAlert()
                }
            )
        } else {
            options.append(
                OptionRowConfig(icon: "lucide_trash_2", title: String(localized: "앨범 삭제", bundle: .module), style: .destructive) { [weak self] in
                    self?.delegate?.deleteAlert()
                }
            )
        }

        let sheet = SelectionSheet(title: album.displayName, options: options)

        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.custom { _ in sheet.preferredDetentHeight }]
            presentation.preferredCornerRadius = 28
        }

        navigationController.present(sheet, animated: true)
    }

    /// 대표 사진 미리보기 — "선택"을 눌러야 저장, 취소하면 그리드로 돌아간다
    func showCoverPreview(album: Album, candidateId: String) {
        let vc = CoverPhotoPreviewViewController(
            album: album,
            candidateId: candidateId,
            imageUseCase: diContainer.makeImageUseCase(),
            detailUseCase: diContainer.makeAlbumDetailUseCase()
        )
        vc.onConfirm = { [weak self] in
            self?.delegate?.setCover(id: candidateId)
            (self?.viewController as? AlbumDetailViewController)?.exitSelectionMode()
        }

        navigationController.present(vc, animated: true)
    }

    func showMergeTargetPicker(candidates: [AlbumMergeCandidate], isTravel: Bool, currentAlbum: Album) {
        let isAnimal = currentAlbum.from == "animal"

        guard !candidates.isEmpty else {
            let message: String
            if isTravel {
                message = String(localized: "합칠 수 있는 다른 여행 앨범이 없어요", bundle: .module)
            } else if isAnimal {
                message = String(localized: "합칠 수 있는 다른 동물 앨범이 없어요", bundle: .module)
            } else {
                message = String(localized: "합칠 수 있는 다른 인물 앨범이 없어요", bundle: .module)
            }
            let alert = UIAlertController(title: String(localized: "합칠 앨범 없음", bundle: .module), message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "확인", bundle: .module), style: .default))
            navigationController.present(alert, animated: true)
            return
        }

        var currentDateRangeText: String?
        if let start = currentAlbum.startDate, let end = currentAlbum.endDate {
            currentDateRangeText = AlbumMergeSheet.dateRangeFormatter.string(from: start, to: end)
        }

        let title: String
        if isTravel {
            title = String(localized: "합칠 여행 선택", bundle: .module)
        } else if isAnimal {
            title = String(localized: "같은 반려동물 앨범 선택", bundle: .module)
        } else {
            title = String(localized: "동일 인물 앨범 선택", bundle: .module)
        }

        let sheet = AlbumMergeSheet(
            candidates: candidates,
            title: title,
            subtitle: isTravel ? String(localized: "끊어진 두 여행을 연결해요", bundle: .module) : nil,
            sectionHeaderText: isTravel ? currentDateRangeText.map { String(localized: "현재 여행 날짜 : \($0)", bundle: .module) } : nil,
            isTravel: isTravel,
            imageUseCase: diContainer.makeImageUseCase(),
            albumUseCase: diContainer.makeAlbumUseCase()
        )
        sheet.onConfirm = { [weak self] selectedIds in
            guard !selectedIds.isEmpty else { return }
            self?.delegate?.mergeInto(albumIds: selectedIds)
        }

        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.preferredCornerRadius = 28
        }

        navigationController.present(sheet, animated: true)
    }

    func showClusterSplitPicker(clusters: [FaceClusterSummary]) {
        guard clusters.count > 1 else {
            let alert = UIAlertController(
                title: String(localized: "분리할 그룹 없음", bundle: .module),
                message: String(localized: "이 앨범은 병합된 적이 없어서 분리할 그룹이 없어요", bundle: .module),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "확인", bundle: .module), style: .default))
            navigationController.present(alert, animated: true)
            return
        }

        let sheet = ClusterSplitSheet(clusters: clusters, imageUseCase: diContainer.makeImageUseCase())
        sheet.onConfirm = { [weak self] selectedIds in
            guard !selectedIds.isEmpty else { return }
            self?.delegate?.splitInto(clusterIds: selectedIds)
        }

        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.custom { _ in sheet.preferredDetentHeight }]
            presentation.preferredCornerRadius = 28
        }

        navigationController.present(sheet, animated: true)
    }

    func showTravelerManagement(travelers: [Album], others: [Album]) {
        let sheet = TravelerManagementSheet(
            travelers: travelers,
            others: others,
            imageUseCase: diContainer.makeImageUseCase(),
            albumUseCase: diContainer.makeAlbumUseCase(),
            detailUseCase: diContainer.makeAlbumDetailUseCase()
        )
        sheet.onConfirm = { [weak self] travelerIds in
            self?.delegate?.saveTravelerManagement(travelerIds: travelerIds)
        }

        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.preferredCornerRadius = 28
            presentation.prefersGrabberVisible = false
        }
        sheet.isModalInPresentation = true

        navigationController.present(sheet, animated: true)
    }

    // MARK: - 사진 추가 (이전/이후 헤더 토글 + 페이징 그리드가 있는 화면 하나)

    func showAddPhotos(album: Album) {
        guard let startDate = album.startDate, let endDate = album.endDate else { return }

        let detailUseCase = diContainer.makeAlbumDetailUseCase()
        let beforeViewModel = TravelPhotoPickerViewModel(
            album: album,
            direction: .before(startDate),
            imageUseCase: diContainer.makeImageUseCase(),
            detailUseCase: detailUseCase
        )
        let afterViewModel = TravelPhotoPickerViewModel(
            album: album,
            direction: .after(endDate),
            imageUseCase: diContainer.makeImageUseCase(),
            detailUseCase: detailUseCase
        )
        let vc = TravelPhotoPickerViewController(
            albumId: album.id,
            beforeViewModel: beforeViewModel,
            afterViewModel: afterViewModel,
            detailUseCase: detailUseCase
        )

        vc.onCancel = { [weak self] in
            self?.dismissAddPhotosFlow()
        }
        vc.onFinish = { [weak self] in
            self?.delegate?.refreshAfterPhotosAdded()
            self?.dismissAddPhotosFlow()
        }
        vc.onSelectPhoto = { [weak self, weak vc] photoDetails, index, selectedIdentifiers in
            guard let vc else { return }
            self?.showPickerDetail(pickerVC: vc, photoDetails: photoDetails, index: index, selectedIdentifiers: selectedIdentifiers)
        }

        // 길게 누르기 메뉴에서도 열 수 있게 모달로 띄운다
        vc.modalPresentationStyle = .fullScreen
        navigationController.present(vc, animated: true)
    }

    /// "사진 추가" 플로우 전체를 한 번에 닫는다
    private func dismissAddPhotosFlow() {
        navigationController.dismiss(animated: true)
    }

    /// "사진 추가"에서 사진을 탭했을 때 — 뷰어를 선택 모드로 띄우고 선택 결과를 피커에 반영한다
    private func showPickerDetail(pickerVC: TravelPhotoPickerViewController, photoDetails: [PhotoDetail], index: Int, selectedIdentifiers: Set<String>) {
        let vm = diContainer.makeImageViewerViewModel(
            photoDetails: photoDetails,
            index: index,
            isSelectionMode: true,
            selectedIdentifiers: selectedIdentifiers
        )
        vm.onAction = { [weak pickerVC] action in
            switch action {
            case .pageChanged(let id):
                pickerVC?.scrollToItem(id: id)
            case .selectionChanged(let identifiers):
                pickerVC?.syncSelection(identifiers)
            }
        }
        let vc = ImageViewerViewController(viewModel: vm)
        pickerVC.present(vc, animated: true)
    }

//    func showDetail(_ photoDetails: [PhotoDetail], index: Int) {
//        let vm = diContainer.makeImageViewerViewModel(photoDetails: photoDetails, index: index)
//        vm.onAction = { [weak self] action in
//            switch action {
//            case .pageChanged(let id):
//                (self?.viewController as? AlbumDetailViewController)?.scrollToItem(id: id)
//            }
//        }
//        let vc = ImageViewerViewController(viewModel: vm)
//        
//        navigationController.present(vc, animated: true)
//    }

    func showDetail(_ photoDetails: [PhotoDetail], index: Int, inSelectionMode: Bool) {
        let albumDetailVC = viewController as? AlbumDetailViewController

        let vm = diContainer.makeImageViewerViewModel(
            photoDetails: photoDetails,
            index: index,
            isSelectionMode: inSelectionMode,
            selectedIdentifiers: albumDetailVC?.selectedIdentifiers ?? []
        )

        vm.onAction = { [weak albumDetailVC] action in
            switch action {
            case .pageChanged(let id):
                albumDetailVC?.scrollToItem(id: id)
            case .selectionChanged(let identifiers):
                albumDetailVC?.syncSelection(identifiers)
            }
        }

        let vc = ImageViewerViewController(viewModel: vm)
        navigationController.present(vc, animated: true)
    }

    // MARK: - 분류순 "더보기" (실제 앨범 아님, 여행 사진 ∩ 사람/카테고리 사진만 보여주는 화면)

    func startFiltered(title: String, photos: [Photo], sourceAlbumId: UUID) {
        let viewModel = diContainer.makeAlbumDetailViewModel(filteredTitle: title, photos: photos, sourceAlbumId: sourceAlbumId)
        wireActions(of: viewModel)

        let vc = AlbumDetailViewController(viewModel: viewModel)
        navigationController.pushViewController(vc, animated: true)
        // viewController는 항상 지금 맨 위의 앨범 상세 화면을 가리켜야 한다
        self.viewController = vc
    }

    /// 더보기로 들어간 화면의 "..." — 실제 앨범이 아니라서 병합/삭제 등은 없고 공유 한 줄뿐
    func showFilteredOptions(photos: [Photo]) {
        let options = [
            OptionRowConfig(icon: "lucide_share_2", title: String(localized: "전체 공유", bundle: .module), style: .normal) { [weak self] in
                self?.presentShareSheet(for: photos)
            }
        ]
        let sheet = SelectionSheet(title: String(localized: "공유", bundle: .module), options: options)

        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.custom { _ in sheet.preferredDetentHeight }]
            presentation.preferredCornerRadius = 28
        }

        navigationController.present(sheet, animated: true)
    }

    // MARK: - 공유

    func presentShareSheet(for photos: [Photo]) {
        guard !photos.isEmpty else { return }

        LoadingManager.shared.show(allowDismiss: false)
        let imageUseCase = diContainer.makeImageUseCase()

        Task { [weak self] in
            guard let self else { return }
            var images: [UIImage] = []
            // shortcut: 한 번에 최대 50장만 공유 — 더 필요해지면 그때 늘린다
            for photo in photos.prefix(50) {
                guard let cgImage: CGImage = try? await imageUseCase.loadImage(id: photo.localIdentifier, type: .maxSize).cgImage else { continue }
                images.append(UIImage(cgImage: cgImage))
            }

            LoadingManager.shared.hide()

            guard !images.isEmpty else {
                let alert = UIAlertController(
                    title: nil,
                    message: String(localized: "공유할 사진을 불러오지 못했어요", bundle: .module),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "확인", bundle: .module), style: .default))
                navigationController.present(alert, animated: true)
                return
            }

            let activityVC = UIActivityViewController(activityItems: images, applicationActivities: nil)
            navigationController.present(activityVC, animated: true)
        }
    }
}
