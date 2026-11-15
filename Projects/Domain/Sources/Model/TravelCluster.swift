//
//  TravelCluster.swift
//  Domain
//
//  Created by sanghyeon on 5/6/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

public struct TravelCluster {
    public let photos: [PhotoLocationSnapshot]
    public let country: String
    public let administrativeArea: String
    public let locality: String?
    public let subLocality: String?
    public let isoCountryCode: String
    public let startDate: Date
    public let endDate: Date
    /// 나라를 넘나든 여행을 합쳤을 때 방문 순서(중복 포함) — 마지막 원소가 직전에 있던 나라
    public let visitedCountries: [String]

    public var address: String {
        // 여러 나라면 처음 간 순서대로 한 번씩만 나열: "네덜란드 프랑스 스위스"
        let countries = visitedCountries.reduce(into: [String]()) { result, country in
            if !result.contains(country) { result.append(country) }
        }
        if countries.count > 1 { return countries.joined(separator: " ") }
        return locality?.isEmpty == false ? locality! :
        administrativeArea.isEmpty ? country :
        administrativeArea
    }

    public init(
        photos: [PhotoLocationSnapshot],
        country: String,
        administrativeArea: String,
        locality: String?,
        subLocality: String?,
        isoCountryCode: String,
        startDate: Date,
        endDate: Date,
        visitedCountries: [String]? = nil
    ) {
        self.photos = photos
        self.country = country
        self.administrativeArea = administrativeArea
        self.locality = locality
        self.subLocality = subLocality
        self.isoCountryCode = isoCountryCode
        self.startDate = startDate
        self.endDate = endDate
        self.visitedCountries = visitedCountries ?? (country.isEmpty ? [] : [country])
    }
}
