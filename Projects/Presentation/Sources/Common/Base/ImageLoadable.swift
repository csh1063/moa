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
    /// 썸네일용 — 저화질 → 고화질 순으로 메인 스레드에서 콜백. 기본 구현은 loadImage 결과를 고화질로 한 번만
    func loadImageProgressive(id: String, size: CGSize, onImage: @escaping (UIImage?, _ isFinal: Bool) -> Void)
}

extension ImageLoadable {
    func loadImageProgressive(id: String, size: CGSize, onImage: @escaping (UIImage?, Bool) -> Void) {
        Task {
            let image = await loadImage(id: id, size: size)
            // 백그라운드에서 끝날 수 있어서 메인으로 보낸다(UI를 만지면 크래시)
            await MainActor.run {
                onImage(image, true)
            }
        }
    }
}
