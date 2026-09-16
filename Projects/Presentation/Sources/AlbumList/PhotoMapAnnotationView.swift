//
//  PhotoMapAnnotationView.swift
//  Presentation
//
//  Created by sanghyeon on 9/8/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import MapKit
import Domain

/// 주소 기준으로 미리 묶인 사진 그룹(PhotoMapCluster) 하나 = 지도 위 핀 하나.
/// MapKit의 실시간 화면거리 클러스터링은 안 쓴다 — 묶는 기준 자체가 주소라서 줌 레벨과 무관하게
/// 고정이고, 그래서 핀 개수도(원본 사진 개수가 아니라 주소 그룹 개수만큼만) 훨씬 적다.
final class PhotoClusterAnnotation: NSObject, MKAnnotation {
    let cluster: PhotoMapCluster
    let coordinate: CLLocationCoordinate2D

    init(cluster: PhotoMapCluster) {
        self.cluster = cluster
        self.coordinate = CLLocationCoordinate2D(latitude: cluster.latitude, longitude: cluster.longitude)
        super.init()
    }
}

final class PhotoMapAnnotationView: MKAnnotationView {

    static let reuseId = "PhotoMapAnnotationView"

    private let avatarContainer = UIView()
    private let imageView = UIImageView()
    private let countBadge = UILabel()

    private var task: Task<Void, Never>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("PhotoMapAnnotationView does not support NSCoding")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        imageView.image = nil
    }

    private func setupView() {
        canShowCallout = false

        avatarContainer.layer.masksToBounds = true
        avatarContainer.layer.borderWidth = 2
        avatarContainer.layer.borderColor = UIColor.white.cgColor
        avatarContainer.backgroundColor = Theme.strokeSoft
        addSubview(avatarContainer)
        avatarContainer.addShadow(color: .black, opacity: 0.2, offset: CGSize(width: 0, height: 1), radius: 3)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        avatarContainer.addSubview(imageView)

        countBadge.backgroundColor = Theme.primary
        countBadge.textColor = .white
        countBadge.font = .systemFont(ofSize: 10, weight: .bold)
        countBadge.textAlignment = .center
        countBadge.layer.cornerRadius = 8
        countBadge.layer.masksToBounds = true
        countBadge.layer.borderWidth = 1.5
        countBadge.layer.borderColor = UIColor.white.cgColor
        countBadge.isHidden = true
        addSubview(countBadge)
    }

    func configure(cluster: PhotoMapCluster, imageLoader: @escaping (String, CGSize) async -> UIImage?) {
        task?.cancel()
        imageView.image = nil

        let count = cluster.photos.count
        let size: CGFloat = count > 1 ? 52 : 40

        countBadge.isHidden = count <= 1
        countBadge.text = "\(count)"

        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = CGPoint(x: 0, y: -size / 2)
        avatarContainer.frame = bounds
        avatarContainer.layer.cornerRadius = size / 2
        imageView.frame = avatarContainer.bounds
        countBadge.frame = CGRect(x: size - 20, y: size - 14, width: 24, height: 16)

        guard let thumbnailId = cluster.photos.first?.localIdentifier else { return }
        task = Task { [weak self] in
            let image = await imageLoader(thumbnailId, CGSize(width: size * 2, height: size * 2))
            guard !Task.isCancelled else { return }
            self?.imageView.image = image
        }
    }
}
