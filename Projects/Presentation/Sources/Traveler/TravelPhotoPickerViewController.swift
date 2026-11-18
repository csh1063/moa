//
//  TravelPhotoPickerViewController.swift
//  Presentation
//
//  Created by sanghyeon on 7/12/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Combine
import Domain

/// 여행 앨범에 사진을 수동으로 추가 — 이전/이후 그리드를 토글로 전환하고 고른 걸 한꺼번에 추가한다
final class TravelPhotoPickerViewController: UIViewController {

    private enum ActiveDirection { case before, after }

    // MARK: - Callbacks

    var onCancel: (() -> Void)?
    var onFinish: (() -> Void)?
    /// 이미지를 탭해서 상세(뷰어)로 보여달라는 요청 — 앨범 상세와 동일하게 뷰어에서도 선택할 수 있다
    var onSelectPhoto: ((_ photoDetails: [PhotoDetail], _ index: Int, _ selectedIdentifiers: Set<String>) -> Void)?

    // MARK: - Properties

    private let albumId: UUID
    private let detailUseCase: AlbumDetailUseCase
    private let beforeViewModel: TravelPhotoPickerViewModel
    private let afterViewModel: TravelPhotoPickerViewModel
    private var cancellables = Set<AnyCancellable>()
    private var activeDirection: ActiveDirection = .before
    private var isCommitting = false

    // MARK: - UI

    private let naviView = NaviBarView(type: .title(.leading))

    private lazy var directionSegment = PillSegmentedControl(items: [
        beforeViewModel.direction.headerText,
        afterViewModel.direction.headerText
    ])

    private let pagingScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isPagingEnabled = true
        sv.isScrollEnabled = false  // 헤더 토글로만 전환 (직접 스와이프는 막아서 활성 상태와 항상 일치시킴)
        sv.showsHorizontalScrollIndicator = false
        return sv
    }()
    private let pageContainer = UIView()

    private lazy var beforeGrid = TravelPhotoGridView(viewModel: beforeViewModel)
    private lazy var afterGrid = TravelPhotoGridView(viewModel: afterViewModel)

    // MARK: - Init

    init(albumId: UUID,
         beforeViewModel: TravelPhotoPickerViewModel,
         afterViewModel: TravelPhotoPickerViewModel,
         detailUseCase: AlbumDetailUseCase) {
        self.albumId = albumId
        self.beforeViewModel = beforeViewModel
        self.afterViewModel = afterViewModel
        self.detailUseCase = detailUseCase
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("TravelPhotoPickerViewController does not support NSCoding.")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setupLayout()
        setupTopBar()
        setupGrids()
        updateAddButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AnalyticsTracker.shared.logScreenView("사진 추가")
    }

    // MARK: - Setup

    private func setupLayout() {
        view.addSubview(naviView)
        view.addSubview(directionSegment)
        view.addSubview(pagingScrollView)
        pagingScrollView.addSubview(pageContainer)
        pageContainer.addSubview(beforeGrid)
        pageContainer.addSubview(afterGrid)

        naviView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        directionSegment.snp.makeConstraints { make in
            make.top.equalTo(naviView.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        pagingScrollView.snp.makeConstraints { make in
            make.top.equalTo(directionSegment.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview()
        }
        pageContainer.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(pagingScrollView)
        }
        beforeGrid.snp.makeConstraints { make in
            make.top.bottom.leading.equalToSuperview()
            make.width.equalTo(pagingScrollView)
        }
        afterGrid.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalTo(beforeGrid.snp.trailing)
            make.trailing.equalToSuperview()
            make.width.equalTo(pagingScrollView)
        }
    }

    private func setupTopBar() {
        naviView.setTitle(String(localized: "사진 추가", bundle: .module))
        naviView.addButtons([LeftButton(type: .close), RightButton(type: .add)])

        naviView.publisher
            .sink { [weak self] type in
                switch type {
                case .close: self?.onCancel?()
                case .add: self?.addTapped()
                default: break
                }
            }
            .store(in: &cancellables)

        directionSegment.onChange = { [weak self] index in
            self?.setActiveDirection(index == 0 ? .before : .after)
        }
    }

    private func setupGrids() {
        beforeGrid.onSelectPhoto = { [weak self] photoDetails, index, selectedIds in
            self?.onSelectPhoto?(photoDetails, index, selectedIds)
        }
        afterGrid.onSelectPhoto = { [weak self] photoDetails, index, selectedIds in
            self?.onSelectPhoto?(photoDetails, index, selectedIds)
        }
        beforeViewModel.onSelectionChanged = { [weak self] in self?.updateAddButtonState() }
        afterViewModel.onSelectionChanged = { [weak self] in self?.updateAddButtonState() }
    }

    private func updateAddButtonState() {
        let hasSelection = !beforeViewModel.selectedIds.isEmpty || !afterViewModel.selectedIds.isEmpty
        naviView.setEnabled(hasSelection, for: .add)
    }

    // MARK: - Actions

    private func setActiveDirection(_ direction: ActiveDirection) {
        guard direction != activeDirection else { return }
        activeDirection = direction
        let offsetX = direction == .before ? 0 : pagingScrollView.bounds.width
        pagingScrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
    }

    private func addTapped() {
        guard !isCommitting else { return }
        isCommitting = true
        Task {
            do {
                let allSelected = beforeViewModel.selectedPhotos + afterViewModel.selectedPhotos
                try await detailUseCase.addPhotosToAlbum(albumId: albumId, photos: allSelected)
                onFinish?()
            } catch {
                debugLog("🐛 사진 추가 commit 실패: \(error)")
            }
            isCommitting = false
        }
    }

    // MARK: - 상세(뷰어) 연동

    // 상세(뷰어)에서 선택 상태를 바꾸고 돌아왔을 때 호출 — 탭 당시 보이던(활성) 그리드로만 온 것이므로 그쪽에 반영
    func syncSelection(_ identifiers: Set<String>) {
        activeGrid.syncSelection(identifiers)
    }

    func scrollToItem(id: String) {
        activeGrid.scrollToItem(id: id)
    }

    private var activeGrid: TravelPhotoGridView {
        activeDirection == .before ? beforeGrid : afterGrid
    }
}
