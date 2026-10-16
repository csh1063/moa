//
//  NaviBarButton.swift
//  Presentation
//
//  Created by sanghyeon on 3/29/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Combine

final class NaviBarButton: UIView {

//    public var buttonTintColor: UIColor {
//        get {
//            self.button.tintColor
//        }
//        set {
//            self.button.tintColor = newValue
//        }
//    }

    private let button = UIButton()
    private let dot: UIView = {
        let view = UIView()
        view.backgroundColor = .red
        return view
    }()

    let type: NaviBarButtonType

    var publisher: AnyPublisher<NaviBarButtonType, Never> {
        button.tapPublisher
            .map { [weak self] _ in self?.type ?? .none }
            .eraseToAnyPublisher()
    }

    init(type: NaviBarButtonType) {

        self.type = type

        super.init(frame: .zero)

        self.setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("NaviBarButton dose not support")
    }

    func setEnabled(_ enabled: Bool) {
        button.isEnabled = enabled
        alpha = enabled ? 1.0 : 0.4
    }

    private func setupView() {

        self.backgroundColor = .clear

        dot.isHidden = true
        dot.layer.cornerRadius = 2
        dot.layer.masksToBounds = true

        button.layer.masksToBounds = true

        addSubview(button)
        addSubview(dot)

        button.snp.makeConstraints { make in
            make.top.bottom.equalTo(self).inset(6)
            make.leading.trailing.equalTo(self).inset(6)
            make.width.equalTo(32)
            make.height.equalTo(32)
        }

        dot.snp.makeConstraints { make in
            make.height.width.equalTo(4)
            make.top.equalTo(self).offset(12)
            make.trailing.equalTo(self).offset(-12)
        }

        if type.imageName != "" {
            var image = UIImage(named: type.imageName, in: .module, with: nil)
            // 뒤로가기만 다른 아이콘들보다 존재감이 작게 느껴져서 더 키운다
            if type == .back, let original = image {
                image = original.resized(to: CGSize(width: 28, height: 28))
            }
            self.button.setImage(image?.withRenderingMode(.alwaysTemplate), for: .normal)
        }

        if let text = type.text {
            self.button.setTitle(text, for: .normal)
            self.button.setTitleLabelFont(type.font)
            self.button.setTitleLabelFont(UIFont.systemFont(ofSize: 12))

            button.snp.updateConstraints { make in
                make.width.equalTo(44)
                make.leading.trailing.equalTo(self)
            }
        }

        self.button.setTitleColor(type.foregroundColor, for: .normal)
        self.button.tintColor = type.foregroundColor

        if let backgroundColor = type.backgroundColor {
            self.button.backgroundColor = backgroundColor
//            if type.text == nil {
                self.button.addBorder(color: Theme.strokeSoft, borderWidth: 1)
//            }
            button.layer.cornerRadius = 16
        }
    }
}

private extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
