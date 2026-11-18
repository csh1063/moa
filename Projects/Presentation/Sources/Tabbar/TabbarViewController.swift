//
//  TabbarViewController.swift
//  Presentation
//
//  Created by sanghyeon on 12/22/25.
//  Copyright © 2025 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Combine

final class TabbarViewController: CustomTabBarController {

    private let viewModel: TabbarViewModel

    private var showOnConsent: Bool = false
    private var showOnboarding: Bool = false

    /// 탭 전환 — 미니 진행률을 배지로 줄이는 데 쓴다
    var onTabSelected: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    init(viewModel: TabbarViewModel) {
        self.viewModel = viewModel

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("TabbarViewController does not support NSCoding.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.binding()

        self.setBackgroundColor(Theme.background.withAlphaComponent(0.72))

        self.setItemColors(
            normal: Theme.textSecondary,
            selected: .white)
//            selected: Theme.primary)

//        self.setLayoutMargin(height: 68,
//                             margin: .init(leading: 0, trailing: 0, bottom: 0),
//                             padding: .init(leading: 12, trailing: 12))
        // 왼쪽 배지 자리를 비워두려고 오른쪽 정렬 — 배지가 떠도 탭바는 안 움직인다
        self.setAlign(.right)
        self.setLayoutMargin(height: 56, itemWidth: 80,
                             margin: .init(trailing: 20, bottom: 4),
                             padding: .zero, cornerRadius: 28)

        self.setShadow(color: .black, alpha: 0.3, x: 0, y: 4, blur: 16)

        self.setSelectedBox(color: Theme.primary)

        self.selectedIndex = 1

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

//        if !showOnboarding {
//            showOnboarding = true
//            let vc = OnboardingViewController()
//            vc.modalPresentationStyle = .fullScreen
//            self.present(vc, animated: true)
//        } else if !showOnConsent {
//            showOnConsent = true
//            let vc = ConsentViewController()
//            vc.modalPresentationStyle = .fullScreen
//            self.present(vc, animated: true)
//            
//        }

        viewModel.send(.showOnboarding)
    }

    private func binding() {

        let output = viewModel.transform()
        output.onboarding
            .sink { [weak self] isShow in
                if let isShow {
                    if !isShow {
                        let vc = OnboardingViewController()
                        vc.modalPresentationStyle = .fullScreen
                        vc.onClose = { [weak self] in
                            self?.viewModel.send(.afterOnboarding)
                        }
                        self?.present(vc, animated: true)
                    } else {
                        self?.viewModel.send(.showConsent)
                    }
                }
            }
            .store(in: &cancellables)

        output.consent
            .sink { [weak self] isShow in
                if let isShow, !isShow {
                    let vc = TermsViewController()
                    vc.modalPresentationStyle = .fullScreen
                    vc.onConsented = { [weak self] in
                        self?.viewModel.send(.afterConsent)
                    }
                    self?.present(vc, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    func showTabbar() {
        self.animateFade(isShow: true)
    }

    func hideTabbar() {
        self.animateFade(isShow: false)
    }

}

extension TabbarViewController: CustomTabBarDelegate {
    func tabBarController(_ tabBarController: CustomTabBarController, didSelect viewController: UIViewController) {
        onTabSelected?()
    }
}
