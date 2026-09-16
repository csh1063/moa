//
//  LocationMapCoordinator.swift
//  Presentation
//
//  Created by sanghyeon on 9/7/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Domain

@MainActor
public final class LocationMapCoordinator: BaseCoordinator {

    private let diContainer: AlbumListDIContainer
    private let navigationController: UINavigationController

    init(diContainer: AlbumListDIContainer,
         navigationController: UINavigationController) {
        self.diContainer = diContainer
        self.navigationController = navigationController

        super.init()
    }

    public override func start() {
        let viewModel = diContainer.makeLocationMapViewModel()
        viewModel.onAction = { [weak self] type in
            switch type {
            case .selectPhoto(let photoDetails, let index):
                self?.showDetail(photoDetails, index: index)
            case .pop:
                self?.pop()
            }
        }

        bindAlert(from: viewModel)

        let vc = LocationMapViewController(viewModel: viewModel)

        navigationController.pushViewController(vc, animated: true)
        self.viewController = vc
    }

    private func pop() {
        navigationController.popViewController(animated: true)
        self.remove(coordinator: self)
    }

    private func showDetail(_ photoDetails: [PhotoDetail], index: Int) {
        let vm = diContainer.makeImageViewerViewModel(photoDetails: photoDetails, index: index)
        let vc = ImageViewerViewController(viewModel: vm)

        navigationController.present(vc, animated: true)
    }
}
