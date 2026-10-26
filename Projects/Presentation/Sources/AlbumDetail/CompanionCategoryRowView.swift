//
//  CompanionCategoryRowView.swift
//  Presentation
//
//  Created by sanghyeon on 10/24/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Domain

/// 여행 앨범 "분류순" 한 줄 — 제목 + 가로 스크롤 썸네일 + 더보기. 사람/자연/음식/공간 전부 같은 모양이다
final class CompanionCategoryRowView: UIView {

    var onTapMore: (() -> Void)?

    private let titleLabel: UILabel = {
        let lb = UILabel()
        lb.font = .systemFont(ofSize: 15, weight: .semibold)
        lb.textColor = Theme.textPrimary
        return lb
    }()

    private let moreButton: UIButton = {
        var config = UIButton.Configuration.plain()
        var titleAttr = AttributeContainer()
        titleAttr.font = .systemFont(ofSize: 13, weight: .regular)
        config.attributedTitle = AttributedString(String(localized: "더보기", bundle: .module), attributes: titleAttr)
        config.baseForegroundColor = Theme.textSecondary
        config.contentInsets = .zero
        return UIButton(configuration: config)
    }()

    private let thumbnailScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        return sv
    }()

    private let thumbnailStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        return stack
    }()

    private var loadTasks: [Task<Void, Never>] = []
    private static let thumbnailSize = CGSize(width: 72, height: 72)
    private static let maxThumbnails = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("CompanionCategoryRowView does not support NSCoding") }

    deinit {
        loadTasks.forEach { $0.cancel() }
    }

    private func setupView() {
        let headerStack = UIStackView(arrangedSubviews: [titleLabel, UIView(), moreButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center

        addSubview(headerStack)
        addSubview(thumbnailScrollView)
        thumbnailScrollView.addSubview(thumbnailStackView)

        headerStack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        thumbnailScrollView.snp.makeConstraints { make in
            make.top.equalTo(headerStack.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(Self.thumbnailSize.height)
        }
        thumbnailStackView.snp.makeConstraints { make in
            make.edges.height.equalToSuperview()
        }

        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
    }

    func configure(section: AlbumDetailViewModel.AlbumDetailCategorySection, imageLoader: any ImageLoadable) {
        titleLabel.text = section.title

        loadTasks.forEach { $0.cancel() }
        loadTasks.removeAll()
        thumbnailStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for photo in section.photos.prefix(Self.maxThumbnails) {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = Theme.strokeSoft
            imageView.layer.cornerRadius = 10
            imageView.snp.makeConstraints { make in
                make.width.height.equalTo(Self.thumbnailSize.width)
            }
            thumbnailStackView.addArrangedSubview(imageView)

            let identifier = photo.localIdentifier
            let task = Task { [weak imageView] in
                let image = await imageLoader.loadImage(id: identifier, size: Self.thumbnailSize)
                guard !Task.isCancelled else { return }
                imageView?.image = image
            }
            loadTasks.append(task)
        }
    }

    @objc private func moreTapped() {
        onTapMore?()
    }
}
