//
//  AnimalAlbumGridCell.swift
//  Presentation
//
//  Created by sanghyeon on 9/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Domain

/// FaceAlbumGridCell과 동일한 레이아웃 — "인물" 모두보기 그리드에서 동물 앨범용. 발바닥
/// placeholder, "나" 하이라이트 없음 (동물에는 해당 없음)만 다르다.
final class AnimalAlbumGridCell: UICollectionViewCell {

    // MARK: - UI

    private let coverView = UIView()
    private let animalCellView = AnimalCellView()

    private let placeholderIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "pawprint.fill")?.withRenderingMode(.alwaysTemplate)
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
        fatalError("AnimalAlbumGridCell does not support NSCoding")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        animalCellView.prepareForReuse()
        placeholderIcon.isHidden = false
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

        coverView.addSubview(animalCellView)
        coverView.addSubview(placeholderIcon)
        coverView.addSubview(gradientView)
        coverView.addSubview(countBadge)

        gradientView.addSubview(nameLabel)

        coverView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        animalCellView.snp.makeConstraints { make in
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

    func configure(with viewModel: AnimalAlbumCellViewModel) {
        currentIdentifier = viewModel.localIdentifier
        countBadge.text = "\(viewModel.photoCount)"

        gradientView.isHidden = !viewModel.isNamed
        nameLabel.text = viewModel.isNamed ? viewModel.displayName : nil

        animalCellView.configure(with: viewModel.animalCellViewModel) { [weak self] loaded in
            guard let self, self.currentIdentifier == viewModel.localIdentifier else { return }
            self.placeholderIcon.isHidden = loaded
        }
    }
}
