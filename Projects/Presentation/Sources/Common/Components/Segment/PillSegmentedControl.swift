//
//  PillSegmentedControl.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit

/// 둥근 트랙 위에서 primary 알약이 선택 항목으로 미끄러지는 세그먼트 — 탭바(필 모양)와 같은 톤
final class PillSegmentedControl: UIView {

    /// 사용자가 탭해서 바뀌었을 때만 불린다(코드로 바꾼 건 안 부름)
    var onChange: ((Int) -> Void)?
    private(set) var selectedIndex = 0

    private let inset: CGFloat = 3
    private let thumbView: UIView = {
        let v = UIView()
        v.backgroundColor = Theme.primary
        return v
    }()
    private var buttons: [UIButton] = []

    init(items: [String]) {
        super.init(frame: .zero)
        backgroundColor = Theme.surface
        addBorder(color: Theme.strokeSoft, borderWidth: 1)
        addSubview(thumbView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(inset)
        }

        buttons = items.enumerated().map { index, title in
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.tag = index
            button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            return button
        }
        updateButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 40)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layoutThumb()
    }

    func setSelectedIndex(_ index: Int, animated: Bool) {
        guard buttons.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        let changes = { self.layoutThumb(); self.updateButtons() }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4, animations: changes)
        } else {
            changes()
        }
    }

    private func layoutThumb() {
        guard !buttons.isEmpty, bounds.width > 0 else { return }
        let width = (bounds.width - inset * 2) / CGFloat(buttons.count)
        thumbView.frame = CGRect(x: inset + width * CGFloat(selectedIndex), y: inset, width: width, height: bounds.height - inset * 2)
        thumbView.layer.cornerRadius = thumbView.bounds.height / 2
    }

    private func updateButtons() {
        for button in buttons {
            let isSelected = button.tag == selectedIndex
            button.setTitleColor(isSelected ? .white : Theme.textSecondary, for: .normal)
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    @objc private func didTap(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        setSelectedIndex(sender.tag, animated: true)
        onChange?(sender.tag)
    }
}
