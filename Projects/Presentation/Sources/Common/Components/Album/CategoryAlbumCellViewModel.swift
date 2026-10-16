//
//  CategoryAlbumCellViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 5/30/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Domain

struct CategoryAlbumCellViewModel: AlbumCellViewModel {

    var id: UUID
    var localIdentifier: String
    var displayName: String
    var formattedDate: String
    var photoCount: Int

    var album: Album
    var imageLoader: any ImageLoadable

    let systemIconName: String
    let iconColor: UIColor

    init(album: Album, imageLoader: any ImageLoadable) {
        self.id = album.id
        self.localIdentifier = album.coverPhotoIdentifier ?? ""
        self.displayName = album.displayName.replacingOccurrences(of: "_", with: " ")
        self.formattedDate = ""
        self.photoCount = album.photoCount
        self.album = album
        self.imageLoader = imageLoader

        // album.name == 카테고리 key
        switch album.name {
        case "food":
            systemIconName = "lucide_utensils"
            iconColor = Theme.primary
        case "nature":
            systemIconName = "lucide_leaf"
            iconColor = Theme.positive
        case "city":
            systemIconName = "lucide_building_2"
            iconColor = Theme.secondary
        case "event":
            systemIconName = "lucide_star"
            iconColor = Theme.accent
        case "animal":
            systemIconName = "lucide_paw_print"
            iconColor = UIColor("#A0784E")
        case "text_document":
            systemIconName = "lucide_file_text"
            iconColor = Theme.textSecondary
        case "sports":
            systemIconName = "lucide_activity"
            iconColor = Theme.warning
        case "vehicle":
            systemIconName = "lucide_car"
            iconColor = UIColor("#6B7AFF")
        case "video":
            systemIconName = "lucide_video"
            iconColor = UIColor("#3A3A3C")
        default:
            systemIconName = "lucide_image"
            iconColor = Theme.textTertiary
        }
    }
}
