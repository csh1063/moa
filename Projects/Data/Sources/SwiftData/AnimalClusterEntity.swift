//
//  AnimalClusterEntity.swift
//  Data
//
//  Created by sanghyeon on 7/19/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import SwiftData

@Model
public final class AnimalClusterEntity {
    @Attribute(.unique) public var id: UUID
    public var centroidData: Data
    public var excludedPhotoIds: [String] = []
    public var createdAt: Date = Date()

    /// 합쳐지기 직전의 원래 앨범 이름 — 분리할 때 복원용, 이미 있으면 처음 이름 유지
    public var originalName: String?
    public var originalDisplayName: String?
    public var originalIsRenamed: Bool = false

    @Relationship(deleteRule: .nullify)
    public var album: AlbumEntity?

    @Relationship(deleteRule: .nullify)
    public var animalEmbeddings: [AnimalEmbeddingEntity] = []

    public init(id: UUID = UUID(), centroidData: Data) {
        self.id = id
        self.centroidData = centroidData
    }
}
