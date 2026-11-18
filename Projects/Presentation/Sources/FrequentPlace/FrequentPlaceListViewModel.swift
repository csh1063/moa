//
//  FrequentPlaceListViewModel.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Combine
import Domain

struct FrequentPlaceRow: Equatable {
    let id: UUID
    let title: String
    let address: String
    let latitude: Double
    let longitude: Double
    /// 수정 화면 이름 기본값 — 직접 추가한 동네만 있다(자동은 "여행 제외 지역 N"이라 이름으로 안 씀)
    let manualTitle: String?
}

final class FrequentPlaceListViewModel: BaseViewModel {

    // 추가 지도 시작 위치 — 좌표 있는 사진이 하나도 없을 때(서울시청)
    static let fallbackLocation = (latitude: 37.5663, longitude: 126.9779)

    @Published private(set) var rows: [FrequentPlaceRow] = []
    /// 목록을 나갈 때 여행 앨범을 다시 만들지 물어볼지 — 추가/삭제가 한 번이라도 있었으면 true
    private(set) var hasChanges = false

    private let useCase: FrequentPlaceUseCase

    init(useCase: FrequentPlaceUseCase) {
        self.useCase = useCase
        super.init()
    }

    func load() async {
        // 예전 자동 지역은 첫 진입 때 주소를 찾느라 오래 걸린다
        isLoading = true
        defer { isLoading = false }
        do {
            let places = try await useCase.fetchPlaces()
            var autoIndex = 0
            rows = places.map { place in
                let title: String
                if place.isManual {
                    title = place.title ?? ""
                } else {
                    autoIndex += 1
                    title = String(localized: "여행 제외 지역 \(autoIndex) (자동)", bundle: .module)
                }
                return FrequentPlaceRow(
                    id: place.id,
                    title: title,
                    address: place.address ?? String(localized: "주소 정보 없음", bundle: .module),
                    latitude: place.latitude,
                    longitude: place.longitude,
                    manualTitle: place.isManual ? place.title : nil
                )
            }
        } catch {
            debugLog("error: \(error.localizedDescription)")
        }
    }

    func startLocation() -> (latitude: Double, longitude: Double) {
        (try? useCase.lastPhotoLocation()) ?? Self.fallbackLocation
    }

    func add(latitude: Double, longitude: Double, title: String, address: String?) async {
        do {
            try useCase.addPlace(latitude: latitude, longitude: longitude, title: title, address: address)
            hasChanges = true
            await load()
        } catch {
            debugLog("error: \(error.localizedDescription)")
        }
    }

    func update(id: UUID, latitude: Double, longitude: Double, title: String, address: String?) async {
        do {
            try useCase.updatePlace(id: id, latitude: latitude, longitude: longitude, title: title, address: address)
            hasChanges = true
            await load()
        } catch {
            debugLog("error: \(error.localizedDescription)")
        }
    }

    func confirmDelete(_ row: FrequentPlaceRow, onDeleted: @escaping () -> Void) {
        showAlert(
            title: String(localized: "\(row.title)을(를) 삭제할까요?", bundle: .module),
            message: String(localized: "이 동네 근처에서 찍은 사진도 여행으로 묶이게 돼요", bundle: .module),
            buttons: [
                AlertButtonConfig(title: String(localized: "취소", bundle: .module), style: .cancel, action: nil),
                AlertButtonConfig(title: String(localized: "삭제", bundle: .module), style: .destructive) { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in
                        do {
                            try self.useCase.deletePlace(id: row.id)
                            self.hasChanges = true
                            await self.load()
                            onDeleted()
                        } catch {
                            debugLog("error: \(error.localizedDescription)")
                        }
                    }
                }
            ]
        )
    }
}
