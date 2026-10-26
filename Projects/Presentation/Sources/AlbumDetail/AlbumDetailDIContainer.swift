//
//  AlbumDetailDIContainer.swift
//  Presentation
//
//  Created by sanghyeon on 3/28/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Domain

@MainActor
public final class AlbumDetailDIContainer {

    private let photoLibraryRepository: PhotoLibraryRepository
    private let albumDataRepository: AlbumDataRepository
    private let labelRepository: PhotoLabelDataRepository
    private let faceClusterRepository: FaceClusterRepository
    private let animalClusterRepository: AnimalClusterRepository
    private let photoDataRepository: PhotoDataRepository
    private let travelRepository: TravelDetectionRepository

    private let album: Album
    private let isSelectMode: Bool

    public init(album: Album,
                photoLibraryRepository: PhotoLibraryRepository,
                albumDataRepository: AlbumDataRepository,
                labelRepository: PhotoLabelDataRepository,
                faceClusterRepository: FaceClusterRepository,
                animalClusterRepository: AnimalClusterRepository,
                photoDataRepository: PhotoDataRepository,
                travelRepository: TravelDetectionRepository,
                isSelectMode: Bool) {
        self.album = album
        self.photoLibraryRepository = photoLibraryRepository
        self.albumDataRepository = albumDataRepository
        self.labelRepository = labelRepository
        self.faceClusterRepository = faceClusterRepository
        self.animalClusterRepository = animalClusterRepository
        self.photoDataRepository = photoDataRepository
        self.travelRepository = travelRepository
        self.isSelectMode = isSelectMode
    }

    func makeAlbumDetailViewModel() -> AlbumDetailViewModel {

        let imageUseCase = DefaultPhotoImageUseCase(
            repository: photoLibraryRepository
        )

        return AlbumDetailViewModel(source: .album(album),
                                    imageUseCase: imageUseCase,
                                    detailUseCase: makeAlbumDetailUseCase(),
                                    startInSelectionMode: isSelectMode)
    }

    /// 여행 앨범 "분류순" 보기의 더보기 — 실제 앨범이 아니라 (여행 사진) ∩ (사람/카테고리 앨범 사진)
    /// 교집합만 보여주는 화면용. sourceAlbumId는 삭제/제외가 실제로 반영될 진짜 여행 앨범을 가리킨다.
    func makeAlbumDetailViewModel(filteredTitle: String, photos: [Photo], sourceAlbumId: UUID) -> AlbumDetailViewModel {
        let imageUseCase = DefaultPhotoImageUseCase(
            repository: photoLibraryRepository
        )

        return AlbumDetailViewModel(source: .filtered(title: filteredTitle, photos: photos, sourceAlbumId: sourceAlbumId),
                                    imageUseCase: imageUseCase,
                                    detailUseCase: makeAlbumDetailUseCase())
    }

    func makeImageUseCase() -> PhotoImageUseCase {
        DefaultPhotoImageUseCase(repository: photoLibraryRepository)
    }

    func makeAlbumUseCase() -> AlbumUseCase {
        DefaultAlbumUseCase(
            albumRepository: albumDataRepository,
            faceClusterRepository: faceClusterRepository,
            animalClusterRepository: animalClusterRepository
        )
    }

    func makeAlbumDetailUseCase() -> AlbumDetailUseCase {
        DefaultAlbumDetailUseCase(
            repository: albumDataRepository,
            libraryRepository: photoLibraryRepository,
            faceClusterRepository: faceClusterRepository,
            animalClusterRepository: animalClusterRepository,
            photoDataRepository: photoDataRepository,
            travelRepository: travelRepository
        )
    }

    func makeImageViewerViewModel(photoDetails: [PhotoDetail], index: Int,
                                  isSelectionMode: Bool = false,
                                  selectedIdentifiers: Set<String> = []) -> ImageViewerViewModel {

        let imageUseCase = DefaultImageViewerUseCase(
            repository: photoLibraryRepository,
            labelRepository: labelRepository
        )

        return ImageViewerViewModel(photoDetails: photoDetails,
                                    initialIndex: index,
                                    imageUseCase: imageUseCase,
                                    isSelectionMode: isSelectionMode,
                                    selectedIdentifiers: selectedIdentifiers)
    }
}
