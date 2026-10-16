//
//  AnalysisBadgeManager.swift
//  Presentation
//
//  Created by sanghyeon on 9/2/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

/// 진행 상태 3단계(탭바 옆 배지)를 window 레벨에 띄운다 — 탭바 유무와 상관없이(상세 페이지처럼
/// 탭바가 숨겨진 화면에서도) 계속 떠 있어야 해서 MiniProgressView와 같은 방식으로 window에 직접 붙인다.
/// 세로 위치는 탭바(TabbarViewController에서 height:56, bottom margin:4로 설정한 값)와 같은 높이가
/// 되도록 고정 좌표로 맞춰뒀다 — 탭바가 숨겨진 화면에서도 같은 자리를 유지해야 하므로 탭바 프레임을
/// 실시간으로 따라가는 대신 고정값을 쓴다.
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
        // 2단계 위젯이 오른쪽으로 슬라이드돼 사라지는 것과 같은 방향으로, 오른쪽에서 밀고 들어오게
        // 시작 위치를 오른쪽으로 밀어둔다 — 높이는 서로 달라도(위젯은 더 위, 배지는 탭바 옆) 이동
        // 방향이 같으면 "이어서 넘어왔다"는 느낌을 준다.
        view.transform = CGAffineTransform(translationX: 60, y: 0)

        window.addSubview(view)
        view.snp.makeConstraints { make in
            make.trailing.equalTo(window).offset(-20)
            // 탭바 height(56) + bottom margin(4)과 같은 높이에 오도록: 탭바 중심 = safeArea bottom - 32
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
            badgeView.transform = CGAffineTransform(translationX: 60, y: 0)
        }, completion: { _ in
            badgeView.removeFromSuperview()
        })
        self.badgeView = nil
        self.isPresenting = false
    }
}
