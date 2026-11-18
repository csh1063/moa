//
//  AlbumSelectionActionBar.swift
//  Presentation
//
//  Created by sanghyeon on 7/22/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//
//  메인/전체보기 화면에서 앨범을 여러 개 선택했을 때 쓰는 하단 액션바 — 앨범 상세의
//  bottomBar(선택한 사진 개수 + 삭제/제외 버튼)와 같은 역할을 앨범 목록 레벨에서 한다.

import UIKit
import SnapKit
import Combine

final class AlbumSelectionActionBar: UIView {

    private let countLabel: UILabel = {
        let lb = UILabel()
        lb.textColor = Theme.textSecondary
        lb.font = .systemFont(ofSize: 14, weight: .regular)
        lb.text = String(localized: "0개 선택", bundle: .module)
        return lb
    }()

    private let deleteButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(named: "lucide_trash_2", in: .module, with: nil)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.negative
        config.cornerStyle = .medium
        return UIButton(configuration: config)
    }()

    private let deleteSubject = PassthroughSubject<Void, Never>()
    var deletePublisher: AnyPublisher<Void, Never> { deleteSubject.eraseToAnyPublisher() }

    /// 앨범 상세 하단바와 같은 고정 높이 88 + 중심 -10 — safe area는 이 여백으로 흡수한다
    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.background
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowRadius = 8

        addSubview(countLabel)
        addSubview(deleteButton)

        countLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview().offset(-10)
        }
        deleteButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalToSuperview().offset(-10)
            make.height.equalTo(44)
            make.width.equalTo(44)
        }

        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("AlbumSelectionActionBar does not support NSCoding")
    }

    func setSelectedCount(_ count: Int) {
        countLabel.text = String(localized: "\(count)개 선택", bundle: .module)
        deleteButton.isEnabled = count > 0
        deleteButton.alpha = count > 0 ? 1.0 : 0.4
    }

    @objc private func deleteTapped() {
        deleteSubject.send()
    }
}
