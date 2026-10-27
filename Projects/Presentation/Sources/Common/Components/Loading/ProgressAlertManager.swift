//
//  ProgressAlertManager.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

/// 삭제처럼 끝날 때까지 기다려야 하는 작업용 진행률 카드(제목 + 진행바 + %) — 진행 중엔 닫을 수 없다
public final class ProgressAlertManager {

    public static let shared = ProgressAlertManager()
    private init() {}

    private var dimView: UIView?
    private var alertView: ProgressAlertView?

    public func show(title: String) {
        guard alertView == nil else { return }

        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return }

        let dimView = UIView(backgroundColor: .black.withAlphaComponent(0.3))
        let view = ProgressAlertView(title: title)
        window.addSubview(dimView)
        window.addSubview(view)

        dimView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        view.snp.makeConstraints { make in
            make.center.equalTo(dimView)
            make.width.equalTo(270)
        }

        dimView.alpha = 0
        view.alpha = 0
        UIView.animate(withDuration: 0.2) {
            dimView.alpha = 1
            view.alpha = 1
        }

        self.dimView = dimView
        self.alertView = view
    }

    public func update(_ ratio: Double) {
        alertView?.update(ratio)
    }

    public func hide() {
        guard let view = alertView, let dimView else { return }
        // 바로 비워둬야 사라지는 애니메이션 도중 늦게 도착한 update는 무시되고, 곧바로 다음 show도 가능하다
        alertView = nil
        self.dimView = nil
        UIView.animate(withDuration: 0.2) {
            view.alpha = 0
            dimView.alpha = 0
        } completion: { _ in
            view.removeFromSuperview()
            dimView.removeFromSuperview()
        }
    }
}

private final class ProgressAlertView: UIView {

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Theme.textPrimary
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let trackView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.strokeSoft
        view.layer.cornerRadius = 3
        view.clipsToBounds = true
        return view
    }()

    private let fillView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.primary
        view.layer.cornerRadius = 3
        return view
    }()

    private let percentLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = Theme.textSecondary
        label.textAlignment = .center
        label.text = "0%"
        return label
    }()

    private var ratio: Double = 0

    init(title: String) {
        super.init(frame: .zero)
        backgroundColor = Theme.surface
        layer.cornerRadius = 16
        titleLabel.text = title

        addSubview(titleLabel)
        addSubview(trackView)
        trackView.addSubview(fillView)
        addSubview(percentLabel)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        trackView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(6)
        }
        fillView.snp.makeConstraints { make in
            make.leading.top.bottom.equalTo(trackView)
            make.width.equalTo(trackView).multipliedBy(0)
        }
        percentLabel.snp.makeConstraints { make in
            make.top.equalTo(trackView.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().offset(-20)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ ratio: Double) {
        // 늦게 도착한 이전 값 때문에 바가 뒤로 가지 않게 한다
        let clamped = min(max(ratio, 0), 1)
        guard clamped > self.ratio else { return }
        self.ratio = clamped

        percentLabel.text = "\(Int(clamped * 100))%"
        // multiplier는 생성 후 못 바꿔서 제약을 통째로 다시 만든다 (ProgressRow와 같은 이유)
        fillView.snp.remakeConstraints { make in
            make.leading.top.bottom.equalTo(trackView)
            make.width.equalTo(trackView).multipliedBy(clamped)
        }
        UIView.animate(withDuration: 0.15) {
            self.layoutIfNeeded()
        }
    }
}
