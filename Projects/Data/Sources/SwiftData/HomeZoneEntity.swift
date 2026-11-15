//
//  HomeZoneEntity.swift
//  Data
//
//  Created by sanghyeon on 5/24/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import SwiftData
import Foundation

@Model
public final class HomeZoneEntity {
    public var latitude: Double
    public var longitude: Double
    public var analyzedAt: Date
    // 아래는 "자주가는 동네"(직접 추가/삭제)용으로 추가 — 기본값이 있어서 기존 데이터는 자동 측정 동네로 이어진다
    public var id: UUID = UUID()
    public var isManual: Bool = false
    public var title: String?
    public var address: String?

    public init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        analyzedAt: Date,
        isManual: Bool = false,
        title: String? = nil,
        address: String? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.analyzedAt = analyzedAt
        self.isManual = isManual
        self.title = title
        self.address = address
    }
}
