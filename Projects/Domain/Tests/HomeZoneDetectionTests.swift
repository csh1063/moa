//
//  HomeZoneDetectionTests.swift
//  DomainTests
//
//  Created by sanghyeon on 10/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import XCTest
@testable import Domain

final class HomeZoneDetectionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func photo(daysAgo: Double, lat: Double = 37.5665, lng: Double = 126.9780) -> PhotoLocationSnapshot {
        PhotoLocationSnapshot(from: Photo(
            localIdentifier: UUID().uuidString,
            createdAt: now.addingTimeInterval(-daysAgo * day),
            latitude: lat,
            longitude: lng
        ))
    }

    func test_sameCellAcrossThreeWeeks_becomesHomeZone() {
        let photos = [1, 2, 8, 9, 15].map { photo(daysAgo: $0) }

        let zones = HomeZoneDetection.zones(from: photos, now: now)

        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones.first?.analyzedAt, now)
    }

    func test_onlyTwoWeeks_isNotHomeZone() {
        // 여행 직후 몇 장만 본 증분 분석 상황 — 이게 0개라고 기존 홈존을 지우면 안 된다(AutoAlbumUseCase.analyze가 막음)
        let photos = [1, 1.01, 1.02, 8, 8.01].map { photo(daysAgo: $0) }

        XCTAssertTrue(HomeZoneDetection.zones(from: photos, now: now).isEmpty)
    }

    func test_fewerThanFivePhotos_isNotHomeZone() {
        let photos = [1, 8, 15, 22].map { photo(daysAgo: $0) }

        XCTAssertTrue(HomeZoneDetection.zones(from: photos, now: now).isEmpty)
    }

    func test_photosOlderThanThreeMonths_areIgnored() {
        let photos = [100, 101, 108, 115, 122].map { photo(daysAgo: $0) }

        XCTAssertTrue(HomeZoneDetection.zones(from: photos, now: now).isEmpty)
    }

    func test_twoPlaces_sortedByPhotoCount_andCappedAtFive() {
        let home = [1, 2, 3, 8, 9, 15].map { photo(daysAgo: $0) }
        let office = [1, 8, 15, 16, 22].map { photo(daysAgo: $0, lat: 37.4, lng: 127.1) }
        let farAway = (0..<7).flatMap { cell in
            [1, 8, 15, 16, 22].map { photo(daysAgo: $0, lat: 35.0 + Double(cell), lng: 129.0) }
        }

        let zones = HomeZoneDetection.zones(from: office + home + farAway, now: now)

        XCTAssertEqual(zones.count, HomeZoneDetection.maxHomeZones)
        XCTAssertEqual(zones.first?.latitude, 37.5665)
    }

    func test_travelDisplayName_singleDayIsOuting() {
        // 자정을 넘기면 1시간짜리도 "여행"이 되는 알려진 한계가 있어서, 같은 날 정오 기준으로 본다
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        XCTAssertEqual(TravelAlbumNaming.displayName(place: "제주", startDate: start, endDate: start.addingTimeInterval(3600)), "제주 나들이")
        XCTAssertEqual(TravelAlbumNaming.displayName(place: "제주", startDate: start, endDate: start.addingTimeInterval(2 * day)), "제주 여행")
    }
}
