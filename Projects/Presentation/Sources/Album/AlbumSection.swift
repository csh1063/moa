//
//  AlbumSection.swift
//  Presentation
//
//  Created by sanghyeon on 5/30/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Domain

enum AlbumSection: Int, CaseIterable {
    case travel
    case face
    case library
    case category
    case location
    case date
    case similar

    var title: String {
        switch self {
        case .date:     return String(localized: "시간", bundle: .module)
        case .travel:     return String(localized: "여행", bundle: .module)
        case .location:  return String(localized: "장소", bundle: .module)
        case .category: return String(localized: "분류", bundle: .module)
        case .face:     return String(localized: "인물", bundle: .module)
        case .similar: return String(localized: "중복", bundle: .module)
        case .library: return String(localized: "가져온 앨범", bundle: .module)
        }
    }

    var type: String {
        switch self {
        case .date:     return "date"
        case .travel:     return "travel"
        case .location:  return "location"
        case .category: return "category"
        case .face:     return "face"
        case .similar: return "similar"
        case .library: return "library"
        }
    }

    /// 홈 "인물" 섹션에 같이 보이는 from 값 — 동작은 여전히 face/animal로 나뉜다
    static let faceSectionFromValues: Set<String> = ["face", "animal"]
}

enum AlbumType: Hashable {
    case date(DateAlbumCellViewModel)
    case travel(TravelAlbumCellViewModel)
    case location(LocationAlbumCellViewModel)
    case category(CategoryAlbumCellViewModel)
    case face(FaceAlbumCellViewModel)
    case animal(AnimalAlbumCellViewModel)
    case similar(SimilarAlbumCellViewModel)

    var album: Album {
        switch self {
        case .date(let vm):     return vm.album
        case .travel(let vm):   return vm.album
        case .location(let vm): return vm.album
        case .category(let vm): return vm.album
        case .face(let vm):     return vm.album
        case .animal(let vm):   return vm.album
        case .similar(let vm):  return vm.album
        }
    }
}
