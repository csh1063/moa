//
//  LibraryAlbumGridCell.swift
//  Presentation
//
//  Created by sanghyeon on 9/18/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Domain

/// "가져온 앨범" 모두보기 전용 셀 — DateAlbumCell과 같은 구조(커버 사진 + 하단 그라데이션 + 텍스트)를
/// 따르되, 레이아웃(makeLibrarySection)에서 세로 크기를 메인 화면 시간 카드의 2배(240)로 고정하고
/// 가로 2열로 배치한다
final class LibraryAlbumGridCell: UICollectionViewCell {

    // MARK: - UI

    private let containerView = UIView()
    private let photoView = UIImageView()

    private let placeholderIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "photo.on.rectangle")?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = Theme.textTertiary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let overlayView = UIView()
    private let nameLabel  = UILabel()
    private let countLabel = UILabel()

    private var currentIdentifier: String?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("LibraryAlbumGridCell does not support NSCoding")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentIdentifier = nil
        photoView.image = nil
        placeholderIcon.isHidden = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayView.layoutIfNeeded()
        if let gradient = overlayView.layer.sublayers?.first as? CAGradientLayer {
            gradient.frame = overlayView.bounds
        }
    }

    // MARK: - Setup

    private func setupView() {
        contentView.backgroundColor = Theme.background

        containerView.backgroundColor = Theme.surface
        containerView.layer.cornerRadius = 16
        containerView.layer.masksToBounds = true
        containerView.addBorder(color: Theme.strokeSoft, borderWidth: 1)
        contentView.addSubview(containerView)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.backgroundColor = Theme.strokeSoft
        containerView.addSubview(photoView)

        containerView.addSubview(placeholderIcon)

        overlayView.backgroundColor = .clear
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.6).cgColor]
        gradient.locations = [0.4, 1.0]
        overlayView.layer.addSublayer(gradient)
        containerView.addSubview(overlayView)

        nameLabel.textColor = .white
        nameLabel.font = .systemFont(ofSize: 16, weight: .bold)
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        containerView.addSubview(nameLabel)

        countLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        countLabel.font = .systemFont(ofSize: 12, weight: .regular)
        containerView.addSubview(countLabel)

        containerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        photoView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        placeholderIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(36)
        }
        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        countLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalToSuperview().inset(12)
        }
        nameLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalTo(countLabel.snp.top).offset(-2)
        }
    }

    // MARK: - Configure

    func configure(with viewModel: CategoryAlbumCellViewModel) {
        currentIdentifier = viewModel.localIdentifier
        nameLabel.text = viewModel.displayName
        countLabel.text = String(localized: "사진 \(viewModel.photoCount.formatted())장", bundle: .module)

        photoView.image = nil

        let size = CGSize(width: 300, height: 400)
        viewModel.loadImageProgressive(size: size) { [weak self] image, _ in
            guard let self, self.currentIdentifier == viewModel.localIdentifier else { return }
            self.photoView.image = image
            self.placeholderIcon.isHidden = image != nil
        }
    }
}
