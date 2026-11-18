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
        // 여행 직후 몇 장만 본 증분 상황 — 0개라고 기존 홈존을 지우면 안 된다
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

    func test_shortAddress_dedupsCityAndSkipsEmpty() {
        // 한국 주소는 administrativeArea와 locality가 둘 다 "서울특별시"로 오는 경우가 있다
        XCTAssertEqual(HomeZone.shortAddress(["서울특별시", "서울특별시", "성동구", "성수동"]), "서울특별시 성동구 성수동")
        XCTAssertEqual(HomeZone.shortAddress(["경기도", nil, "", "판교역로"]), "경기도 판교역로")
        XCTAssertNil(HomeZone.shortAddress([nil, "", nil]))
    }

    func test_couldNotVisitHome_onlyWhenGapTooShortForDetour() {
        let seoul = [HomeZone(latitude: 37.5665, longitude: 126.9780, analyzedAt: now)]
        let amsterdam = (latitude: 52.3676, longitude: 4.9041)
        let paris = (latitude: 48.8566, longitude: 2.3522)
        let tokyo = (latitude: 35.6762, longitude: 139.6503)
        let bangkok = (latitude: 13.7563, longitude: 100.5018)

        // 유럽 안에서 8시간 — 서울 왕복만 비행기로 최소 18시간이라 집에 못 갔다
        XCTAssertTrue(HomeZoneDetection.couldNotVisitHome(from: amsterdam, to: paris, gap: 8 * 3600, homeZones: seoul))
        // 실제 유럽 여행 간격(21.7시간) — 비행만 19.5시간이지만 공항 시간 2시간 × 2를 더하면 23.5시간이라 못 갔다
        XCTAssertTrue(HomeZoneDetection.couldNotVisitHome(from: amsterdam, to: paris, gap: 21.7 * 3600, homeZones: seoul))
        XCTAssertFalse(HomeZoneDetection.couldNotVisitHome(from: amsterdam, to: paris, gap: 24 * 3600, homeZones: seoul))
        // 도쿄 → 방콕 이틀 — 서울 경유(약 5시간)가 가능했으니 다른 여행일 수 있다
        XCTAssertFalse(HomeZoneDetection.couldNotVisitHome(from: tokyo, to: bangkok, gap: 2 * day, homeZones: seoul))
        // 1,000km 미만은 공항 시간을 안 더한다 — 집(브뤼셀)이 가까우면 기차로 금방 다녀올 수 있다
        let brussels = [HomeZone(latitude: 50.8503, longitude: 4.3517, analyzedAt: now)]
        XCTAssertFalse(HomeZoneDetection.couldNotVisitHome(from: amsterdam, to: paris, gap: 3 * 3600, homeZones: brussels))
        // 홈존이 없으면 판단 불가
        XCTAssertFalse(HomeZoneDetection.couldNotVisitHome(from: amsterdam, to: paris, gap: 8 * 3600, homeZones: []))
    }

    func test_travelClusterAddress_listsCountriesOnceInVisitOrder() {
        let cluster = TravelCluster(
            photos: [],
            country: "네덜란드",
            administrativeArea: "노르트홀란트",
            locality: "암스테르담",
            subLocality: nil,
            isoCountryCode: "NL",
            startDate: now,
            endDate: now,
            visitedCountries: ["네덜란드", "프랑스", "스위스", "프랑스"]
        )
        XCTAssertEqual(cluster.address, "네덜란드 프랑스 스위스")
    }
}
