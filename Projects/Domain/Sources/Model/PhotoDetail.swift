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
    public let photo: Photo?
    public var labels: [PhotoLabel] = []
    /// PHAsset 기준 영상 여부 — photo(분석 결과, 미분석이면 nil)에 기대지 않고 항상 명시적으로 받는다.
    /// 안 넘기면 photo.isVideo로 대체하지만, 미분석 사진은 photo가 nil이라 이 fallback만으로는
    /// 영상 여부를 알 수 없다(실제로 이 문제로 사진첩 탭에서 영상 재생이 전혀 동작하지 않는 버그가 있었음)
    public let isVideo: Bool

    public init(id: String, createdDate: Date?, photo: Photo? = nil, isVideo: Bool? = nil) {
        self.id = id
        self.createdDate = createdDate
        self.photo = photo
        self.isVideo = isVideo ?? (photo?.isVideo ?? false)
    }
}
