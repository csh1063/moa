//
//  FrequentPlaceAddViewController.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import MapKit
import Combine
import SnapKit
import Domain

/// 자주가는 동네 추가/수정 — 검색하거나 지도를 움직여 가운데에 핀을 꽂고, 적용 → 이름 정해서 저장
/// 지도를 끄는 제스처가 뒤로가기로 먹히지 않게 전체화면으로 띄운다
final class FrequentPlaceAddViewController: UIViewController {

    var onSave: ((_ latitude: Double, _ longitude: Double, _ title: String, _ address: String?) -> Void)?

    private let startCoordinate: CLLocationCoordinate2D
    /// 수정일 때 이름 시트의 기본값 — nil이면 지금 위치의 동/도로명
    private let initialName: String?
    private let isEditMode: Bool
    private let geocoder = CLGeocoder()
    private var currentAddress: String?
    /// 이름 기본값 — 동/도로명이 있으면 그것만
    private var currentShortName: String?
    private var cancellables = Set<AnyCancellable>()

    // 주소 검색은 지금 위치와 무관해야 해서 대한민국 전체를 고정 범위로 준다 — 범위가 없으면 도로명을 못 찾는다
    private let searchCompleter: MKLocalSearchCompleter = {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 36.5, longitude: 127.8),
            span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
        )
        return completer
    }()
    private var searchResults: [MKLocalSearchCompletion] = []

    private let naviView = NaviBarView()

    private let searchField: UITextField = {
        let tf = UITextField()
        tf.placeholder = String(localized: "주소 검색 (예: 성동구 성수동)", bundle: .module)
        tf.font = .systemFont(ofSize: 15, weight: .regular)
        tf.textColor = Theme.textPrimary
        tf.backgroundColor = Theme.surface
        tf.layer.cornerRadius = 12
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        tf.leftViewMode = .always
        tf.returnKeyType = .search
        tf.clearButtonMode = .whileEditing
        return tf
    }()

    private let searchButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "검색", bundle: .module)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.cornerStyle = .medium
        return UIButton(configuration: config)
    }()

    private let mapView = MKMapView()

    private let resultsTableView: UITableView = {
        let tv = UITableView()
        tv.backgroundColor = Theme.surface
        tv.layer.cornerRadius = 12
        tv.rowHeight = 52
        tv.isHidden = true
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return tv
    }()

    private let targetView: UIImageView = {
        let iv = UIImageView(image: UIImage(named: "lucide_locate_fixed", in: .module, with: nil)?.withRenderingMode(.alwaysTemplate))
        iv.tintColor = Theme.textSecondary
        return iv
    }()

    private let pinView: UIImageView = {
        let iv = UIImageView(image: UIImage(named: "lucide_map_pin", in: .module, with: nil)?.withRenderingMode(.alwaysTemplate))
        iv.tintColor = Theme.primary
        return iv
    }()

    private let bottomView: UIView = {
        let v = UIView()
        v.backgroundColor = Theme.surface
        v.layer.cornerRadius = 20
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return v
    }()

    private let addressLabel: UILabel = {
        let lb = UILabel()
        lb.font = .systemFont(ofSize: 16, weight: .semibold)
        lb.textColor = Theme.textPrimary
        lb.numberOfLines = 2
        lb.text = String(localized: "주소 확인 중…", bundle: .module)
        return lb
    }()

    private let applyButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "적용", bundle: .module)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.cornerStyle = .medium
        return UIButton(configuration: config)
    }()

    init(startLatitude: Double, startLongitude: Double, isEditMode: Bool = false, initialName: String? = nil) {
        self.startCoordinate = CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
        self.isEditMode = isEditMode
        self.initialName = initialName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        naviView.publisher
            .sink { [weak self] type in
                if type == .close { self?.dismiss(animated: true) }
            }
            .store(in: &cancellables)

        mapView.setRegion(
            MKCoordinateRegion(center: startCoordinate, latitudinalMeters: 3000, longitudinalMeters: 3000),
            animated: false
        )
        updateAddress()
    }

    private func setupUI() {
        view.backgroundColor = Theme.background
        naviView.setTitle(isEditMode
            ? String(localized: "동네 수정", bundle: .module)
            : String(localized: "동네 추가", bundle: .module))
        naviView.addButtons([LeftButton(type: .close)])

        mapView.delegate = self
        mapView.showsCompass = false
        searchField.delegate = self
        searchCompleter.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.delegate = self

        view.addSubview(mapView)
        view.addSubview(targetView)
        view.addSubview(pinView)
        view.addSubview(searchField)
        view.addSubview(searchButton)
        view.addSubview(bottomView)
        view.addSubview(resultsTableView)
        bottomView.addSubview(addressLabel)
        bottomView.addSubview(applyButton)
        view.addSubview(naviView)

        naviView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        searchField.snp.makeConstraints { make in
            make.top.equalTo(naviView.snp.bottom).offset(8)
            make.leading.equalToSuperview().inset(20)
            make.trailing.equalTo(searchButton.snp.leading).offset(-8)
            make.height.equalTo(44)
        }
        searchButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalTo(searchField)
            make.width.equalTo(64)
            make.height.equalTo(44)
        }
        mapView.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top).offset(20)
        }
        resultsTableView.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(0)
        }
        targetView.snp.makeConstraints { make in
            make.center.equalTo(mapView)
            make.size.equalTo(28)
        }
        // 핀 아이콘의 뾰족한 끝(아이콘 아래쪽 가운데)이 타겟 한가운데에 꽂히도록 핀의 아래를 지도 중심에 맞춘다
        pinView.snp.makeConstraints { make in
            make.centerX.equalTo(mapView)
            make.bottom.equalTo(mapView.snp.centerY).offset(2)
            make.size.equalTo(40)
        }
        bottomView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        addressLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(20)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        applyButton.snp.makeConstraints { make in
            make.top.equalTo(addressLabel.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(12)
            make.height.equalTo(52)
        }

        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
    }

    // MARK: - 주소

    /// 타겟(지도 중심) 좌표의 주소를 하단에 보여준다 — 이전 요청이 남아있으면 취소하고 마지막 위치만 조회
    private func updateAddress() {
        let center = mapView.centerCoordinate
        geocoder.cancelGeocode()
        addressLabel.text = String(localized: "주소 확인 중…", bundle: .module)
        geocoder.reverseGeocodeLocation(
            CLLocation(latitude: center.latitude, longitude: center.longitude),
            preferredLocale: Locale(identifier: "ko_KR")
        ) { [weak self] placemarks, _ in
            guard let self else { return }
            let placemark = placemarks?.first
            let address = HomeZone.shortAddress([
                placemark?.administrativeArea, placemark?.locality, placemark?.subLocality, placemark?.thoroughfare
            ])
            self.currentAddress = address
            self.currentShortName = placemark?.thoroughfare ?? placemark?.subLocality ?? address
            self.addressLabel.text = address ?? String(localized: "주소를 찾을 수 없어요", bundle: .module)
        }
    }

    // MARK: - 검색

    @objc private func searchTapped() {
        search()
    }

    private func search() {
        guard let query = searchField.text?.trimmingCharacters(in: .whitespaces), !query.isEmpty else { return }
        searchField.resignFirstResponder()

        // 같은 검색어면 completer가 다시 알려주지 않으므로 갖고 있는 결과를 다시 보여준다
        if query == searchCompleter.queryFragment {
            showResults()
        } else {
            searchCompleter.queryFragment = query
        }
    }

    private func showResults() {
        guard !searchResults.isEmpty else {
            hideResults()
            let alert = UIAlertController(
                title: String(localized: "검색 결과가 없어요", bundle: .module),
                message: String(localized: "구/동 이름이나 도로명 주소로 다시 검색해보세요", bundle: .module),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "확인", bundle: .module), style: .default))
            present(alert, animated: true)
            return
        }
        resultsTableView.reloadData()
        resultsTableView.snp.updateConstraints { make in
            make.height.equalTo(min(CGFloat(searchResults.count) * resultsTableView.rowHeight, 260))
        }
        resultsTableView.isHidden = false
    }

    private func hideResults() {
        resultsTableView.isHidden = true
    }

    /// 고른 결과의 좌표로 지도를 옮긴다 — 이동이 끝나면 regionDidChange에서 주소가 갱신된다
    private func move(to completion: MKLocalSearchCompletion) {
        hideResults()
        MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start { [weak self] response, _ in
            guard let self, let coordinate = response?.mapItems.first?.placemark.coordinate else { return }
            self.mapView.setCenter(coordinate, animated: true)
        }
    }

    // MARK: - 적용

    @objc private func applyTapped() {
        let center = mapView.centerCoordinate
        let address = currentAddress
        let nameSheet = AlbumRenameSheet(
            albumName: initialName ?? currentShortName ?? "",
            title: String(localized: "동네 이름", bundle: .module),
            subtitle: String(localized: "목록에 보일 이름을 정해주세요", bundle: .module),
            fieldTitle: String(localized: "동네 이름", bundle: .module),
            placeholder: String(localized: "동네 이름 입력", bundle: .module)
        )
        nameSheet.onSave = { [weak self, weak nameSheet] name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let title = trimmed.isEmpty ? (address ?? String(localized: "내 동네", bundle: .module)) : trimmed
            let save = { self?.onSave?(center.latitude, center.longitude, title, address) }
            // 시트는 onSave를 부른 직후에 스스로 닫힌다 — 저장 후 이 화면이 닫히므로 시트가 다 닫힌 뒤에 넘긴다
            DispatchQueue.main.async {
                if let coordinator = nameSheet?.transitionCoordinator {
                    coordinator.animate(alongsideTransition: nil) { _ in save() }
                } else {
                    save()
                }
            }
        }
        if let presentation = nameSheet.sheetPresentationController {
            presentation.detents = [.custom { _ in 260 }]
            presentation.preferredCornerRadius = 28
        }
        present(nameSheet, animated: true)
    }
}

