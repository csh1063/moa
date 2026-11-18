//
//  ClusterableEmbedding.swift
//  Domain
//
//  Created by sanghyeon on 7/19/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 클러스터링 대상의 최소 인터페이스 — 정규화된 임베딩과 photoId(같은 사진 속 개체는 서로 다른 개체)
public protocol ClusterableEmbedding {
    var embedding: [Float] { get }
    var photoId: String { get }
}
