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

    /// 탭바(TabbarCoordinator)에서 이 화면 하나만 담은 새 네비게이션 컨트롤러를 모달로 띄우는
    /// 방식으로 쓰이므로, "뒤로"는 pop이 아니라 그 모달 자체를 닫는 것이어야 한다.
    private func dismiss() {
        navigationController.dismiss(animated: true)
        self.remove(coordinator: self)
    }
}
