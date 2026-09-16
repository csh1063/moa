//
//  FaceAlbumGridCell.swift
//  Presentation
//
//  Created by sanghyeon on 9/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Domain

/// "인물" 모두보기 전용 셀 — 홈 화면의 원형 아바타(FaceAlbumCell)와 달리, 사진첩 그리드처럼
/// 사각 사진이 셀 전체를 채우고, 사용자가 직접 이름을 지정한 경우에만 하단에 그라데이션+이름을 얹는다.
final class FaceAlbumGridCell: UICollectionViewCell {

    // MARK: - UI

    private let coverView = UIView()
    private let faceCellView = FaceCellView()

    private let placeholderIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.fill")?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = Theme.textTertiary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let countBadge: UILabel = {
        let lb = UILabel()
        lb.backgroundColor = Theme.primary
        lb.textColor = .white
        lb.font = .systemFont(ofSize: 10, weight: .bold)
        lb.textAlignment = .center
        lb.layer.cornerRadius = 8
        lb.layer.masksToBounds = true
        return lb
    }()

    private let gradientView = GradientView()

    private let nameLabel: UILabel = {
        let lb = UILabel()
        lb.textColor = .white
        lb.font = .systemFont(ofSize: 13, weight: .semibold)
        lb.numberOfLines = 1
        return lb
    }()

    private var currentIdentifier: String?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("FaceAlbumGridCell does not support NSCoding")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        faceCellView.prepareForReuse()
        placeholderIcon.isHidden = false
        coverView.layer.borderColor = Theme.strokeSoft.cgColor
        currentIdentifier = nil
    }

    // MARK: - Setup

    private func setupView() {
        contentView.backgroundColor = Theme.background

        coverView.layer.cornerRadius = 12
        coverView.layer.masksToBounds = true
        coverView.addBorder(color: Theme.strokeSoft, borderWidth: 1)
        coverView.backgroundColor = Theme.strokeSoft
        contentView.addSubview(coverView)

        coverView.addSubview(faceCellView)
        coverView.addSubview(placeholderIcon)
        coverView.addSubview(gradientView)
        coverView.addSubview(countBadge)

        gradientView.addSubview(nameLabel)

        coverView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        faceCellView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        placeholderIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(24)
        }
        countBadge.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(6)
            make.height.equalTo(16)
            make.width.greaterThanOrEqualTo(22)
        }
        gradientView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(0.45)
        }
        nameLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().inset(8)
        }
    }

    // MARK: - Configure

    func configure(with viewModel: FaceAlbumCellViewModel) {
        currentIdentifier = viewModel.localIdentifier
        countBadge.text = "\(viewModel.photoCount)"

        gradientView.isHidden = !viewModel.isNamed
        nameLabel.text = viewModel.isNamed ? viewModel.displayName : nil

        coverView.layer.borderColor = viewModel.isHighlighted
            ? Theme.primary.cgColor
            : Theme.strokeSoft.cgColor

        faceCellView.configure(with: viewModel.faceCellViewModel) { [weak self] loaded in
            guard let self, self.currentIdentifier == viewModel.localIdentifier else { return }
            self.placeholderIcon.isHidden = loaded
        }
    }
}
