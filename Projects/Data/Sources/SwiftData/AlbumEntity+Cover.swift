//
//  AlbumEntity+Cover.swift
//  Data
//
//  Created by sanghyeon on 10/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation

/// 대표사진 규칙 — 모든 경로(사진 추가/삭제/제외, 클러스터링, 합치기/분리, 스플래시 동기화)가 이것만 쓴다.
/// 1) 사용자가 직접 고른 사진이 앨범에 남아 있으면 유지
/// 2) 인물/동물 앨범은 얼굴(동물) 화질이 가장 좋은 사진
/// 3) 그 외는 가장 최신 사진 — 영상이어도 된다(첫 프레임 썸네일로 표시됨)
extension AlbumEntity {

    /// 사진 구성이 늘거나 클러스터가 바뀐 뒤 호출 — 직접 고른 게 없으면 규칙대로 다시 고른다
    func refreshCover() {
        if coverPhotoManuallySet, containsPhoto(coverPhotoIdentifier) { return }
        coverPhotoManuallySet = false
        coverPhotoIdentifier = autoCoverIdentifier()
    }

    /// 사진이 빠지거나 합쳐진 뒤 호출 — 지금 대표사진이 앨범에 남아 있으면(합칠 때 기준 앨범의 대표 포함) 그대로 둔다
    func repairCoverIfMissing() {
        if containsPhoto(coverPhotoIdentifier) { return }
        coverPhotoManuallySet = false
        coverPhotoIdentifier = autoCoverIdentifier()
    }

    private func containsPhoto(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return photos.contains { $0.localIdentifier == identifier }
    }

    private func autoCoverIdentifier() -> String? {
        let photoIds = Set(photos.map { $0.localIdentifier })
        func inAlbum(_ photo: PhotoEntity?) -> Bool { photo.map { photoIds.contains($0.localIdentifier) } ?? false }

        switch from {
        case "face":
            if let best = clusters.flatMap({ $0.faceEmbeddings }).filter({ inAlbum($0.photo) })
                .max(by: { $0.captureQuality < $1.captureQuality }) {
                return best.photo?.localIdentifier
            }
        case "animal":
            if let best = animalClusters.flatMap({ $0.animalEmbeddings }).filter({ inAlbum($0.photo) })
                .max(by: { $0.detectionConfidence < $1.detectionConfidence }) {
                return best.photo?.localIdentifier
            }
        default:
            break
        }
        return photos.max(by: { $0.createdAt < $1.createdAt })?.localIdentifier
    }
}
