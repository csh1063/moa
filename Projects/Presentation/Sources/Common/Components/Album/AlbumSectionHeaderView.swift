//
//  AlbumSectionHeaderView.swift
//  Presentation
//
//  Created by sanghyeon on 5/27/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit

final class AlbumSectionHeaderView: UICollectionReusableView {

    // MARK: - UI

    private let titleLabel = UILabel()
    private let moreButton = UIButton(type: .system)

    var onMoreTapped: (() -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("AlbumSectionHeaderView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear

        titleLabel.textColor = Theme.textPrimary
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        addSubview(titleLabel)

        moreButton.setTitle(String(localized: "모두 보기", bundle: .module), for: .normal)
        moreButton.setTitleColor(Theme.primary, for: .normal)
        moreButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        addSubview(moreButton)

        // 섹션의 contentInsets(leading/trailing 20)이 supplementariesFollowContentInsets
        // 기본값(true)에 의해 헤더에도 이미 적용된 상태라, 여기서 또 20을 주면 셀 콘텐츠보다
        // 20pt 더 안쪽에서 시작하는 이중 여백이 된다 — 헤더 프레임 경계에 바로 붙인다
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
        }

        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }
    }

    @objc private func moreTapped() {
        onMoreTapped?()
    }

    func configure(_ section: AlbumSection, itemCount: Int) {
        titleLabel.text = section.title

        switch section {
        case .travel:
            self.moreButton.isHidden = itemCount < 8
        case .location:
            self.moreButton.isHidden = false
        case .date:
            self.moreButton.isHidden = false
        case .category:
            self.moreButton.isHidden = true
        case .face:
            self.moreButton.isHidden = itemCount < 20
        case .similar:
            self.moreButton.isHidden = false
        case .library:
            // 메인엔 최대 3개까지만 노출되므로, 하나라도 있으면 나머지를 볼 수 있게 모두보기를 보여준다
            self.moreButton.isHidden = itemCount < 1
        }
    }
}
