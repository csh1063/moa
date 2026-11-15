//
//  MyPageCoordinator.swift
//  Presentation
//
//  Created by sanghyeon on 12/22/25.
//  Copyright © 2025 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import SafariServices

@MainActor
public final class MyPageCoordinator: BaseCoordinator {

    private let diContainer: MyPageDIContainer
    private let tabbarViewModel: TabbarViewModel
    private let navigationController = UINavigationController()

    init(diContainer: MyPageDIContainer, tabbarViewModel: TabbarViewModel) {
        self.diContainer = diContainer
        self.tabbarViewModel = tabbarViewModel

        super.init()
    }

    public override func start() {
        let viewModel = diContainer.makeMyPageViewModel(tabbarViewModel: tabbarViewModel)
        viewModel.onAction = { [weak self] action in
            switch action {
            case .move(let data):
                switch data.type {
                case .labels:
                    self?.moveLabels(isLabel: true)
                case .addressCount:
                    self?.moveLabels(isLabel: false)
                case .privacy:
                    let vc = WebDocuViewController(type: .privacy)
                    self?.hideTabBar?()
                    self?.navigationController.pushViewController(vc, animated: true)
                case .terms:
                    let vc = WebDocuViewController(type: .terms)
                    self?.hideTabBar?()
                    self?.navigationController.pushViewController(vc, animated: true)
                case .feedback:
                    self?.moveFeedback()
//                case .displayMode:
//                    let vc = OptionPickerViewController(
//                        title: "디스플레이 모드",
//                        options: DisplayMode.allCases.map {$0.text},
//                        selected: data.value
//                    )
//                    vc.onSelect = { [weak viewModel] selected in
//                        // 저장 버튼 눌렀을 때 여기서 selected 사용
//                        print("??")
//                        Task { @MainActor in
//                            print("?!")
//                            await viewModel?.changeDisplayMode(selected)
//                        }
//                    }
//                    self?.hideTabBar?()
//                    self?.navigationController.pushViewController(vc, animated: true)
                case .openSource:
                    let vc = OpenSourceViewController()
                    self?.hideTabBar?()
                    self?.navigationController.pushViewController(vc, animated: true)
                case .test:
                    self?.moveTest()
                case .frequentPlaces:
                    self?.moveFrequentPlaces()
                case .homeZone:
                    guard let self else { return }
                    let vc = self.diContainer.makeHomeZoneLabViewController()
                    self.hideTabBar?()
                    self.navigationController.pushViewController(vc, animated: true)
                default: break
                }
            }
        }

        let vc = MyPageViewController(viewModel: viewModel)

        bindAlert(from: viewModel)

        navigationController.delegate = self
        navigationController.viewControllers = [vc]
        self.viewController = vc
    }

    func startAndReturn() -> UINavigationController {
        start(coordinator: self)
        return navigationController
    }

    func moveFeedback() {
        let viewModel = diContainer.makeFeedbackViewModel()
        bindAlert(from: viewModel)
        let vc = FeedbackViewController(viewModel: viewModel)
        self.hideTabBar?()
        self.navigationController.pushViewController(vc, animated: true)
    }

    func moveLabels(isLabel: Bool) {
        let detailDI = diContainer.makeLabelsDIContainer(isLabel: isLabel)

        let detailCoordinator = LabelsCoordinator(
            diContainer: detailDI,
            navigationController: self.navigationController
        )
        self.hideTabBar?()
        self.start(coordinator: detailCoordinator)
    }

    func moveFrequentPlaces() {
        let viewModel = diContainer.makeFrequentPlaceListViewModel()
        bindAlert(from: viewModel)

        let listVC = FrequentPlaceListViewController(viewModel: viewModel)
        listVC.onTapAdd = { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            let start = viewModel.startLocation()
            let addVC = FrequentPlaceAddViewController(startLatitude: start.latitude, startLongitude: start.longitude)
            addVC.onSave = { [weak viewModel, weak addVC] latitude, longitude, title, address in
                Task { await viewModel?.add(latitude: latitude, longitude: longitude, title: title, address: address) }
                addVC?.dismiss(animated: true)
            }
            self.navigationController.present(addVC, animated: true)
        }
        listVC.onTapEdit = { [weak self, weak viewModel] row in
            guard let self else { return }
            let editVC = FrequentPlaceAddViewController(
                startLatitude: row.latitude,
                startLongitude: row.longitude,
                isEditMode: true,
                initialName: row.manualTitle
            )
            editVC.onSave = { [weak viewModel, weak editVC] latitude, longitude, title, address in
                Task { await viewModel?.update(id: row.id, latitude: latitude, longitude: longitude, title: title, address: address) }
                editVC?.dismiss(animated: true)
            }
            self.navigationController.present(editVC, animated: true)
        }
        // 동네가 바뀌어도 이미 만든 여행 앨범은 그대로라, 나갈 때 전체를 다시 만들지 물어본다
        listVC.onFinish = { [weak self] hasChanges in
            guard hasChanges, let self else { return }
            self.showAlert(
                title: String(localized: "여행 앨범을 다시 만들까요?", bundle: .module),
                message: String(localized: "바뀐 동네를 반영하려면 여행 앨범을 처음부터 다시 만들어야 해요\n직접 편집한 여행 앨범도 다시 만들어져요", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "나중에", bundle: .module), style: .cancel, action: nil),
                    AlertButtonConfig(title: String(localized: "다시 만들기", bundle: .module), style: .default) { [weak self] in
                        self?.tabbarViewModel.send(.rebuildTravelAlbums)
                    }
                ]
            )
        }

        hideTabBar?()
        navigationController.pushViewController(listVC, animated: true)
    }

    func moveTest() {
        let detailDI = diContainer.makePhotoTestDIContainer()

        let detailCoordinator = PhotoTestCoordinator(
            diContainer: detailDI,
            navigationController: self.navigationController
        )
        self.hideTabBar?()
        self.start(coordinator: detailCoordinator)
    }
}
