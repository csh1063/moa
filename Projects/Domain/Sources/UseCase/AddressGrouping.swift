//
//  AddressGrouping.swift
//  Domain
//
//  Created by sanghyeon on 9/9/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 주소 기반 묶음 키 — 지역 앨범과 장소 지도가 같은 기준을 쓰도록 공용으로 뺐다
public enum AddressGrouping {

    /// 필드별로 정제된 주소 구성요소
    public struct CleanedAddressComponents {
        public let country: String?
        public let administrativeArea: String?
        public let locality: String?
        public let subLocality: String?
    }

    public static func cleanedComponents(for address: PhotoLocation) -> CleanedAddressComponents? {
        guard let country = address.country, !country.isEmpty else { return nil }
        let isoCode = address.isoCountryCode ?? ""

        func clean(_ raw: String?) -> String? {
            guard let raw, !raw.isEmpty else { return nil }
            return TravelAlbumNaming.cleanAreaName(raw, isoCode: isoCode)
        }

        return CleanedAddressComponents(
            country: clean(country),
            administrativeArea: clean(address.administrativeArea),
            locality: clean(address.locality),
            subLocality: clean(address.subLocality)
        )
    }

    /// key: 국가+시/도 단위, value: 시/군/구+동 단위(더 촘촘한 라벨/지도 클러스터용)
    public static func keyValue(for address: PhotoLocation) -> (key: String, value: String)? {
        guard let components = cleanedComponents(for: address), let country = components.country else { return nil }

        let administrativeArea = components.administrativeArea ?? ""
        let locality = components.locality ?? ""
        let subLocality = components.subLocality ?? ""
        let key = "\(country) \(administrativeArea)".trimmingCharacters(in: .whitespaces)

        let addressText: String
        if locality == administrativeArea || locality.hasSuffix("도") {
            addressText = subLocality
        } else {
            addressText = [locality, subLocality]
                .reduce(into: [String]()) { result, value in
                    if result.last != value { result.append(value) }
                }
                .joined(separator: " ")
        }

        return (key, addressText)
    }
}
