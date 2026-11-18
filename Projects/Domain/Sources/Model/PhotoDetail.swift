//
//  PhotoDetail.swift
//  Domain
//
//  Created by sanghyeon on 5/8/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public struct PhotoDetail {
    public let id: String
    public let createdDate: Date?
    public var photo: Photo?
    public var labels: [PhotoLabel] = []
    /// PHAsset 기준 영상 여부 — 미분석 사진은 photo가 nil이라 따로 받는다
    public let isVideo: Bool

    public init(id: String, createdDate: Date?, photo: Photo? = nil, isVideo: Bool? = nil) {
        self.id = id
        self.createdDate = createdDate
        self.photo = photo
        self.isVideo = isVideo ?? (photo?.isVideo ?? false)
    }
}
