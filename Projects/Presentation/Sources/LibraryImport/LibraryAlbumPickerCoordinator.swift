//
//  LibraryAlbumPickerCoordinator.swift
//  Presentation
//
//  Created by sanghyeon on 9/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Domain

@MainActor
final class LibraryAlbumPickerCoordinator: BaseCoordinator {

    private let useCase: LibraryAlbumImportUseCase
    private let navigationController: UINavigationController

    init(useCase: LibraryAlbumImportUseCase, navigationController: UINavigationController) {
        self.useCase = useCase
        self.navigationController = navigationController

        super.init()
    }

    override func start() {
        let viewModel = LibraryAlbumPickerViewModel(useCase: useCase)
        viewModel.onAction = { [weak self] type in
            switch type {
            case .pop:
                self?.dismiss()
            }
        }

        bindAlert(from: viewModel)

        let vc = LibraryAlbumPickerViewController(viewModel: viewModel)
        self.viewController = vc
        navigationController.pushViewController(vc, animated: true)
    }

    /// 모달로 띄운 화면이라 "뒤로"는 모달을 닫는다
    private func dismiss() {
        navigationController.dismiss(animated: true)
        self.remove(coordinator: self)
    }
}
