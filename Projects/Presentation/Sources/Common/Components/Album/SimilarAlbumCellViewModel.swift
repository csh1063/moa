//
//  SimilarAlbumCellViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 6/24/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Domain

final class SimilarAlbumCellViewModel: AlbumCellViewModel {

    var id: UUID
    var localIdentifier: String
    /// 스택 카드 앞/중간/뒤에 쓸 실제 사진 식별자(최신순, 최대 3장) — album.photos가 비어있으면
    /// (가벼운 목록 조회 경로) 커버 1장으로 대체해서 기존처럼 동작한다.
    var stackIdentifiers: [String]
    var displayName: String
    var formattedDate: String
    var photoCount: Int

    var album: Album
    var imageLoader: any ImageLoadable

    init(album: Album, imageLoader: any ImageLoadable) {
        self.id = album.id
        self.localIdentifier = album.coverPhotoIdentifier ?? ""
        let photoIds = album.photos.map { $0.localIdentifier }
        self.stackIdentifiers = photoIds.isEmpty
            ? [self.localIdentifier]
            : Array(photoIds.prefix(3))
        self.displayName = album.displayName.replacingOccurrences(of: "_", with: " ")
        self.formattedDate = ""
        self.photoCount = album.photoCount
        self.album = album
        self.imageLoader = imageLoader
    }
}
