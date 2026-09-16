//
//  AddressGrouping.swift
//  Domain
//
//  Created by sanghyeon on 9/9/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 주소 기반으로 사진을 묶을 때 쓰는 키 계산 — 위치 앨범(AutoAlbumUseCase)과 장소 지도
/// (PhotoMapClustering)가 같은 기준으로 묶이도록 공용으로 뺀 순수 함수.
public enum AddressGrouping {

    /// 필드별로 정제된(cleanAreaName 적용) 주소 구성요소 — 장소 지도가 줌 단계별로 country부터
    /// subLocality까지 몇 단계를 쓸지는 스스로 정하되, 각 필드의 정제 규칙은 여기 걸 그대로 쓴다.
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
