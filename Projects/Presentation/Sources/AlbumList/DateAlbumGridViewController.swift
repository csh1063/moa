//
//  DateAlbumGridViewController.swift
//  Presentation
//
//  Created by sanghyeon on 9/7/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Combine
import Domain

/// "시간" 모두보기 — date 앨범은 연도 단위라 카드 리스트로 만들면 몇 장 안 되고, 유효한 날짜가 있는
/// 사진은 사실상 전부 어떤 date 앨범엔가 들어간다. 그래서 사진첩 탭(PhotoLibraryViewController)과
/// 같은 "월별 섹션 헤더 + 핀치줌 그리드" 화면을 그대로 재사용하되, 탭 루트가 아니라 뒤로가기가 있는
/// 푸시 화면이라 헤더만 다르게 구성한다. ViewModel은 PhotoLibraryViewModel을 그대로 쓴다.
final class DateAlbumGridViewController: BaseViewController {

    private let naviView = NaviBarView()

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<PhotoHeader, PhotoCellItemViewModel>!

    private var columnCount: Int = 3
    private var pinchBeginScale: CGFloat = 1.0

    /// 월별 섹션 접기/펼치기 — 서버에서 다시 받아오는 게 아니라 로컬 UI 상태라 title로만 식별한다
    private var collapsedSectionTitles: Set<String> = []
    private var latestPhotos: [PhotoHeader: [PhotoCellItemViewModel]] = [:]

    private let viewModel: PhotoLibraryViewModel

    private var cancellables = Set<AnyCancellable>()

    override var pageTitle: String? { "시간" }

    var onBack: (() -> Void)?

    init(viewModel: PhotoLibraryViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError(Self.fatalMessage)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupView()
        self.bindings()
        self.setupPinchGesture()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.viewModel.send(.permission)
    }

    private func setupView() {

        naviView.setTitle(String(localized: "시간", bundle: .module))
        naviView.addButtons([LeftButton(type: .back)])

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: createDynamicLayout(columns: columnCount))
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Theme.background
        collectionView.delegate = self

        configureDataSource()

        view.addSubview(naviView)
        view.addSubview(collectionView)

        naviView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalTo(self.view)
        }

        collectionView.snp.makeConstraints { make in
            make.top.equalTo(self.naviView.snp.bottom)
            make.leading.trailing.bottom.equalTo(self.view)
        }
    }

    private func bindings() {
        naviView.publisher.sink { [weak self] type in
            guard let self, type == .back else { return }
            self.onBack?()
        }
        .store(in: &cancellables)

        let output = self.viewModel.transform()

        output.photos
            .receive(on: DispatchQueue.main)
            .sink { [weak self] photos in
                self?.applySnapshot(with: photos)
            }
            .store(in: &cancellables)

        output.photoPermission
            .sink { [weak self] permission in
                if permission.access {
                    self?.viewModel.send(.appear)
                }
            }
            .store(in: &cancellables)
    }

    private func setupPinchGesture() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        collectionView.addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchBeginScale = gesture.scale

        case .changed:
            let scale = gesture.scale / pinchBeginScale
            let newLayout = createDynamicLayout(columns: columnCount, scale: scale)
            collectionView.setCollectionViewLayout(newLayout, animated: false)

            if scale < 0.65 && columnCount < 11 {
                columnCount += 2
                pinchBeginScale = gesture.scale
            } else if scale > 1.35 && columnCount > 1 {
                columnCount = max(1, columnCount - 2)
                pinchBeginScale = gesture.scale
            }

        case .ended, .cancelled:
            let scale = gesture.scale / pinchBeginScale
            let isZoomingIn = scale > 1.0

            collectionView.setCollectionViewLayout(
                createDynamicLayout(columns: columnCount),
                animated: isZoomingIn
            )
        default:
            break
        }
    }

    private func createDynamicLayout(columns: Int, scale: CGFloat = 1.0) -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, env in
            let spacing = 4.0
            let sectionInset = 4.0
            let baseCount = CGFloat(columns)
            let isZoomingIn = scale >= 1.0

            let progress = isZoomingIn
                ? min((scale - 1.0) / 0.6, 1.0)
                : min((1.0 - scale) / 0.6, 1.0)

            let dynamicColumnCount = isZoomingIn
                ? baseCount
                : baseCount + (progress * 2.0)

            let contentWidth = env.container.contentSize.width - (sectionInset * 2) - (spacing * (dynamicColumnCount - 1))

            let groupHeight: CGFloat
            let sideItemWidth: CGFloat
            let normalItemWidth: CGFloat
            let startX: CGFloat

            if isZoomingIn {
                sideItemWidth = (contentWidth / baseCount) * progress
                normalItemWidth = (contentWidth + sideItemWidth * 2) / baseCount
                groupHeight = normalItemWidth
                startX = -sideItemWidth
            } else {
                groupHeight = contentWidth / dynamicColumnCount
                let targetCount = baseCount + 2.0
                sideItemWidth = (contentWidth / targetCount) * progress
                normalItemWidth = (contentWidth - sideItemWidth * 2) / baseCount
                startX = 0
            }

            let totalItemsInRow = isZoomingIn ? Int(baseCount) : Int(baseCount) + 2

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(groupHeight)
            )

            let group = NSCollectionLayoutGroup.custom(layoutSize: groupSize) { _ in
                var items = [NSCollectionLayoutGroupCustomItem]()
                var currentX = startX

                for i in 0..<totalItemsInRow {
                    let isEdge = !isZoomingIn && (i == 0 || i == totalItemsInRow - 1)
                    let width = isEdge ? sideItemWidth : normalItemWidth
                    let frame = CGRect(
                        x: currentX + sectionInset,
                        y: spacing,
                        width: width,
                        height: groupHeight - spacing
                    )
                    items.append(NSCollectionLayoutGroupCustomItem(frame: frame))
                    currentX += width + spacing
                }
                return items
            }

            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(50)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            header.pinToVisibleBounds = true
            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [header]
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0)

            return section
        }
    }

    func scrollToItem(id: String) {
        let snapshot = dataSource.snapshot()
        for (sectionIndex, section) in snapshot.sectionIdentifiers.enumerated() {
            let items = snapshot.itemIdentifiers(inSection: section)
            if let itemIndex = items.firstIndex(where: { $0.localIdentifier == id }) {
                let indexPath = IndexPath(item: itemIndex, section: sectionIndex)
                collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
                return
            }
        }
    }
}

