//
//  AnalyticsTracker.swift
//  Presentation
//
//  Created by sanghyeon on 7/31/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

// Presentation은 Firebase를 모른다 — 실제 로깅은 App이 logHandler로 주입한다
public final class AnalyticsTracker {

    public static let shared = AnalyticsTracker()
    private init() {}

    public var logHandler: ((String) -> Void)?

    public func logScreenView(_ pageTitle: String) {
        logHandler?(pageTitle)
    }
}
