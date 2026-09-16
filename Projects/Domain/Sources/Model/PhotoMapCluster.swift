//
//  PhotoMapCluster.swift
//  Domain
//
//  Created by sanghyeon on 9/9/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 장소 지도 화면의 핀 하나 — 주소 기준으로 묶인 사진 그룹. 핀 위치는 그 그룹에 속한 사진들의
/// 실제 좌표 평균(centroid)이고, 대표 썸네일은 가장 최근 사진.
public struct PhotoMapCluster {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    /// 최신순 정렬 — first가 대표 썸네일/뷰어 시작 지점
    public let photos: [Photo]

    public init(id: String, latitude: Double, longitude: Double, photos: [Photo]) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.photos = photos
    }
}
