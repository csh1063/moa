//
//  MiniProgressView.swift
//  Presentation
//
//  Created by sanghyeon on 4/27/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Combine

/// 미니 진행률(2단계) — 사진 분석과 앨범 생성이 병렬이라 두 줄의 독립 진행바로 보여준다
final class MiniProgressView: UIView {

    var cancellables = Set<AnyCancellable>()
    var onTap: (() -> Void)?

    private let photoRow = MiniProgressBarRow(icon: "lucide_image_plus")
    private let albumRow = MiniProgressBarRow(icon: "lucide_layers")

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.surface
        layer.cornerRadius = 20
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        setupLayout()
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 176, height: 72)
    }

    @objc private func handleTap() {
        onTap?()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.borderWidth = 0.5
        layer.borderColor = Theme.strokeSoft.cgColor
    }

    private func setupLayout() {
        let stack = UIStackView(arrangedSubviews: [photoRow, albumRow])
        stack.axis = .vertical
        stack.spacing = 12

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalTo(self).inset(16)
            make.centerY.equalTo(self)
        }
    }

    func setPhotoRowHidden(_ hidden: Bool) {
        photoRow.isHidden = hidden
    }

    // MARK: - Bind

    func bind(
        locationProgress: AnyPublisher<Double, Never>,
        albumProgress: AnyPublisher<Double, Never>
    ) {
        locationProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.photoRow.updateProgress(progress)
            }
            .store(in: &cancellables)

        albumProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.albumRow.updateProgress(progress)
                if progress >= 1.0 {
                    AnalysisProgressManager.shared.hide()
                }
            }
            .store(in: &cancellables)
    }
}

/// 미니 위젯 한 줄 — 아이콘 + 진행바 + 진행 중일 때만 펄스 도트
/// 폭은 트랙 대비 비율로 계산하고 첫 반영은 애니메이션 없이 — 위젯을 다시 만들 때 0부터 차 보이지 않게
private final class MiniProgressBarRow: UIView {

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = Theme.textSecondary
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let trackView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.strokeSoft
        view.layer.cornerRadius = 2.5
        view.clipsToBounds = true
        return view
    }()

    private let fillView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.primary
        view.layer.cornerRadius = 2.5
        return view
    }()

    private let glowDot: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 3
        view.layer.shadowColor = Theme.primary.cgColor
        view.layer.shadowRadius = 4
        view.layer.shadowOffset = .zero
        view.layer.shadowOpacity = 0
        view.isHidden = true
        return view
    }()

    private var hasSetInitialProgress = false

    init(icon: String) {
        super.init(frame: .zero)
        iconView.image = UIImage(named: icon, in: .module, with: nil)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        addSubview(iconView)
        addSubview(trackView)
        trackView.addSubview(fillView)
        // 트랙이 잘라내지 않게 도트는 self에 두고 진행바 끝만 따라간다
        addSubview(glowDot)

        snp.makeConstraints { make in
            make.height.equalTo(14)
        }

        iconView.snp.makeConstraints { make in
            make.leading.equalTo(self)
            make.centerY.equalTo(self)
            make.width.height.equalTo(14)
        }

        trackView.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(8)
            make.trailing.equalTo(self)
            make.centerY.equalTo(self)
            make.height.equalTo(5)
        }

        fillView.snp.makeConstraints { make in
            make.leading.top.bottom.equalTo(trackView)
            make.width.equalTo(trackView).multipliedBy(0)
        }

        glowDot.snp.makeConstraints { make in
            make.centerX.equalTo(fillView.snp.trailing)
            make.centerY.equalTo(trackView)
            make.width.height.equalTo(6)
        }
    }

    func updateProgress(_ progress: Double) {
        // multiplier는 바꿀 수 없어서 remake로 제약 전체를 다시 만든다
        let apply = {
            self.fillView.snp.remakeConstraints { make in
                make.leading.top.bottom.equalTo(self.trackView)
                make.width.equalTo(self.trackView).multipliedBy(CGFloat(progress))
            }
            self.layoutIfNeeded()
        }

        glowDot.isHidden = progress <= 0 || progress >= 1.0
        if progress > 0 && progress < 1.0 {
            startPulseIfNeeded()
        } else {
            stopPulse()
        }

        guard hasSetInitialProgress else {
            hasSetInitialProgress = true
            apply()
            return
        }
        UIView.animate(withDuration: 0.15, animations: apply)
    }

    private func startPulseIfNeeded() {
        guard glowDot.layer.animation(forKey: "pulse") == nil else { return }

        let shadowAnim = CAKeyframeAnimation(keyPath: "shadowOpacity")
        shadowAnim.values = [0.4, 0.9, 0.4]
        shadowAnim.keyTimes = [0, 0.5, 1]

        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [0.8, 1.2, 0.8]
        scaleAnim.keyTimes = [0, 0.5, 1]

        let group = CAAnimationGroup()
        group.animations = [shadowAnim, scaleAnim]
        group.duration = 1.2
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        glowDot.layer.add(group, forKey: "pulse")
    }

    private func stopPulse() {
        glowDot.layer.removeAnimation(forKey: "pulse")
    }
}
