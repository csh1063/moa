//
//  FaceAlbumCell.swift
//  Presentation
//
//  Created by sanghyeon on 5/27/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Domain

/// avatarContainer 전용 — 자기 자신의 layoutSubviews에서 직접 반지름을 계산한다. 부모 셀의
/// layoutSubviews/configure에서 이 뷰의 bounds를 읽어 계산하려고 했더니 타이밍이 꼬여서(첫
/// 표시 때 bounds가 아직 0인 상태로 읽히는 경우가 있었음) 계속 네모로 깨지는 문제가 있었다 —
/// 이 뷰 스스로 자기 bounds가 바뀔 때(=자기 layoutSubviews가 불릴 때) 반지름을 다시 계산하면
/// 그런 타이밍 문제 자체가 성립하지 않는다.
private final class CircularContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

final class FaceAlbumCell: UICollectionViewCell {

    // MARK: - UI

    private let avatarContainer = CircularContainerView()

    private let faceCellView = FaceCellView()

    private let placeholderIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.fill")?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = Theme.textTertiary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let countBadge = UILabel()
    private let nameLabel  = UILabel()

    private var currentIdentifier: String?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("FaceAlbumCell does not support NSCoding")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        faceCellView.prepareForReuse()
        placeholderIcon.isHidden = false
        avatarContainer.layer.borderColor = Theme.strokeSoft.cgColor
        avatarContainer.layer.borderWidth = 2.5
        currentIdentifier = nil
    }

    // MARK: - Setup

    private func setupView() {
        contentView.backgroundColor = Theme.background

        avatarContainer.layer.masksToBounds = true
        avatarContainer.layer.borderWidth = 2.5
        avatarContainer.layer.borderColor = Theme.strokeSoft.cgColor
        avatarContainer.backgroundColor = Theme.strokeSoft
        contentView.addSubview(avatarContainer)

        avatarContainer.addSubview(faceCellView)
        avatarContainer.addSubview(placeholderIcon)

        countBadge.backgroundColor = Theme.primary
        countBadge.textColor = .white
        countBadge.font = .systemFont(ofSize: 10, weight: .bold)
        countBadge.textAlignment = .center
        countBadge.layer.cornerRadius = 8
        countBadge.layer.masksToBounds = true
        countBadge.layer.borderWidth = 1.5
        countBadge.layer.borderColor = Theme.background.cgColor
        contentView.addSubview(countBadge)

        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        contentView.addSubview(nameLabel)

        avatarContainer.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            // 셀 너비에 비례(기존 80pt 셀 기준 68pt 아바타 = 0.85) — 셀이 커지면 아바타도 같이 커진다
            make.width.height.equalTo(contentView.snp.width).multipliedBy(0.85)
        }
        faceCellView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        placeholderIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(30)
        }
        countBadge.snp.makeConstraints { make in
            make.bottom.equalTo(avatarContainer)
            make.trailing.equalTo(avatarContainer).offset(2)
            make.height.equalTo(16)
            make.width.greaterThanOrEqualTo(24)
        }
        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(avatarContainer.snp.bottom).offset(6)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    // MARK: - Configure

    func configure(with viewModel: FaceAlbumCellViewModel) {
        currentIdentifier = viewModel.localIdentifier
        countBadge.text   = "\(viewModel.photoCount)"

        if viewModel.isNamed {
            nameLabel.text      = viewModel.displayName
            nameLabel.textColor = Theme.textSecondary
            nameLabel.font      = .systemFont(ofSize: 12, weight: .regular)
        } else {
            nameLabel.text      = ""
            nameLabel.textColor = Theme.textTertiary
            nameLabel.font      = .italicSystemFont(ofSize: 12)
        }

        avatarContainer.layer.borderColor = viewModel.isHighlighted
            ? Theme.primary.cgColor
            : Theme.strokeSoft.cgColor

        faceCellView.configure(with: viewModel.faceCellViewModel) { [weak self] loaded in
            guard let self, self.currentIdentifier == viewModel.localIdentifier else { return }
            self.placeholderIcon.isHidden = loaded
        }
    }
}
