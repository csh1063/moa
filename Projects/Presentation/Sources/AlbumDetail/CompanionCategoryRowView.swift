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

/// 여행 앨범 "분류순" 한 묶음 — 제목 + 5열 최대 3줄 썸네일. 15장을 넘으면 마지막 칸이 딤 처리된 더보기 칸이 된다
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

    private let gridStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = spacing
        return stack
    }()

    private var loadTasks: [Task<Void, Never>] = []
    private static let thumbnailSize = CGSize(width: 150, height: 150)
    private static let columns = 5
    private static let maxRows = 3
    private static let spacing: CGFloat = 4

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
        addSubview(gridStackView)

        headerStack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        gridStackView.snp.makeConstraints { make in
            make.top.equalTo(headerStack.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }

        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
    }

    func configure(section: AlbumDetailViewModel.AlbumDetailCategorySection, imageLoader: any ImageLoadable) {
        titleLabel.text = section.title

        loadTasks.forEach { $0.cancel() }
        loadTasks.removeAll()
        gridStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let maxCells = Self.columns * Self.maxRows
        let hasMore = section.photos.count > maxCells
        let shown = Array(section.photos.prefix(maxCells))
        var cells: [UIView] = shown.enumerated().map { index, photo in
            let isMoreCell = hasMore && index == maxCells - 1
            return makeThumbnail(
                identifier: photo.localIdentifier,
                imageLoader: imageLoader,
                moreCount: isMoreCell ? section.photos.count - (maxCells - 1) : nil
            )
        }
        // 마지막 줄이 덜 차도 칸 너비가 같도록 빈 칸으로 채운다
        while cells.count % Self.columns != 0 { cells.append(UIView()) }

        for start in stride(from: 0, to: cells.count, by: Self.columns) {
            let row = UIStackView(arrangedSubviews: Array(cells[start..<start + Self.columns]))
            row.axis = .horizontal
            row.spacing = Self.spacing
            row.distribution = .fillEqually
            gridStackView.addArrangedSubview(row)
        }
    }

    /// moreCount가 있으면 사진 위에 딤 + "+N 더보기"를 덮은 더보기 칸
    private func makeThumbnail(identifier: String, imageLoader: any ImageLoadable, moreCount: Int?) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.strokeSoft
        imageView.layer.cornerRadius = 8
        imageView.snp.makeConstraints { make in
            make.height.equalTo(imageView.snp.width)
        }

        let task = Task { [weak imageView] in
            let image = await imageLoader.loadImage(id: identifier, size: Self.thumbnailSize)
            guard !Task.isCancelled else { return }
            imageView?.image = image
        }
        loadTasks.append(task)

        guard let moreCount else { return imageView }

        let dimView = UIView()
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        let countLabel = UILabel()
        countLabel.text = "+\(moreCount)"
        countLabel.font = .systemFont(ofSize: 17, weight: .bold)
        countLabel.textColor = .white

        let moreLabel = UILabel()
        moreLabel.text = String(localized: "더보기", bundle: .module)
        moreLabel.font = .systemFont(ofSize: 11, weight: .medium)
        moreLabel.textColor = UIColor.white.withAlphaComponent(0.9)

        let labelStack = UIStackView(arrangedSubviews: [countLabel, moreLabel])
        labelStack.axis = .vertical
        labelStack.alignment = .center
        labelStack.spacing = 1

        imageView.addSubview(dimView)
        dimView.addSubview(labelStack)
        dimView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        labelStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(moreTapped)))
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .button
        imageView.accessibilityLabel = String(localized: "더보기", bundle: .module) + " +\(moreCount)"
        return imageView
    }

    @objc private func moreTapped() {
        onTapMore?()
    }
}
