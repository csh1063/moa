//
//  AnalysisProgressManager.swift
//  Presentation
//
//  Created by sanghyeon on 4/27/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Combine

final class AnalysisProgressManager {
    static let shared = AnalysisProgressManager()

    var isPresenting: Bool = false

    private var window: UIWindow?
    private var floatingView: MiniProgressView?
    private var isHiding: Bool = false

    func show(
        locationProgress: AnyPublisher<Double, Never>,
        albumProgress: AnyPublisher<Double, Never>,
        showsPhotoProgress: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        guard !isPresenting else {return}

        isPresenting = true

        let view = MiniProgressView()
        view.setPhotoRowHidden(!showsPhotoProgress)
        view.bind(locationProgress: locationProgress, albumProgress: albumProgress)
        view.onTap = onTap

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }

        window.addSubview(view)

        // 왼쪽 화면 밖(위젯 폭 176 + 여유)에서 시작해 슬라이드-인 — 탭바가 오른쪽이라 위젯/배지는 왼쪽에 둔다
        view.snp.makeConstraints { make in
            make.leading.equalTo(-184)
            make.bottom.equalTo(window).offset(-120)
            make.width.equalTo(176)
            // 진행바 한 줄(재생성)이면 두 줄(분석)일 때보다 낮게
            make.height.equalTo(showsPhotoProgress ? 72 : 46)
        }
        window.layoutIfNeeded()

        self.window = window
        self.floatingView = view

        view.snp.updateConstraints { make in
            make.leading.equalTo(20)
        }

        UIView.animate(withDuration: 0.5) {
            window.layoutIfNeeded()
        }
    }

    /// - delay: 시작 전 대기 — 완료 후 자동으로 사라질 땐 0.5초, 탭해서 복귀할 땐 0
    /// - completion: 사라지는 애니메이션이 끝난 뒤 호출(그 뒤에 시트를 띄워야 애니메이션이 안 가려진다)
    func hide(delay: TimeInterval = 0.5, completion: (() -> Void)? = nil) {

        guard !isHiding else { completion?(); return }
        isHiding = true

        guard let window else {
            floatingView?.removeFromSuperview()
            floatingView = nil
            isPresenting = false
            isHiding = false
            completion?()
            return
        }

        self.floatingView?.snp.updateConstraints { make in
            make.leading.equalTo(-184)
        }

        UIView.animate(withDuration: 0.5, delay: delay) {
            window.layoutIfNeeded()
        } completion: { success in
            if success {
                self.floatingView?.removeFromSuperview()
                self.floatingView = nil
                self.isPresenting = false
                self.isHiding = false
            }
            completion?()
        }
    }
}