// MARK: - MKMapViewDelegate

extension FrequentPlaceAddViewController: MKMapViewDelegate {

    // 지도를 움직이는 동안 핀이 살짝 떠 있다가, 멈추면 다시 타겟에 꽂힌다
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        hideResults()
        UIView.animate(withDuration: 0.15) {
            self.pinView.transform = CGAffineTransform(translationX: 0, y: -14)
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
            self.pinView.transform = .identity
        }
        updateAddress()
    }
}

// MARK: - UITextFieldDelegate

extension FrequentPlaceAddViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        search()
        return true
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension FrequentPlaceAddViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        showResults()
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        searchResults = []
        showResults()
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension FrequentPlaceAddViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let result = searchResults[indexPath.row]
        var content = cell.defaultContentConfiguration()
        // 결과가 전부 국내라 앞의 "대한민국"은 뺀다
        content.text = result.title.hasPrefix("대한민국 ") ? String(result.title.dropFirst(5)) : result.title
        content.textProperties.color = Theme.textPrimary
        content.textProperties.font = .systemFont(ofSize: 15, weight: .regular)
        content.secondaryText = result.subtitle.isEmpty ? nil : result.subtitle
        content.secondaryTextProperties.color = Theme.textSecondary
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        move(to: searchResults[indexPath.row])
    }
}
