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

    /// 줌 단계가 바뀌어 클러스터가 재계산될 때마다 불린다. 예전엔 옛 핀에서 새 핀이 갈라져 나오거나
    /// 여러 핀이 하나로 모이는 좌표 애니메이션을 시도했었는데, "geo_" 폴백 키(아직 역지오코딩 안 된
    /// 사진)는 계층 구조에 안 걸리고, 한 화면에서 분할/병합이 동시에 섞여 일어나는 경우도 많아서
    /// 부모/자식 매칭이 자주 틀렸다 — 그 결과가 핀이 중구난방으로 움직이는 것처럼 보였다. 대신
    /// 옛 핀은 즉시 제거, 새 핀은 투명하게 추가한 뒤 페이드인하는 단순한 방식으로 정리한다.
    ///
    /// 옛 핀도 페이드아웃하는 버전을 처음 시도했었는데, `PhotoMapAnnotationView`가 재사용
    /// 식별자를 쓰는 탓에 빠르게 줌을 여러 번 바꾸면 "사라지는" 애니메이션이 끝나기 전에 그
    /// 뷰 인스턴스가 새 핀 용도로 재활용돼서, 뒤늦게 끝나는 옛 애니메이션이 방금 나타난 새
    /// 핀의 alpha를 도로 0으로 떨어뜨려버리는 버그가 있었다(줌 여러 번 하면 핀이 다 사라지는
    /// 증상). 제거는 애니메이션 없이 즉시 해서 이 경합 자체를 없앤다 — 페이드인만 남아도
    /// 같은 뷰가 재활용되면서 겹쳐도 최종값이 항상 alpha 1로 수렴해서 안전하다.
    private func applyAnnotations(_ clusters: [PhotoMapCluster]) {
        emptyLabel.isHidden = !clusters.isEmpty

        let oldAnnotations = mapView.annotations.compactMap { $0 as? PhotoClusterAnnotation }

        guard hasDrawnInitialAnnotations else {
            // 최초 로드 — 애니메이션 없이 바로 그린다. 카메라는 건드리지 않는다(핀 위치에 맞춰
            // 자동으로 이동/줌시키면 지도가 열리는 시점의 위치/줌이 그대로 안 유지된다는 요청이 있었음)
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

    // 팬/줌이 끝날 때마다 현재 줌 레벨을 계산해서 넘겨준다 — 실제 재클러스터링 여부(tier 변경
    // 여부)는 ViewModel이 판단한다
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        let zoomLevel = log2(360.0 * Double(mapView.frame.width) / (256.0 * mapView.region.span.longitudeDelta))
        viewModel.send(.zoomLevelChanged(zoomLevel))
    }
}
