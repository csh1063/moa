//
//  AlbumRepositoryError.swift
//  Domain
//
//  Created by sanghyeon on 3/21/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

public enum AlbumRepositoryError: Error {
    case albumNotFound
    case photoNotFound
    /// 영상은 대표 사진으로 선택할 수 없음
    case coverPhotoCannotBeVideo
}
