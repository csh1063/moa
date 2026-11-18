//
//  AnalysisBadgeManager.swift
//  Presentation
//
//  Created by sanghyeon on 9/2/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

/// 진행 3단계(탭바 옆 배지)를 window에 띄운다 — 탭바가 숨은 화면에서도 같은 자리라 고정 좌표를 쓴다
final class AnalysisBadgeManager {
    static let shared = AnalysisBadgeManager()

    private(set) var isPresenting = false

    private var window: UIWindow?
    private var badgeView: AnalysisBadgeView?

    func show(onTap: (() -> Void)?) {
        if let badgeView {
            badgeView.onTap = onTap
            badgeView.setActive()
            return
        }

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }

        isPresenting = true

        let view = AnalysisBadgeView()
        view.onTap = onTap
        view.alpha = 0
        // 미니 위젯이 사라지는 방향(왼쪽)에서 들어오게 시작 위치를 민다
        view.transform = CGAffineTransform(translationX: -60, y: 0)

        window.addSubview(view)
        view.snp.makeConstraints { make in
            make.leading.equalTo(window).offset(20)
            // 탭바(높이 56 + 아래 여백 4) 중심과 같은 높이
            make.centerY.equalTo(window.safeAreaLayoutGuide.snp.bottom).offset(-32)
            make.width.height.equalTo(view.intrinsicContentSize)
        }

        self.window = window
        self.badgeView = view

        UIView.animate(
            withDuration: 0.4, delay: 0,
            usingSpringWithDamping: 0.75, initialSpringVelocity: 0.4
        ) {
            view.alpha = 1
            view.transform = .identity
        }
        view.setActive()
    }

    func showCompleted() {
        badgeView?.showCompleted()
    }

    func hide() {
        guard let badgeView else { return }
        UIView.animate(withDuration: 0.25, animations: {
            badgeView.alpha = 0
            badgeView.transform = CGAffineTransform(translationX: -60, y: 0)
        }, completion: { _ in
            badgeView.removeFromSuperview()
        })
        self.badgeView = nil
        self.isPresenting = false
    }
}