extension DateAlbumGridViewController {
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<PhotoCell, PhotoCellItemViewModel> { cell, indexPath, cellViewModel in
            cell.configure(with: cellViewModel, index: indexPath.row)
            cell.onImageTap = { [weak self] in
                self?.viewModel.send(.selectItem(id: cellViewModel.localIdentifier))
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<PhotoSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, indexPath in
            guard let self else { return }
            let sections = Array(self.dataSource.snapshot().sectionIdentifiers)
            let section = sections[indexPath.section]
            headerView.configure(with: section)
            headerView.setCollapsible(isCollapsed: self.collapsedSectionTitles.contains(section.title), animated: false)
            headerView.onTap = { [weak self] in
                self?.toggleSection(section)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<PhotoHeader, PhotoCellItemViewModel>(collectionView: collectionView) {
            collectionView, indexPath, cellViewModel in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: cellViewModel)
        }

        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func applySnapshot(with photos: [PhotoHeader: [PhotoCellItemViewModel]]) {
        latestPhotos = photos
        applyCurrentSnapshot(animatingDifferences: true)
    }

    /// 접힌 섹션은 헤더만 남기고 아이템을 비워서 넣는다 — 섹션 자체를 스냅샷에서 빼면
    /// diffable data source가 헤더까지 통째로 없애버려서, 접었다 폈다 할 헤더가 사라져버린다.
    private func applyCurrentSnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<PhotoHeader, PhotoCellItemViewModel>()

        let sections: [PhotoHeader] = Array(latestPhotos.keys).sorted { $0.title > $1.title }

        snapshot.appendSections(sections)

        sections.forEach { section in
            let items = collapsedSectionTitles.contains(section.title) ? [] : (latestPhotos[section] ?? [])
            snapshot.appendItems(items, toSection: section)
        }

        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func toggleSection(_ section: PhotoHeader) {
        if collapsedSectionTitles.contains(section.title) {
            collapsedSectionTitles.remove(section.title)
        } else {
            collapsedSectionTitles.insert(section.title)
        }
        applyCurrentSnapshot(animatingDifferences: true)

        if let headerIndex = Array(dataSource.snapshot().sectionIdentifiers).firstIndex(where: { $0.title == section.title }),
           let headerView = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: headerIndex)
           ) as? PhotoSectionHeaderView {
            headerView.setCollapsible(isCollapsed: collapsedSectionTitles.contains(section.title), animated: true)
        }
    }
}

extension DateAlbumGridViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cellViewModel = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.send(.selectItem(id: cellViewModel.localIdentifier))
    }
}
