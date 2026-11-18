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

    private let shareButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(named: "lucide_share_2", in: .module, with: nil)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        btn.isHidden = true  // 공유 버튼 숨김 — 다시 켤 때 지운다
        return btn
    }()

    private let selectedCountLabel: UILabel = {
        let lb = UILabel()
        lb.textColor = Theme.textSecondary
        lb.font = .systemFont(ofSize: 14, weight: .regular)
        lb.text = String(localized: "0개 선택", bundle: .module)
        return lb
    }()

    /// 여행 앨범 전용 — 날짜순/분류순 토글
    private lazy var modeSegmentedControl = PillSegmentedControl(items: [
        String(localized: "날짜순", bundle: .module),
        String(localized: "분류순", bundle: .module)
    ])

    private let categoryScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let categoryLoadingView: CardStackLoadingView = {
        let view = CardStackLoadingView()
        view.isHidden = true
        return view
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

    // 앨범 이름은 사용자 입력이라 고정된 화면 이름으로 트래킹한다
    override var pageTitle: String? { "앨범 상세" }

    private var pageMode: AlbumDetailPageMode = .list {
        didSet { updateModeUI() }
    }
    /// 분류순에서 "선택"을 눌렀을 때 날짜순으로 돌려놓을지 판단하는 용도로 로컬에도 들고 있는다
    private var currentDisplayTab: AlbumDetailViewModel.DisplayTab = .date
    private var isSelectionMode: Bool { pageMode != .list }
    /// 체크박스와 하단바가 필요한 다중 선택 모드인지 — pickCover는 단일 탭 동작이라 제외
    private var isMultiSelectMode: Bool { pageMode == .select || pageMode == .onlySelect }
    private(set) var selectedIdentifiers: Set<String> = []
    /// 대표 사진 고르기 그리드에서 "대표" 태그를 어느 셀에 붙일지 판단하는 기준
    private var currentCoverId: String? {
        didSet { refreshCoverTags() }
    }
    private var travelerInfo: AlbumDetailViewModel.TravelerInfo? {
        // 헤더가 있으면 텍스트만 바꾸고 레이아웃만 갱신한다(reloadData는 셀이 깜빡인다)
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
        naviView.addButtons(listModeButtons)
        configureDataSource()
        collectionView.delegate = self

        view.addSubview(naviView)
        view.addSubview(collectionView)
        view.addSubview(categoryScrollView)
        categoryScrollView.addSubview(categoryStackView)
        categoryScrollView.addSubview(categoryLoadingView)
        view.addSubview(bottomBar)
        bottomBar.addSubview(selectedCountLabel)
        bottomBar.addSubview(shareButton)
        bottomBar.addSubview(excludeButton)
        bottomBar.addSubview(deleteButton)

        naviView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        // 여행 앨범일 때만 날짜순/분류순 토글
        if viewModel.isTravelAlbum {
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
        categoryLoadingView.snp.makeConstraints { make in
            make.center.equalTo(categoryScrollView.frameLayoutGuide)
            make.width.height.equalTo(60)
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
            // 제외 버튼은 인물 앨범에만 보인다 — 숨겨진 자리만큼 비지 않게 삭제 버튼 옆에 붙인다
            make.trailing.equalTo((viewModel.isFaceAlbum ? excludeButton : deleteButton).snp.leading).offset(-12)
            make.centerY.equalTo(deleteButton)
            make.height.equalTo(44)
            make.width.equalTo(44)
        }

        bottomBar.isHidden = true
        categoryScrollView.isHidden = true
        excludeButton.isHidden = !viewModel.isFaceAlbum
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
        excludeButton.addTarget(self, action: #selector(excludeButtonTapped), for: .touchUpInside)
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
                modeSegmentedControl.setSelectedIndex(tab == .date ? 0 : 1, animated: true)
                collectionView.isHidden = tab == .category
                categoryScrollView.isHidden = tab == .date
            }
            .store(in: &cancellables)

        output.categorySections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sections in
                guard let self else { return }
                // 계산이 끝나기 전엔 빈 화면 대신 로딩
                guard let sections else {
                    categoryLoadingView.isHidden = false
                    categoryLoadingView.startAnimating()
                    return
                }
                categoryLoadingView.stopAnimating()
                categoryLoadingView.isHidden = true
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
            modeSegmentedControl.onChange = { [weak self] index in
                self?.viewModel.send(.switchTab(index == 0 ? .date : .category))
            }
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
                    // 분류순은 선택할 그리드가 아니라서 날짜순으로 돌린 뒤 선택 모드로
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

    /// 분류순 "더보기" 화면은 실제 앨범이 아니라 "..." 메뉴가 없다
    private var listModeButtons: [NaviButtonSetting] {
        viewModel.hasOptionsMenu
            ? [LeftButton(type: .back), RightButton(type: .select), RightButton(type: .more)]
            : [LeftButton(type: .back), RightButton(type: .select)]
    }

    private func updateModeUI() {
        bottomBar.isHidden = !isMultiSelectMode

        switch pageMode {
        case .list:
            collectionView.allowsMultipleSelection = false
            collectionView.allowsMultipleSelectionDuringEditing = false
            naviView.addButtons(listModeButtons)
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

    /// 대표 사진 고르기 모드에서 현재 대표 사진에 "대표" 태그, 영상은 흐리게
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
                    // 바로 적용하지 않고 미리보기부터 — 확정은 미리보기의 "선택"에서
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
        let startedAt = Date()
        // 처음 채울 때와 다음 페이지를 붙일 때는 애니메이션 없이, 지워서 줄어들 때만 애니메이션
        let currentCount = dataSource.snapshot().numberOfItems
        dataSource.apply(snapshot, animatingDifferences: currentCount > 0 && photos.count < currentCount)
        debugLog("⏱️ [앨범 상세] 그리드 \(photos.count)장 반영 — \(String(format: "%.2f", Date().timeIntervalSince(startedAt)))초")
    }
}

// MARK: - UICollectionViewDelegate

extension AlbumDetailViewController: UICollectionViewDelegate {
    // 끝에서 60칸 전에 다음 페이지를 미리 읽는다
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.item >= collectionView.numberOfItems(inSection: indexPath.section) - 60 else { return }
        viewModel.send(.loadMore)
    }

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
