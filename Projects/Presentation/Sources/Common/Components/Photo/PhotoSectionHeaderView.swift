//
//  PhotoSectionHeaderView.swift
//  Presentation
//
//  Created by sanghyeon on 4/19/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

final class PhotoSectionHeaderView: UICollectionReusableView {

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let chevronIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.down")?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = Theme.textSecondary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    /// 섹션 접기/펼치기를 지원하는 화면(시간 모두보기)에서만 쓰인다 — nil이면 탭해도 아무 반응 없다
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(with data: PhotoHeader) {
        titleLabel.text = data.title
        countLabel.text = String(localized: "\(data.count)장", bundle: .module)
    }

    /// 접기 지원 화면에서 현재 접힘 상태에 맞춰 화살표를 회전시킨다. animated가 false인 상태로 매번
    /// 재사용 셀에 configure될 때도 호출되므로, 회전 애니메이션은 실제 탭(toggle) 시점에만 켠다.
    func setCollapsible(isCollapsed: Bool, animated: Bool) {
        chevronIcon.isHidden = false
        let rotation: CGFloat = isCollapsed ? -.pi / 2 : 0
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.chevronIcon.transform = CGAffineTransform(rotationAngle: rotation)
            }
        } else {
            chevronIcon.transform = CGAffineTransform(rotationAngle: rotation)
        }
    }

    private func setupView() {

        self.backgroundColor = Theme.background

        titleLabel.textColor = Theme.textPrimary
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        countLabel.textColor = Theme.textSecondary
        countLabel.font = .systemFont(ofSize: 14)
        countLabel.textAlignment = .right

        chevronIcon.isHidden = true

        self.addSubview(titleLabel)
        self.addSubview(chevronIcon)
        self.addSubview(countLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(self).offset(12)
            make.bottom.equalTo(self).offset(-12)
            make.leading.equalTo(self).inset(20)
        }

        chevronIcon.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.leading.equalTo(titleLabel.snp.trailing).offset(6)
            make.size.equalTo(14)
        }

        countLabel.snp.makeConstraints { make in
            make.bottom.equalTo(titleLabel)
            make.trailing.equalTo(self).inset(20)
            make.leading.greaterThanOrEqualTo(chevronIcon.snp.trailing).offset(8)
        }
    }

    @objc private func handleTap() {
        onTap?()
    }
}
