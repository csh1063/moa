//
//  ProgressRow.swift
//  Presentation
//
//  Created by sanghyeon on 4/27/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

final class ProgressRow: UIView {

    private let iconBackground: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.surfaceWarm
        view.layer.cornerRadius = 17
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = Theme.primary
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = Theme.textPrimary
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.color = Theme.primary
        return view
    }()

    /// "자세히" 토글 — 펼침 콘텐츠는 AlbumAnalysisSheet가 맡고 이 뷰는 화살표 방향만
    var onToggleDetail: (() -> Void)?

    private let detailToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "lucide_chevron_down", in: .module, with: nil), for: .normal)
        button.tintColor = Theme.textTertiary
        return button
    }()

    private let progressView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.primary
        return view
    }()

    private let fillLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        return label
    }()

    init(icon: String, title: String) {
        super.init(frame: .zero)
        iconView.image = UIImage(named: icon, in: .module, with: nil)
        titleLabel.text = title
        fillLabel.text = title
        backgroundColor = Theme.surface
        layer.cornerRadius = 16
        layer.masksToBounds = true
        setupLayout()
        detailToggleButton.addTarget(self, action: #selector(detailToggleTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateBorderColor() {
        layer.borderWidth = 1
        layer.borderColor = Theme.strokeSoft.cgColor
    }

    @objc private func detailToggleTapped() {
        onToggleDetail?()
    }

    /// 화살표 방향만 반영(위/아래) — 펼쳐진 콘텐츠는 이 뷰 소관이 아니다.
    func setDetailExpanded(_ expanded: Bool) {
        UIView.animate(withDuration: 0.25) {
            // 정확히 180도(.pi)는 회전 방향이 애매해질 수 있어 아주 살짝 못 미치게 돈다.
            self.detailToggleButton.transform = expanded ? CGAffineTransform(rotationAngle: .pi - 0.001) : .identity
        }
    }

    func setDetailToggleHidden(_ hidden: Bool) {
        detailToggleButton.isHidden = hidden
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
        fillLabel.text = title
    }

    func startSpinner() {
        spinner.startAnimating()
    }

    func stopSpinner() {
        spinner.stopAnimating()
    }

    // 폭은 self 대비 비율 제약으로 — 레이아웃 전에도 맞고, multiplier는 못 바꿔서 매번 remake한다
    // 첫 반영은 애니메이션 없이 즉시 — 시트를 다시 열 때 0부터 차 보이지 않게
    private var hasSetInitialProgress = false

    func updateProgress(_ progress: Double) {
        let apply = {
            self.progressView.snp.remakeConstraints { make in
                make.leading.top.bottom.equalTo(self)
                make.width.equalTo(self).multipliedBy(CGFloat(progress))
            }
            self.layoutIfNeeded()
        }
        guard hasSetInitialProgress else {
            hasSetInitialProgress = true
            apply()
            return
        }
        UIView.animate(withDuration: 0.1, animations: apply)
    }

    private func setupLayout() {

        iconBackground.addSubview(iconView)

        progressView.clipsToBounds = true

        addSubview(titleLabel)
        addSubview(progressView)
        progressView.addSubview(fillLabel)
        addSubview(iconBackground)
        addSubview(spinner)
        addSubview(detailToggleButton)

        self.snp.makeConstraints { make in
            make.height.equalTo(58)
        }

        progressView.snp.makeConstraints { make in
            make.leading.top.bottom.equalTo(self)
            // updateProgress와 같은 형태(self 대비 비율)로 만든다
            make.width.equalTo(self).multipliedBy(0)
        }

        iconBackground.snp.makeConstraints { make in
            make.leading.equalTo(self).offset(12)
            make.centerY.equalTo(self)
            make.width.height.equalTo(34)
        }

        iconView.snp.makeConstraints { make in
            make.center.equalTo(iconBackground)
            make.width.height.equalTo(16)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconBackground.snp.trailing).offset(12)
            make.centerY.equalTo(self)
        }

        fillLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconBackground.snp.trailing).offset(12)
            make.centerY.equalTo(self)
        }

        spinner.snp.makeConstraints { make in
            make.trailing.equalTo(self).offset(-12)
            make.centerY.equalTo(self)
        }

        detailToggleButton.snp.makeConstraints { make in
            make.trailing.equalTo(spinner.snp.leading).offset(-4)
            make.centerY.equalTo(self)
            make.width.height.equalTo(28)
        }

    }
}
