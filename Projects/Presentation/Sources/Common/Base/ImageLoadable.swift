//
//  ImageLoadable.swift
//  Presentation
//
//  Created by sanghyeon on 3/16/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit

protocol ImageLoadable {
    func loadImage(id: String, size: CGSize) async -> UIImage?
    /// 그리드/카드 썸네일 전용 — 저화질 먼저(placeholder) → 고화질로 순차 콜백. onImage는 메인
    /// 스레드에서 불린다. 기본 구현은 기존 단발성 loadImage 결과를 "고화질"(isFinal: true) 한 번만
    /// 콜백하므로, 이 프로토콜을 채택한 곳은 아무것도 안 바꿔도 그대로 동작한다 — 실제 저화질→고화질
    /// 순차 로딩을 쓰려면 이 메서드를 오버라이드해야 한다.
    func loadImageProgressive(id: String, size: CGSize, onImage: @escaping (UIImage?, _ isFinal: Bool) -> Void)
}

extension ImageLoadable {
    func loadImageProgressive(id: String, size: CGSize, onImage: @escaping (UIImage?, Bool) -> Void) {
        Task {
            let image = await loadImage(id: id, size: size)
            onImage(image, true)
        }
    }
}
