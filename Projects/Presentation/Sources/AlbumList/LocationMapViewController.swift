//
//  LocationMapViewController.swift
//  Presentation
//
//  Created by sanghyeon on 9/7/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import MapKit
import SnapKit
import Combine
import Domain

final class LocationMapViewController: BaseViewController {

    private let naviView = NaviBarView()
    private let mapView = MKMapView()

    private let emptyLabel: UILabel = {
        let lb = UILabel()
        lb.text = String(localized: "표시할 위치 정보가 없어요", bundle: .module)
        lb.textColor = Theme.textTertiary
        lb.font = .systemFont(ofSize: 15, weight: .medium)
        lb.textAlignment = .center
        lb.isHidden = true
        return lb
    }()

    private let viewModel: LocationMapViewModel

    private var cancellables = Set<AnyCancellable>()
    private var hasDrawnInitialAnnotations = false

    override var pageTitle: String? { "장소" }

    init(viewModel: LocationMapViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError(Self.fatalMessage)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupView()
        self.binding()

        self.viewModel.send(.appear)
    }

    private func setupView() {
        naviView.setTitle(String(localized: "장소", bundle: .module))
        naviView.addButtons([LeftButton(type: .back)])

        mapView.delegate = self
        mapView.showsUserLocation = false
        mapView.register(PhotoMapAnnotationView.self, forAnnotationViewWithReuseIdentifier: PhotoMapAnnotationView.reuseId)

        self.view.addSubview(naviView)
        self.view.addSubview(mapView)
        self.view.addSubview(emptyLabel)

        naviView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }

        mapView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(naviView.snp.bottom)
        }

        emptyLabel.snp.makeConstraints { make in
            make.center.equalTo(mapView)
            make.leading.trailing.equalToSuperview().inset(40)
        }
    }

    private func binding() {
        naviView.publisher.sink { [weak self] type in
            guard let self, type == .back else { return }
            self.viewModel.send(.dismiss)
        }
        .store(in: &cancellables)

        viewModel.transform().clusters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clusters in
                self?.applyAnnotations(clusters)
            }
            .store(in: &cancellables)
    }

    /// 클러스터가 다시 계산될 때 — 옛 핀은 즉시 지우고 새 핀만 페이드인한다
    private func applyAnnotations(_ clusters: [PhotoMapCluster]) {
        emptyLabel.isHidden = !clusters.isEmpty

        let oldAnnotations = mapView.annotations.compactMap { $0 as? PhotoClusterAnnotation }

        guard hasDrawnInitialAnnotations else {
            // 최초 로드는 애니메이션 없이 — 카메라 위치/줌은 그대로 둔다
            mapView.addAnnotations(clusters.map { PhotoClusterAnnotation(cluster: $0) })
            hasDrawnInitialAnnotations = true
            return
        }

        mapView.removeAnnotations(oldAnnotations)

        guard !clusters.isEmpty else { return }

        let newAnnotations = clusters.map { PhotoClusterAnnotation(cluster: $0) }
        mapView.addAnnotations(newAnnotations)
        for annotation in newAnnotations {
            guard let view = mapView.view(for: annotation) else { continue }
            view.alpha = 0
            UIView.animate(withDuration: 0.25) { view.alpha = 1 }
        }
    }
}

extension LocationMapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let clusterAnnotation = annotation as? PhotoClusterAnnotation else { return nil }
        let view = mapView.dequeueReusableAnnotationView(
            withIdentifier: PhotoMapAnnotationView.reuseId,
            for: annotation
        ) as? PhotoMapAnnotationView
        view?.configure(cluster: clusterAnnotation.cluster) { [weak self] id, size in
            await self?.viewModel.loadImage(id: id, size: size) ?? nil
        }
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation as? PhotoClusterAnnotation else { return }
        mapView.deselectAnnotation(annotation, animated: true)
        viewModel.send(.selectCluster(id: annotation.cluster.id))
    }

    // 다시 클러스터링할지는 ViewModel이 정한다
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        let zoomLevel = log2(360.0 * Double(mapView.frame.width) / (256.0 * mapView.region.span.longitudeDelta))
        viewModel.send(.zoomLevelChanged(zoomLevel))
    }
}
