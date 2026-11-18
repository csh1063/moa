//
//  AlbumCellViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 5/30/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Domain

protocol AlbumCellViewModel: Hashable {
    var id: UUID { get }
    var localIdentifier: String { get }
    var displayName: String { get }
    var formattedDate: String { get }
    var photoCount: Int { get }

    var album: Album { get }

    var imageLoader: any ImageLoadable {get}
}

extension AlbumCellViewModel {

    func loadImage(size: CGSize) async -> UIImage? {
        await imageLoader.loadImage(id: localIdentifier, size: size)
    }

    func loadImageProgressive(size: CGSize, onImage: @escaping (UIImage?, Bool) -> Void) {
        imageLoader.loadImageProgressive(id: localIdentifier, size: size, onImage: onImage)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // 사진 수와 커버까지 비교해야 합치기/사진 추가 뒤에 셀이 다시 그려진다
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.photoCount == rhs.photoCount
            && lhs.localIdentifier == rhs.localIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
