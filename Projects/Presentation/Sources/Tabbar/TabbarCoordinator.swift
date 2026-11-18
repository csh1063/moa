//
//  TabbarCoordinator.swift
//  Presentation
//
//  Created by sanghyeon on 12/22/25.
//  Copyright © 2025 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Combine
import Domain

@MainActor
final class TabbarCoordinator: BaseCoordinator {

    private let container: TabbarDIContainer
    private var tabbarViewController: TabbarViewController?
    private let window: UIWindow

    private var cancellables = Set<AnyCancellable>()

    /// 진행 표시 3단계: 1(시트) → 2(미니위젯) → 3(탭바 옆 배지). nil이면 진행 중인 분석 없음
    private enum ProgressTier {
        case sheet
        case mini
        case badge
    }
    private var currentTier: ProgressTier?
    private var currentAnalyzeProgress: AnalyzeProgress?
    private var isAnalysisComplete = false

    public init(container: TabbarDIContainer, window: UIWindow) {
        self.container = container
        self.window = window

        super.init()
    }

    public override func start() {

        let viewModel = container.makeTabbarViewModel()
        viewModel.onAction = { [weak self] type in
            switch type {
            case .progressSheet(let progress):
                self?.startAnalysisFlow(progress: progress)
            case .showLibraryImportPicker(let useCase):
                self?.presentLibraryImportPicker(useCase: useCase)
            case .analysisGuide(let isFirstAnalysis, let loadEstimate, let onStart):
                self?.presentAnalysisGuide(isFirstAnalysis: isFirstAnalysis, loadEstimate: loadEstimate, onStart: onStart)
            }
        }

        bindAlert(from: viewModel)

        self.tabbarViewController = TabbarViewController(viewModel: viewModel)
        // 미니위젯이 떠 있을 때 탭을 바꾸면 배지로 줄인다
        self.tabbarViewController?.onTabSelected = { [weak self] in self?.handleUserDidNavigate() }

        let photoCoordinator = makePhotoLibraryCoordinator(viewModel: viewModel)
        let albumCoordinator = makeAlbumCoordinator(viewModel: viewModel)
        let myPageCoordinator = makeMyPageCoordinator(viewModel: viewModel)
        [photoCoordinator, albumCoordinator, myPageCoordinator].forEach {
            $0.hideTabBar = { [weak self] in
                self?.tabbarViewController?.hideTabbar()
            }

            $0.showTabBar = { [weak self] in
                self?.tabbarViewController?.showTabbar()
            }

            // 탭 안의 모든 화면 이동을 잡는다
            $0.onNavigate = { [weak self] in self?.handleUserDidNavigate() }
        }
        let photo = photoCoordinator.startAndReturn()
        let album = albumCoordinator.startAndReturn()
        let myPage = myPageCoordinator.startAndReturn()

        self.tabbarViewController?.setTabBarItem("lucide_images", vc: photo, title: String(localized: "사진첩", bundle: .module))
        self.tabbarViewController?.setTabBarItem("lucide_layers", vc: album, title: String(localized: "앨범", bundle: .module))
        self.tabbarViewController?.setTabBarItem("lucide_settings", vc: myPage, title: String(localized: "설정", bundle: .module))

        let controllers = [photo,
                           album,
                           myPage]

        self.tabbarViewController?.setViewControllers(controllers)

        window.rootViewController = self.tabbarViewController
        window.makeKeyAndVisible()
    }

