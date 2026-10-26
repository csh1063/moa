//
//  AlbumDetailViewController.swift
//  Presentation
//
//  Created by sanghyeon on 3/26/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//
//

import UIKit
import SnapKit
import Combine
import Domain

enum AlbumDetailPageMode {
    case list
    case select
    case onlySelect
    /// 대표(커버) 사진 고르기 — 탭한 사진이 바로 대표로 저장되고 모드가 끝난다(다중 선택 아님)
    case pickCover
}

final class AlbumDetailViewController: BaseViewController {

    // MARK: - UI

    private var naviView = NaviBarView(type: .title(.leading))

    private lazy var collectionView: UICollectionView = {
        let space: CGFloat = 2
        let count: CGFloat = 3
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = .zero
        layout.minimumLineSpacing = space
        layout.minimumInteritemSpacing = space
        let width = (UIScreen.main.bounds.width - (space * (count + 1))) / count
        layout.itemSize = CGSize(width: width, height: width)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isScrollEnabled = true
        cv.showsVerticalScrollIndicator = false
        cv.contentInset = UIEdgeInsets(top: 8, left: space, bottom: 80, right: space)
        cv.backgroundColor = .clear
        return cv
    }()

    private let bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = Theme.background
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.08
        v.layer.shadowOffset = CGSize(width: 0, height: -2)
        v.layer.shadowRadius = 8
        return v
    }()

    private let deleteButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(named: "lucide_trash_2", in: .module, with: nil)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.negative
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        return btn
    }()

    /// 얼굴 앨범에서만 노출 — 선택한 사진을 이 인물 앨범에서 분리(블랙리스트 처리)
    private let excludeButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(named: "lucide_user_x", in: .module, with: nil)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        return btn
    }()

    private let selectedCountLabel: UILabel = {
        let lb = UILabel()
        lb.textColor = Theme.textSecondary
        lb.font = .systemFont(ofSize: 14, weight: .regular)
        lb.text = String(localized: "0개 선택", bundle: .module)
        return lb
    }()

    private let shareButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(named: "lucide_share_2", in: .module, with: nil)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        return btn
    }()

    /// 여행 앨범 전용 — 날짜순/분류순 토글
    private lazy var modeSegmentedControl = UISegmentedControl(items: [
        String(localized: "날짜순", bundle: .module),
        String(localized: "분류순", bundle: .module)
    ])

    private let categoryScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let categoryStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        return stack
    }()

    // MARK: - Properties

    private var dataSource: UICollectionViewDiffableDataSource<Int, PhotoCellItemViewModel>!
    private let viewModel: AlbumDetailViewModel
    private var cancellables = Set<AnyCancellable>()

    // 앨범 이름은 사용자가 정하는 값이라 카디널리티가 무한대라 분석 화면 이름으로 부적합 —
    // 고정된 화면 식별자로 트래킹한다
    override var pageTitle: String? { "앨범 상세" }

    private var pageMode: AlbumDetailPageMode = .list {
        didSet { updateModeUI() }
    }
    /// 분류순에서 "선택"을 눌렀을 때 날짜순으로 돌려놓을지 판단하는 용도로 로컬에도 들고 있는다
    private var currentDisplayTab: AlbumDetailViewModel.DisplayTab = .date
    private var isSelectionMode: Bool { pageMode != .list }
    /// 여러 장을 체크해서 지우기/제외하기 같은 "다중 선택" UI(체크박스, 하단 바)가 필요한 모드인지 —
    /// pickCover는 탭 한 번으로 바로 끝나는 단일 동작이라 여기 포함하지 않는다
    private var isMultiSelectMode: Bool { pageMode == .select || pageMode == .onlySelect }
    private(set) var selectedIdentifiers: Set<String> = []
    /// 대표 사진 고르기 그리드에서 "대표" 태그를 어느 셀에 붙일지 판단하는 기준
    private var currentCoverId: String? {
        didSet { refreshCoverTags() }
    }
    private var travelerInfo: AlbumDetailViewModel.TravelerInfo? {
        // reloadData()는 사진 셀까지 전부 다시 그려서 깜빡였다 — 헤더가 이미 떠 있으면 그 뷰의 텍스트만
        // 직접 바꾸고, 크기 재계산만 invalidateLayout으로 처리한다 (사진 셀은 전혀 안 건드림).
        // 헤더가 아직 없던 상태(처음 생기는 경우)는 supplementaryViewProvider가 나중에 만들어질 때
        // 이 시점의 최신 값을 그대로 읽어가므로 별도 처리가 필요 없다
        didSet {
            if let info = travelerInfo,
               let header = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader).first as? TravelerHeaderView {
                header.configure(name: info.name, count: info.count)
            }
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: - Init

    init(viewModel: AlbumDetailViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError(Self.fatalMessage)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupBindings()
        viewModel.send(.appear)
    }

    // MARK: - Setup

    private func setupView() {
        naviView.addButtons([LeftButton(type: .back), RightButton(type: .select), RightButton(type: .more)])
        configureDataSource()
        collectionView.delegate = self

        view.addSubview(naviView)
        view.addSubview(collectionView)
        view.addSubview(categoryScrollView)
        categoryScrollView.addSubview(categoryStackView)
        view.addSubview(bottomBar)
        bottomBar.addSubview(selectedCountLabel)
        bottomBar.addSubview(excludeButton)
        bottomBar.addSubview(deleteButton)
        bottomBar.addSubview(shareButton)

        naviView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        // 여행 앨범일 때만 날짜순/분류순 토글을 끼워 넣는다 — 분류순 더보기로 들어간 화면(실제
        // 앨범 아님, isTravelAlbum == false)은 토글 없이 기존처럼 바로 그리드가 나온다
        if viewModel.isTravelAlbum {
            // UISegmentedControl은 기본값이 0이 아니라 -1(선택 없음)이다 — 이걸 명시적으로 0(날짜순)으로
            // 맞춰두지 않으면, 아래 selectedPublisher 구독이 이 -1을 그대로 읽어서 "분류순"으로 오인하고
            // 그걸 ViewModel에 보내버려 화면이 항상 분류순으로 잘못 시작하는 버그가 있었다
            modeSegmentedControl.selectedSegmentIndex = 0
            view.addSubview(modeSegmentedControl)
            modeSegmentedControl.snp.makeConstraints { make in
                make.top.equalTo(naviView.snp.bottom).offset(8)
                make.leading.trailing.equalToSuperview().inset(16)
            }
            collectionView.snp.makeConstraints { make in
                make.top.equalTo(modeSegmentedControl.snp.bottom).offset(8)
                make.leading.trailing.bottom.equalToSuperview()
            }
            categoryScrollView.snp.makeConstraints { make in
                make.top.equalTo(modeSegmentedControl.snp.bottom).offset(8)
                make.leading.trailing.bottom.equalToSuperview()
            }
        } else {
            collectionView.snp.makeConstraints { make in
                make.top.equalTo(naviView.snp.bottom)
                make.leading.trailing.bottom.equalToSuperview()
            }
            categoryScrollView.snp.makeConstraints { make in
                make.top.equalTo(naviView.snp.bottom)
                make.leading.trailing.bottom.equalToSuperview()
            }
        }
        categoryStackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
            make.width.equalTo(categoryScrollView).offset(-32)
        }

        bottomBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(88)
        }
        selectedCountLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview().offset(-10)
        }
        deleteButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalToSuperview().offset(-10)
            make.height.equalTo(44)
            make.width.equalTo(44)
        }
        excludeButton.snp.makeConstraints { make in
            make.trailing.equalTo(deleteButton.snp.leading).offset(-12)
            make.centerY.equalTo(deleteButton)
            make.height.equalTo(44)
            make.width.equalTo(44)
        }
        shareButton.snp.makeConstraints { make in
            make.trailing.equalTo(excludeButton.snp.leading).offset(-12)
            make.centerY.equalTo(deleteButton)
            make.height.equalTo(44)
            make.width.equalTo(44)
        }

        bottomBar.isHidden = true
        categoryScrollView.isHidden = true
        excludeButton.isHidden = !viewModel.isFaceAlbum
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        excludeButton.addTarget(self, action: #selector(excludeButtonTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
    }

    private func setupBindings() {
        let output = viewModel.transform()

        output.name
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in self?.naviView.setTitle(name) }
            .store(in: &cancellables)

        output.photos
            .receive(on: DispatchQueue.main)
            .map { [weak self] photos -> [PhotoCellItemViewModel] in
                guard let self else { return [] }
                // 얼굴 크롭 디버깅용 로더는 FaceAlbumImageLoader(viewModel: self.viewModel)로 잠깐 바꿔서 테스트 가능
                let imageLoader: any ImageLoadable = self.viewModel
//                let imageLoader: any ImageLoadable = self.viewModel.isFaceAlbum
//                    ? FaceAlbumImageLoader(viewModel: self.viewModel)
//                    : self.viewModel
                return photos.map { PhotoCellItemViewModel(localIdentifier: $0.localIdentifier, imageLoader: imageLoader, isVideo: $0.isVideo) }
            }
            .sink { [weak self] photos in self?.applySnapshot(with: photos) }
            .store(in: &cancellables)

        output.selectionMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self, pageMode == .list else { return }
                enterMode(mode)
            }
            .store(in: &cancellables)

        output.coverPhotoIdentifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in self?.currentCoverId = id }
            .store(in: &cancellables)

        output.travelerInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in self?.travelerInfo = info }
            .store(in: &cancellables)

        output.displayTab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in
                guard let self else { return }
                currentDisplayTab = tab
                modeSegmentedControl.selectedSegmentIndex = tab == .date ? 0 : 1
                collectionView.isHidden = tab == .category
                categoryScrollView.isHidden = tab == .date
            }
            .store(in: &cancellables)

        output.categorySections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sections in
                guard let self else { return }
                categoryStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
                for section in sections {
                    let row = CompanionCategoryRowView()
                    row.configure(section: section, imageLoader: viewModel)
                    row.onTapMore = { [weak self] in
                        self?.viewModel.send(.tapMore(sectionId: section.id))
                    }
                    categoryStackView.addArrangedSubview(row)
                }
            }
            .store(in: &cancellables)

        if viewModel.isTravelAlbum {
            modeSegmentedControl.selectedPublisher
                .sink { [weak self] index in
                    // selectedSegmentIndex는 output.displayTab 바인딩에서도 코드로 세팅하는데, 그것도
                    // KVO라 여기로 다시 흘러든다 — 실제로 값이 바뀐 경우(사용자가 탭한 경우)에만 보내서
                    // 무한 루프를 끊는다
                    guard let self else { return }
                    let tab: AlbumDetailViewModel.DisplayTab = index == 0 ? .date : .category
                    guard tab != currentDisplayTab else { return }
                    viewModel.send(.switchTab(tab))
                }
                .store(in: &cancellables)
        }

        bindNaviActions()
    }

    private func bindNaviActions() {
        naviView.publisher
            .sink { [weak self] type in
                guard let self else { return }
                switch type {
                case .back:   viewModel.send(.dismiss)
                case .more:   viewModel.send(.more)
                case .select:
                    // 분류순(가로 줄 여러 개)은 체크박스로 고를 수 있는 단일 그리드가 아니라서,
                    // 선택 모드로 들어가기 전에 팝업 없이 날짜순으로 돌려놓는다
                    if currentDisplayTab == .category {
                        viewModel.send(.enterSelectModeFromCategoryTab)
                    }
                    viewModel.changeMode(.select)
                case .cancel: exitSelectionMode()
                default: break
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Mode

    func enterMode(_ mode: AlbumDetailPageMode) {
        guard mode != .list else { return }
        pageMode = mode
        // pickCover는 체크박스로 여러 장 고르는 게 아니라 탭 한 번으로 바로 끝나서 editing 모드가 필요 없다
        collectionView.isEditing = mode != .pickCover
    }

    func exitSelectionMode() {
        selectedIdentifiers.removeAll()
        pageMode = .list
        collectionView.isEditing = false
        updateSelectedCount()
    }

    // viewer에서 선택 상태 동기화
    func syncSelection(_ identifiers: Set<String>) {
        selectedIdentifiers = identifiers
        updateSelectedCount()
        collectionView.visibleCells.forEach { cell in
            guard let photoCell = cell as? PhotoCell,
                  let indexPath = collectionView.indexPath(for: photoCell),
                  let item = dataSource.itemIdentifier(for: indexPath) else { return }
            photoCell.setSelected(selectedIdentifiers.contains(item.localIdentifier))
        }
    }

    private func updateModeUI() {
        bottomBar.isHidden = !isMultiSelectMode

        switch pageMode {
        case .list:
            collectionView.allowsMultipleSelection = false
            collectionView.allowsMultipleSelectionDuringEditing = false
            naviView.addButtons([LeftButton(type: .back), RightButton(type: .select), RightButton(type: .more)])
            naviView.setMessage("")
        case .select:
            collectionView.allowsMultipleSelection = true
            collectionView.allowsMultipleSelectionDuringEditing = true
            naviView.addButtons([LeftButton(type: .back), RightButton(type: .cancel)])
        case .onlySelect:
            collectionView.allowsMultipleSelection = true
            collectionView.allowsMultipleSelectionDuringEditing = true
            naviView.addButtons([LeftButton(type: .back), RightButton(type: .more)])
        case .pickCover:
            collectionView.allowsMultipleSelection = false
            collectionView.allowsMultipleSelectionDuringEditing = false
            naviView.addButtons([LeftButton(type: .back), RightButton(type: .cancel)])
            naviView.setMessage(
                String(localized: "대표로 쓸 사진을 선택해주세요", bundle: .module),
                color: Theme.textSecondary,
                font: .systemFont(ofSize: 13)
            )
        }

        bindNaviActions()

        collectionView.visibleCells.forEach { cell in
            guard let photoCell = cell as? PhotoCell else { return }
            photoCell.setSelectionMode(isMultiSelectMode)
        }
        refreshCoverTags()
    }

    /// 대표 사진 고르기 모드일 때만, 지금 이미 대표로 저장돼 있는 사진 셀에 "대표" 태그를 붙이고
    /// 영상 셀은 고를 수 없게 흐리게 표시한다
    private func refreshCoverTags() {
        collectionView.visibleCells.forEach { cell in
            guard let photoCell = cell as? PhotoCell,
                  let indexPath = collectionView.indexPath(for: photoCell),
                  let item = dataSource.itemIdentifier(for: indexPath) else { return }
            photoCell.setCoverTag(pageMode == .pickCover && item.localIdentifier == currentCoverId)
            photoCell.alpha = (pageMode == .pickCover && item.isVideo) ? 0.35 : 1.0
        }
    }

    private func updateSelectedCount() {
        let count = selectedIdentifiers.count
        selectedCountLabel.text = String(localized: "\(count)개 선택", bundle: .module)
        deleteButton.isEnabled = count > 0
        deleteButton.alpha = count > 0 ? 1.0 : 0.4
        excludeButton.isEnabled = count > 0
        excludeButton.alpha = count > 0 ? 1.0 : 0.4
        shareButton.isEnabled = count > 0
        shareButton.alpha = count > 0 ? 1.0 : 0.4
    }

    // MARK: - Actions

    @objc private func deleteButtonTapped() {
        guard !selectedIdentifiers.isEmpty else { return }
        viewModel.send(.deleteSelected(ids: Array(selectedIdentifiers)))
    }

    @objc private func excludeButtonTapped() {
        guard !selectedIdentifiers.isEmpty else { return }
        viewModel.send(.excludeSelected(ids: Array(selectedIdentifiers)))
    }

    @objc private func shareButtonTapped() {
        guard !selectedIdentifiers.isEmpty else { return }
        viewModel.send(.shareSelected(ids: Array(selectedIdentifiers)))
    }

    // MARK: - Scroll

    func scrollToItem(id: String) {
        let snapshot = dataSource.snapshot()
        for (sectionIndex, section) in snapshot.sectionIdentifiers.enumerated() {
            let items = snapshot.itemIdentifiers(inSection: section)
            if let itemIndex = items.firstIndex(where: { $0.localIdentifier == id }) {
                collectionView.scrollToItem(at: IndexPath(item: itemIndex, section: sectionIndex), at: .centeredVertically, animated: false)
                return
            }
        }
    }
}

// MARK: - DataSource

extension AlbumDetailViewController {
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<PhotoCell, PhotoCellItemViewModel> { [weak self] cell, indexPath, cellViewModel in
            guard let self else { return }
            cell.configure(with: cellViewModel, index: indexPath.row)
            cell.setSelectionMode(isMultiSelectMode)
            cell.setSelected(selectedIdentifiers.contains(cellViewModel.localIdentifier))
            cell.setCoverTag(pageMode == .pickCover && cellViewModel.localIdentifier == currentCoverId)
            // 대표 사진 고르기 모드에서는 영상을 고를 수 없다 — 흐리게 표시해서 선택 불가임을 알려준다
            cell.alpha = (pageMode == .pickCover && cellViewModel.isVideo) ? 0.35 : 1.0

//            // 셀 탭 → viewer 열기
//            cell.cellTapPublisher
//                .sink { [weak self] in
//                    self?.viewModel.send(.selectItem(id: cellViewModel.localIdentifier, inSelectionMode: self?.isSelectionMode ?? false))
//                }
//                .store(in: &cancellables)

            cell.onImageTap = { [weak self] in
                guard let self else { return }
                if pageMode == .pickCover {
                    // 영상은 대표 사진으로 고를 수 없다
                    guard !cellViewModel.isVideo else {
                        viewModel.send(.tappedVideoAsCoverCandidate)
                        return
                    }
                    // 바로 적용하지 않고 미리보기부터 — 그리드는 그대로 pickCover 모드에 남아있는다
                    // (취소하면 다시 고를 수 있도록). 실제 적용/모드 종료는 미리보기의 "선택" 확정 후에만
                    viewModel.send(.selectCoverCandidate(id: cellViewModel.localIdentifier))
                    return
                }
                viewModel.send(.selectItem(id: cellViewModel.localIdentifier, inSelectionMode: isSelectionMode))
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Int, PhotoCellItemViewModel>(collectionView: collectionView) { cv, indexPath, vm in
            cv.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: vm)
        }

        collectionView.register(
            TravelerHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: TravelerHeaderView.reuseIdentifier
        )
        dataSource.supplementaryViewProvider = { [weak self] cv, kind, indexPath in
            guard let self, kind == UICollectionView.elementKindSectionHeader,
                  let info = self.travelerInfo,
                  let header = cv.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: TravelerHeaderView.reuseIdentifier,
                    for: indexPath
                  ) as? TravelerHeaderView else {
                return nil
            }
            header.configure(name: info.name, count: info.count)
            return header
        }
    }

    private func applySnapshot(with photos: [PhotoCellItemViewModel]) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, PhotoCellItemViewModel>()
        snapshot.appendSections([0])
        snapshot.appendItems(photos)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}

// MARK: - UICollectionViewDelegate

extension AlbumDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard isMultiSelectMode,
              let item = dataSource.itemIdentifier(for: indexPath),
              let cell = collectionView.cellForItem(at: indexPath) as? PhotoCell else { return }

        selectedIdentifiers.insert(item.localIdentifier)
        cell.setSelected(true)
        updateSelectedCount()
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard isMultiSelectMode,
              let item = dataSource.itemIdentifier(for: indexPath),
              let cell = collectionView.cellForItem(at: indexPath) as? PhotoCell else { return }

        selectedIdentifiers.remove(item.localIdentifier)
        cell.setSelected(false)
        updateSelectedCount()
    }

    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return isMultiSelectMode
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension AlbumDetailViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard let info = travelerInfo else { return .zero }
        let height = TravelerHeaderView.height(for: info.name, width: collectionView.bounds.width)
        return CGSize(width: collectionView.bounds.width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        if pageMode == .list { enterMode(.select) }
    }
}
