//
//  CountBadgeLabel.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

/// 사진 수 배지 — 최소 폭 제약과 함께 쓰면, 숫자가 길어질 때 텍스트 양옆 여백을 유지한 채 배지가 늘어난다
final class CountBadgeLabel: UILabel {

    private let horizontalPadding: CGFloat = 4

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + horizontalPadding * 2, height: size.height)
    }
}
