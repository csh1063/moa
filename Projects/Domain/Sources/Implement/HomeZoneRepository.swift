//
//  HomeZoneRepository.swift
//  Domain
//
//  Created by sanghyeon on 5/24/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public protocol HomeZoneRepository {
    /// 자동 측정 + 직접 추가 동네 전부
    func fetchHomeZones() throws -> [HomeZone]
    /// 자동 측정 결과로 자동 동네만 교체한다 — 직접 추가한 동네는 그대로 둔다
    func replaceAutoHomeZones(_ zones: [HomeZone]) throws
    func addManualHomeZone(_ zone: HomeZone) throws
    /// id가 같은 동네의 위치/이름/주소/직접추가 여부를 바꾼다 — 측정 시각은 그대로
    func updateHomeZone(_ zone: HomeZone) throws
    func deleteHomeZone(id: UUID) throws
}
