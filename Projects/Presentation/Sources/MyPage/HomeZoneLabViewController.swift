//
//  HomeZoneLabViewController.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import MapKit
import Combine
import Domain

/// 실험실 — 지금 저장된 홈존을 지도(여행 판정 반경 원)와 목록으로 보여준다
// shortcut: 디버그 전용이라 ViewModel 없이 리포지토리를 바로 쓴다, 정식 화면이 되면 UseCase/ViewModel로 분리
final class HomeZoneLabViewController: UIViewController {

    // DefaultTravelDetectionRepository.homeZoneRadius와 같은 값 — 이 안에서 찍힌 사진은 여행으로 안 본다
    private let homeZoneRadius: CLLocationDistance = 20_000

    private let homeZoneRepository: HomeZoneRepository
    private let photoDataRepository: PhotoDataRepository

    private var zones: [HomeZone] = []
    private var rows: [(title: String, detail: String)] = []
    private var cancellables = Set<AnyCancellable>()

    private let naviView = NaviBarView()
    private let mapView = MKMapView()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.strokeSoft
        return tableView
    }()

    init(homeZoneRepository: HomeZoneRepository, photoDataRepository: PhotoDataRepository) {
        self.homeZoneRepository = homeZoneRepository
        self.photoDataRepository = photoDataRepository
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        naviView.publisher
            .sink { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }
            .store(in: &cancellables)
        load()
    }

    private func setupUI() {
        view.backgroundColor = Theme.background
        naviView.setTitle("홈존")
        naviView.addButtons([LeftButton(type: .back)])
        mapView.delegate = self

        view.addSubview(mapView)
        view.addSubview(tableView)
        view.addSubview(naviView)

        naviView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        mapView.snp.makeConstraints { make in
            make.top.equalTo(naviView.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(320)
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(mapView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func load() {
        zones = (try? homeZoneRepository.fetchHomeZones()) ?? []
        showOnMap()

        guard !zones.isEmpty else {
            rows = [("홈존 없음", "분석 전이거나, 최근 사진 중 홈존 조건을 만족하는 장소가 없어요")]
            tableView.reloadData()
            return
        }

        rows = zones.enumerated().map { index, zone in ("홈존 \(index + 1)", detail(of: zone, address: "주소 찾는 중…")) }
        tableView.reloadData()

        // 주소는 홈존에서 가장 가까운 사진에서 뽑는데 좌표 있는 사진을 전부 훑어서, 메인 스레드 밖에서 한다
        let zones = self.zones
        let photoDataRepository = self.photoDataRepository
        Task {
            let addresses = await Task.detached {
                let photos = ((try? photoDataRepository.fetchHasCoordinators()) ?? []).map { PhotoLocationSnapshot(from: $0) }
                return zones.map { $0.addressDescription(in: photos) }
            }.value
            self.rows = zip(zones, addresses).enumerated().map { index, pair in
                ("홈존 \(index + 1)", self.detail(of: pair.0, address: pair.1))
            }
            self.tableView.reloadData()
        }
    }

    private func detail(of zone: HomeZone, address: String) -> String {
        let analyzedAt = zone.analyzedAt.formatted(date: .numeric, time: .shortened)
        return "\(address)\n위도 \(zone.latitude), 경도 \(zone.longitude)\n분석일 \(analyzedAt)"
    }

    private func showOnMap() {
        var visibleRect = MKMapRect.null
        for (index, zone) in zones.enumerated() {
            let center = CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude)

            let annotation = MKPointAnnotation()
            annotation.coordinate = center
            annotation.title = "홈존 \(index + 1)"
            mapView.addAnnotation(annotation)

            let circle = MKCircle(center: center, radius: homeZoneRadius)
            mapView.addOverlay(circle)
            visibleRect = visibleRect.union(circle.boundingMapRect)
        }
        guard !visibleRect.isNull else { return }
        mapView.setVisibleMapRect(visibleRect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
    }
}

extension HomeZoneLabViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = rows[indexPath.row].title
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        content.textProperties.color = Theme.textPrimary
        content.secondaryText = rows[indexPath.row].detail
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = Theme.textSecondary
        content.textToSecondaryTextVerticalPadding = 6
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.background
        return cell
    }

    // 목록에서 고르면 지도를 그 홈존 반경으로 옮긴다
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard zones.indices.contains(indexPath.row) else { return }
        let zone = zones[indexPath.row]
        let circle = MKCircle(center: CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude), radius: homeZoneRadius)
        mapView.setVisibleMapRect(circle.boundingMapRect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: true)
    }
}

extension HomeZoneLabViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKCircleRenderer(circle: circle)
        renderer.fillColor = Theme.primary.withAlphaComponent(0.15)
        renderer.strokeColor = Theme.primary
        renderer.lineWidth = 1.5
        return renderer
    }
}