    private func presentAnalysisGuide(isFirstAnalysis: Bool, loadEstimate: @escaping () async -> AnalysisEstimate?, onStart: @escaping () -> Void) {
        guard let tabbarViewController else { return }
        let sheet = AnalysisGuideSheet(isFirstAnalysis: isFirstAnalysis, loadEstimate: loadEstimate)
        sheet.onStart = onStart
        let height = sheet.fittingHeight(width: tabbarViewController.view.bounds.width)
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.custom { _ in height }]
            presentation.preferredCornerRadius = 28
        }
        (tabbarViewController.presentedViewController ?? tabbarViewController).present(sheet, animated: true)
    }

    /// 앨범 탭/설정 탭 양쪽에서 쓰는 진입점이라 탭바 위에 모달로 띄운다
    private func presentLibraryImportPicker(useCase: LibraryAlbumImportUseCase) {
        let modalNav = UINavigationController()
        let importCoordinator = LibraryAlbumPickerCoordinator(useCase: useCase, navigationController: modalNav)
        self.start(coordinator: importCoordinator)
        tabbarViewController?.present(modalNav, animated: true)
    }

    private func makePhotoLibraryCoordinator(viewModel: TabbarViewModel) -> PhotoLibraryCoordinator {
        let diContainer = container.makePhotoLibraryDIContainer()
        return PhotoLibraryCoordinator(diContainer: diContainer, tabbarViewModel: viewModel)
    }

    private func makeAlbumCoordinator(viewModel: TabbarViewModel) -> AlbumCoordinator {
        let diContainer = container.makeAlbumDIContainer()
        return AlbumCoordinator(diContainer: diContainer, tabbarViewModel: viewModel)
    }

    private func makeMyPageCoordinator(viewModel: TabbarViewModel) -> MyPageCoordinator {
        let diContainer = container.makeMyPageDIContainer()
        return MyPageCoordinator(diContainer: diContainer, tabbarViewModel: viewModel)
    }

    // MARK: - 진행 상태 3단계 오케스트레이션

    private func startAnalysisFlow(progress: AnalyzeProgress) {
        currentAnalyzeProgress = progress
        isAnalysisComplete = false
        subscribeCompletion(progress: progress)
        currentTier = .sheet
        presentSheet(progress: progress)
    }

    private func presentSheet(progress: AnalyzeProgress) {
        // 미니 진행률/배지가 떠 있으면 중복되지 않게 먼저 치운다
        AnalysisProgressManager.shared.hide()
        AnalysisBadgeManager.shared.hide()

        let sheet = AlbumAnalysisSheet(progress: progress)
        sheet.isModalInPresentation = true
        if let presentation = sheet.sheetPresentationController {
            // "자세히"를 펼치면 .large로 전환된다
            presentation.detents = [.medium(), .large()]
            presentation.selectedDetentIdentifier = .medium
            presentation.preferredCornerRadius = 28
        }
        // 최소화하면 분석은 계속되고 미니 진행률(2단계)로 바뀐다
        sheet.onMinimize = { [weak self] in
            self?.enterMiniTier()
        }

        tabbarViewController?.present(sheet, animated: true)
    }

    /// 2단계 — 탭바 위 플로팅 미니 진행률. 탭하면 1단계(시트)로 복귀한다.
    private func enterMiniTier() {
        guard let progress = currentAnalyzeProgress else { return }
        currentTier = .mini
        AnalysisBadgeManager.shared.hide()

        AnalysisProgressManager.shared.show(
            locationProgress: progress.photoProgress,
            albumProgress: progress.albumProgress,
            showsPhotoProgress: progress.mode == .analysis,
            onTap: { [weak self] in
                // 위젯이 다 사라진 뒤에 시트를 띄운다(안 그러면 애니메이션이 가려진다)
                AnalysisProgressManager.shared.hide(delay: 0) {
                    self?.currentTier = .sheet
                    self?.presentSheet(progress: progress)
                }
            }
        )
    }

    /// 3단계 — 탭바 옆 배지. 미니위젯 상태에서 화면을 이동하면 여기로 줄어든다
    private func enterBadgeTier() {
        guard currentAnalyzeProgress != nil, !isAnalysisComplete else { return }
        currentTier = .badge
        // 딜레이 없이 바로 사라지게 해야 배지와 타이밍이 맞는다
        AnalysisProgressManager.shared.hide(delay: 0)

        // 위젯이 거의 사라질 즈음 배지가 같은 방향에서 들어와야 이어지는 느낌이 난다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AnalysisBadgeManager.shared.show(onTap: { [weak self] in
                self?.handleBadgeTap()
            })
        }
    }

    /// 미니위젯(2단계)일 때만 배지로 줄인다
    private func handleUserDidNavigate() {
        guard currentTier == .mini else { return }
        enterBadgeTier()
    }

    /// 배지 탭 — 진행 중이면 미니위젯으로, 완료 상태면 치운다
    private func handleBadgeTap() {
        if isAnalysisComplete {
            AnalysisBadgeManager.shared.hide()
            currentTier = nil
            currentAnalyzeProgress = nil
        } else {
            enterMiniTier()
        }
    }

    private func subscribeCompletion(progress: AnalyzeProgress) {
        progress.albumCompleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.isAnalysisComplete = true
                switch self.currentTier {
                case .badge:
                    // 배지 상태에서 완료되면 "완료"로 바뀌고, 탭해야 사라진다
                    AnalysisBadgeManager.shared.showCompleted()
                case .sheet, .mini, .none:
                    // 시트와 미니위젯은 스스로 닫힌다 — 여기선 상태만 정리
                    self.currentTier = nil
                    self.currentAnalyzeProgress = nil
                }
            }
            .store(in: &cancellables)
    }
}
