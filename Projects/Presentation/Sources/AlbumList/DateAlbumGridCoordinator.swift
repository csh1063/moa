//
//  DateAlbumGridCoordinator.swift
//  Presentation
//
//  Created by sanghyeon on 9/7/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Domain

@MainActor
public final class DateAlbumGridCoordinator: BaseCoordinator {

    private let diContainer: PhotoLibraryDIContainer
    private let tabbarViewModel: TabbarViewModel
    private let navigationController: UINavigationController

    init(diContainer: PhotoLibraryDIContainer,
         tabbarViewModel: TabbarViewModel,
         navigationController: UINavigationController) {
        self.diContainer = diContainer
        self.tabbarViewModel = tabbarViewModel
        self.navigationController = navigationController

        super.init()
    }

    public override func start() {
        let viewModel = diContainer.makePhotoLibraryViewModel(tabbarViewModel: tabbarViewModel)
        viewModel.onAction = { [weak self] action in
            switch action {
            case .selectPhoto(let photoDetails, let index):
                self?.showDetail(photoDetails, index: index)
            }
        }

        let vc = DateAlbumGridViewController(viewModel: viewModel)
        vc.onBack = { [weak self] in
            self?.pop()
        }

        navigationController.pushViewController(vc, animated: true)
        self.viewController = vc
    }

    private func pop() {
        navigationController.popViewController(animated: true)
        self.remove(coordinator: self)
    }

    private func showDetail(_ photoDetails: [PhotoDetail], index: Int) {
        let vm = diContainer.makeImageViewerViewModel(photoDetails: photoDetails, index: index)
        vm.onAction = { [weak self] action in
            switch action {
            case .pageChanged(let id):
                (self?.viewController as? DateAlbumGridViewController)?.scrollToItem(id: id)
            case .selectionChanged: break
            }
        }
        let vc = ImageViewerViewController(viewModel: vm)

        navigationController.present(vc, animated: true)
    }
}
