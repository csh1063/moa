//
//  FaceEmbedding.swift
//  Domain
//
//  Created by sanghyeon on 5/18/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import CoreGraphics

public struct FaceEmbedding: Hashable, ClusterableEmbedding {
    public let id: UUID
    public let embedding: [Float]
    public let boundingBox: CGRect
    public let hasGlasses: Bool
    public let photoId: String
    /// 얼굴 화질 점수(0~1) — 대표 사진을 화질로 고르는 데 쓴다
    public let captureQuality: Float

    public init(
        id: UUID = UUID(),
        embedding: [Float],
        boundingBox: CGRect,
        hasGlasses: Bool,
        photoId: String = "",
        captureQuality: Float = 0
    ) {
        self.id = id
        self.embedding = embedding
        self.boundingBox = boundingBox
        self.hasGlasses = hasGlasses
        self.photoId = photoId
        self.captureQuality = captureQuality
    }

    public static func == (lhs: FaceEmbedding, rhs: FaceEmbedding) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
