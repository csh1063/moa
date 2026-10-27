//
//  GeocoderService.swift
//  Data
//
//  Created by sanghyeon on 3/20/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import CoreLocation
import Domain

public final class GeocoderService {

    // MARK: - 단어 목록 로드
    private let replaceTerms: [String: String] = {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "ReplaceWord", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            debugLog("GeocoderService: ReplaceWord.json 로드 실패")
            return [:]
        }
        return dict
    }()

    // CLGeocoder가 응답을 영영 안 줄 수 있다(레이트리밋/네트워크 문제 등) — 타임아웃 없이 걸리면
    // 이걸 순차로 돌리는 여행 감지 파이프라인 전체가 멈춘다. 비슷한 사진 쪽 PHImageManager 콜백에
    // 이미 걸어둔 것과 같은 이유의 같은 종류 안전장치
    private static let geocodeTimeout: TimeInterval = 8

    public init() {

    }

    // MARK: - Public
    func fetchAddress(from location: CLLocation, locale: Locale = .current) async throws -> PhotoLocation? {

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await withTimeout(Self.geocodeTimeout) {
                try await geocoder.reverseGeocodeLocation(location, preferredLocale: locale)
            }

            guard let data = placemarks.first else { return PhotoLocation() }

            let location = mapping(of: data)
            return location
        } catch {
            debugLog("CLGeocoder 실패: \(error)")
            return nil
        }
    }

    func fetchAddress(latitude: Double, longitude: Double, locale: Locale = .current) async throws -> PhotoLocation? {

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await withTimeout(Self.geocodeTimeout) {
                try await geocoder.reverseGeocodeLocation(
                    CLLocation(latitude: latitude, longitude: longitude),
                    preferredLocale: locale
                )
            }

            guard let data = placemarks.first else { return PhotoLocation() }

            let location = mapping(of: data)
            return location
        } catch {
            debugLog("CLGeocoder 실패: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw GeocodeTimeoutError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
    private func replaceAddress(_ string: String?) -> String {
        guard let string else { return "" }

        for (key, value) in self.replaceTerms where key == string {
            return value
        }
        return string
    }

    private func mapping(of placemark: CLPlacemark) -> PhotoLocation {
        PhotoLocation(
            name: replaceAddress(placemark.name),
            thoroughfare: replaceAddress(placemark.thoroughfare),
            subThoroughfare: replaceAddress(placemark.subThoroughfare),
            locality: replaceAddress(placemark.locality),
            subLocality: replaceAddress(placemark.subLocality),
            administrativeArea: replaceAddress(placemark.administrativeArea),
            subAdministrativeArea: replaceAddress(placemark.subAdministrativeArea),
            postalCode: replaceAddress(placemark.postalCode),
            isoCountryCode: placemark.isoCountryCode,
            country: replaceAddress(placemark.country),
            inlandWater: replaceAddress(placemark.inlandWater),
            ocean: replaceAddress(placemark.ocean)

//            country: replaceAddress(placemark.country),
//            administrativeArea: replaceAddress(placemark.administrativeArea),
//            locality: replaceAddress(placemark.locality),
//            subLocality: replaceAddress(placemark.subLocality),
//            thoroughfare: replaceAddress(placemark.thoroughfare),
//            ocean: replaceAddress(placemark.ocean),
//            isoCountryCode: placemark.isoCountryCode)
            )
    }
}

private struct GeocodeTimeoutError: Error {}
