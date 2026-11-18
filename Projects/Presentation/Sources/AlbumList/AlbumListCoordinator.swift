//
//  AlbumListCoordinator.swift
//  Presentation
//
//  Created by sanghyeon on 6/19/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Domain

@MainActor
public final class AlbumListCoordinator: BaseCoordinator {

    private let diContainer: AlbumListDIContainer
    private let navigationController: UINavigationController

    weak var delegate: AlbumDetailViewModelDelegate?

    /// 길게 누르기 메뉴의 코디네이터를 붙잡아 둔다(상세 화면이 아니라 자식 목록에 안 들어간다)
    private var albumMenuCoordinator: AlbumDetailCoordinator?

    init(diContainer: AlbumListDIContainer,
         navigationController: UINavigationController) {
        self.diContainer = diContainer
        self.navigationController = navigationController

        super.init()
    }

    public override func start() {
        let viewModel = diContainer.makeAlbumListViewModel()
//        self.delegate = viewModel
        viewModel.onAction = { [weak self] type in
            switch type {
            case .moveDetail(let album):
                self?.moveDetail(album: album, isSelectMode: album.from == "similar")
            case .pop:
                self?.pop()
            case .showAlbumMenu(let album):
                self?.showAlbumMenu(album: album)
            case .presentLibraryImportPicker:
                self?.presentLibraryImportPicker()
            default: break
            }
        }

        bindAlert(from: viewModel)

        let vc = AlbumListViewController(viewModel: viewModel)

        navigationController.pushViewController(vc, animated: true)
        self.viewController = vc
    }

    private func pop() {
        navigationController.popViewController(animated: true)
        self.remove(coordinator: self)
    }

    func moveDetail(album: Album, isSelectMode: Bool) {
        let detailDI = diContainer.makeDetailDIContainer(album: album, isSelectMode: isSelectMode)

        let detailCoordinator = AlbumDetailCoordinator(
            diContainer: detailDI,
            navigationController: self.navigationController
        )
        self.hideTabBar?()
        self.start(coordinator: detailCoordinator)
    }

    private func presentLibraryImportPicker() {
        let useCase = diContainer.makeLibraryAlbumImportUseCase()
        let modalNav = UINavigationController()
        let importCoordinator = LibraryAlbumPickerCoordinator(useCase: useCase, navigationController: modalNav)
        self.start(coordinator: importCoordinator)
        navigationController.present(modalNav, animated: true)
    }

    /// 앨범을 길게 눌렀을 때 — 앨범 상세의 "..." 버튼과 완전히 동일한 메뉴를 상세 화면 진입 없이 띄운다.
    func showAlbumMenu(album: Album) {
        let detailDI = diContainer.makeDetailDIContainer(album: album, isSelectMode: false)
        let detailCoordinator = AlbumDetailCoordinator(
            diContainer: detailDI,
            navigationController: self.navigationController
        )
        self.albumMenuCoordinator = detailCoordinator
        detailCoordinator.presentAlbumMenu(album: album)
    }
}
