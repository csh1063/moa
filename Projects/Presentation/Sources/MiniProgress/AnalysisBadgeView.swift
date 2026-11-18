//
//  AnalysisBadgeView.swift
//  Presentation
//
//  Created by sanghyeon on 9/2/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

/// 진행 3단계(배지) — 정확한 % 대신 펄스 링으로 진행 중임만 보여준다
final class AnalysisBadgeView: UIView {

    var onTap: (() -> Void)?

    private let coreCircle: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.surface
        view.layer.cornerRadius = 20
        view.layer.borderWidth = 1
        view.layer.borderColor = Theme.strokeSoft.cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.12
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 3)
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "lucide_sparkle", in: .module, with: nil))
        imageView.tintColor = Theme.primary
        return imageView
    }()

    private let pulseRing1 = CAShapeLayer()
    private let pulseRing2 = CAShapeLayer()

    // "완료" 상태일 때만 core 왼쪽에 나타나는 라벨 — 평소엔 폭 0으로 숨겨져 있다.
    private let completedLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "완료", bundle: .module)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.positive
        label.alpha = 0
        return label
    }()

    private var isCompleted = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        setupPulseLayers()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // "완료" 라벨이 나타나도 크기가 안 바뀌게 고정 — 원은 오른쪽 끝, 라벨은 그 왼쪽
    override var intrinsicContentSize: CGSize {
        CGSize(width: 98, height: 40)
    }

    @objc private func handleTap() {
        onTap?()
    }

    private func setupLayout() {
        addSubview(completedLabel)
        addSubview(coreCircle)
        coreCircle.addSubview(iconView)

        coreCircle.snp.makeConstraints { make in
            make.trailing.centerY.equalTo(self)
            make.width.height.equalTo(40)
        }

        iconView.snp.makeConstraints { make in
            make.center.equalTo(coreCircle)
            make.width.height.equalTo(15)
        }

        completedLabel.snp.makeConstraints { make in
            make.trailing.equalTo(coreCircle.snp.leading).offset(-6)
            make.centerY.equalTo(self)
        }
    }

    private func setupPulseLayers() {
        [pulseRing1, pulseRing2].forEach {
            $0.fillColor = UIColor.clear.cgColor
            $0.strokeColor = Theme.primary.cgColor
            $0.lineWidth = 1.4
            layer.addSublayer($0)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 링의 bounds/position을 원의 프레임에 맞춰야 원 중심 기준으로 커진다
        let localRect = CGRect(origin: .zero, size: coreCircle.frame.size)
        let path = UIBezierPath(ovalIn: localRect).cgPath
        for ring in [pulseRing1, pulseRing2] {
            ring.bounds = localRect
            ring.position = CGPoint(x: coreCircle.frame.midX, y: coreCircle.frame.midY)
            ring.path = path
        }
    }

    // MARK: - State

    /// 분석이 진행 중일 때 계속 호출 — 이미 펄스가 돌고 있으면 무시(중복 애니메이션 방지).
    func setActive() {
        guard !isCompleted else { return }
        startPulseIfNeeded()
    }

    /// 완료 — 펄스를 멈추고 "완료"로 바꾼다. 탭해야 사라진다
    func showCompleted() {
        guard !isCompleted else { return }
        isCompleted = true

        pulseRing1.removeAllAnimations()
        pulseRing2.removeAllAnimations()
        pulseRing1.opacity = 0
        pulseRing2.opacity = 0

        iconView.image = UIImage(named: "lucide_check", in: .module, with: nil)
        iconView.tintColor = Theme.positive
        coreCircle.layer.borderColor = Theme.positive.cgColor

        UIView.animate(withDuration: 0.25) {
            self.completedLabel.alpha = 1
        }
    }

    private func startPulseIfNeeded() {
        guard pulseRing1.animation(forKey: "pulse") == nil else { return }
        pulseRing1.opacity = 1
        pulseRing2.opacity = 1

        for (layer, delay) in [(pulseRing1, 0.0), (pulseRing2, 1.1)] {
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1.0, 1.85]
            scale.keyTimes = [0, 1]

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.55, 0]
            opacity.keyTimes = [0, 1]

            let group = CAAnimationGroup()
            group.animations = [scale, opacity]
            group.duration = 2.2
            group.beginTime = CACurrentMediaTime() + delay
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .backwards

            layer.add(group, forKey: "pulse")
        }
    }
}
