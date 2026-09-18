//
//  AlbumListDIContainer.swift
//  Presentation
//
//  Created by sanghyeon on 6/19/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import Domain

@MainActor
public final class AlbumListDIContainer {

    private let photoLibraryRepository: PhotoLibraryRepository
    private let albumDataRepository: AlbumDataRepository
    private let photoLabelDataRepository: PhotoLabelDataRepository
    private let faceClusterRepository: FaceClusterRepository
    private let animalClusterRepository: AnimalClusterRepository
    private let photoDataRepository: PhotoDataRepository
    private let travelRepository: TravelDetectionRepository

    private let from: String

    public init(from: String,
                photoLibraryRepository: PhotoLibraryRepository,
                albumDataRepository: AlbumDataRepository,
                photoLabelDataRepository: PhotoLabelDataRepository,
                faceClusterRepository: FaceClusterRepository,
                animalClusterRepository: AnimalClusterRepository,
                photoDataRepository: PhotoDataRepository,
                travelRepository: TravelDetectionRepository) {
        self.from = from
        self.photoLibraryRepository = photoLibraryRepository
        self.albumDataRepository = albumDataRepository
        self.photoLabelDataRepository = photoLabelDataRepository
        self.faceClusterRepository = faceClusterRepository
        self.animalClusterRepository = animalClusterRepository
        self.photoDataRepository = photoDataRepository
        self.travelRepository = travelRepository
    }

    func makeAlbumListViewModel() -> AlbumListViewModel {

        let imageUseCase = DefaultPhotoImageUseCase(
            repository: photoLibraryRepository
        )

        let albumUseCase = DefaultAlbumUseCase(
            albumRepository: albumDataRepository,
            faceClusterRepository: faceClusterRepository,
            animalClusterRepository: animalClusterRepository
        )

        return AlbumListViewModel(from: from,
                                  imageUseCase: imageUseCase,
                                  albumUseCase: albumUseCase)
    }

    func makeLocationMapViewModel() -> LocationMapViewModel {

        let imageUseCase = DefaultPhotoImageUseCase(
            repository: photoLibraryRepository
        )

        let photoMapUseCase = DefaultPhotoMapUseCase(
            photoDataRepository: photoDataRepository
        )

        return LocationMapViewModel(photoMapUseCase: photoMapUseCase, imageUseCase: imageUseCase)
    }

    func makeImageViewerViewModel(photoDetails: [PhotoDetail], index: Int) -> ImageViewerViewModel {

        let imageUseCase = DefaultImageViewerUseCase(
            repository: photoLibraryRepository,
            labelRepository: photoLabelDataRepository
        )

        return ImageViewerViewModel(photoDetails: photoDetails,
                                    initialIndex: index,
                                    imageUseCase: imageUseCase)
    }

    func makeLibraryAlbumImportUseCase() -> LibraryAlbumImportUseCase {
        DefaultLibraryAlbumImportUseCase(
            photoLibraryRepository: photoLibraryRepository,
            photoDataRepository: photoDataRepository,
            albumDataRepository: albumDataRepository
        )
    }

    func makeDetailDIContainer(album: Album, isSelectMode: Bool) -> AlbumDetailDIContainer {
        AlbumDetailDIContainer(
            album: album,
            photoLibraryRepository: photoLibraryRepository,
            albumDataRepository: albumDataRepository,
            labelRepository: photoLabelDataRepository,
            faceClusterRepository: faceClusterRepository,
            animalClusterRepository: animalClusterRepository,
            photoDataRepository: photoDataRepository,
            travelRepository: travelRepository,
            isSelectMode: isSelectMode
        )
    }
}
