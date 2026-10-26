//
//  AlbumDetailViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 3/26/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Combine
import Domain

enum AlbumDetailViewModelAction {
    case options(album: Album)
    /// "분류순" 더보기로 들어간 화면(실제 앨범 아님)의 "..." 메뉴 — 공유 한 줄짜리 미니 시트
    case optionsFiltered(photos: [Photo])
    case pop
    case selectPhoto(_ photoDetails: [PhotoDetail], index: Int, inSelectionMode: Bool)
    case pickMergeTarget(candidates: [AlbumMergeCandidate], isTravel: Bool, currentAlbum: Album)
    case pickSplitClusters(clusters: [FaceClusterSummary])
    case pickTravelerManagement(travelers: [Album], others: [Album])
    /// 대표 사진 후보를 골랐을 때 — 실제 적용 전에 미리보기 화면을 띄워달라는 요청
    case previewCover(album: Album, candidateId: String)
    /// 여행 앨범 "분류순"의 한 줄(사람/자연/음식/공간) "더보기" — 교집합 사진만 보는 화면으로 이동
    case showFiltered(title: String, photos: [Photo], sourceAlbumId: UUID)
    /// 공유 시트까지 실제로 띄워달라는 요청 (전체 공유 / 선택한 것만 공유 공통)
    case share(photos: [Photo])
}

@MainActor
protocol AlbumDetailViewModelDelegate: AnyObject {
    func save(name: String)
    func deleteAlert()
    func changeMode(_ mode: AlbumDetailPageMode)
    func mergeTapped()
    func mergeInto(albumIds: [UUID])
    func splitTapped()
    func splitInto(clusterIds: [UUID])
    func travelerManagementTapped()
    func saveTravelerManagement(travelerIds: [UUID])
    func refreshAfterPhotosAdded()
    /// 대표 사진 미리보기 화면에서 "선택"을 확정했을 때만 실제로 저장
    func setCover(id: String)
    /// 더보기 옵션시트의 "전체 공유" — 실제 앨범 화면 쪽(옵션시트가 album만 들고 있어 살아있는
    /// photos 목록에 접근 못 하므로 델리게이트를 거쳐 ViewModel이 들고 있는 값을 쓴다)
    func shareAllTapped()
}

/// 여행 앨범 상세 화면의 데이터 소스 — 실제 앨범이거나, "분류순" 더보기로 만들어진
/// (여행 사진) ∩ (사람/카테고리 앨범 사진) 교집합만 보여주는 가짜(비영속) 화면이거나
public enum AlbumDetailSource {
    case album(Album)
    /// sourceAlbumId는 이 필터링의 바탕이 된 진짜 여행 앨범 id — 삭제/제외가 거기에 그대로 반영되게 한다
    case filtered(title: String, photos: [Photo], sourceAlbumId: UUID)
}

@MainActor
public final class AlbumDetailViewModel: BaseViewModel {

    enum Input {
        case appear
        case refresh
        case more
        case dismiss
        case selectItem(id: String, inSelectionMode: Bool)
        case deleteSelected(ids: [String])
        case excludeSelected(ids: [String])
        /// 대표 사진 고르기 모드에서 사진을 탭했을 때 — 바로 적용하지 않고 미리보기부터 요청
        case selectCoverCandidate(id: String)
        /// 대표 사진 고르기 모드에서 영상을 탭했을 때 — 선택 불가 안내
        case tappedVideoAsCoverCandidate
        /// 여행 앨범 날짜순/분류순 토글
        case switchTab(DisplayTab)
        /// 분류순 한 줄의 "더보기"
        case tapMore(sectionId: UUID)
        /// 분류순에서 "선택"을 눌렀을 때 — 팝업 없이 날짜순으로 돌려놓기만 한다(선택 모드 진입 자체는 VC가 바로 이어서 처리)
        case enterSelectModeFromCategoryTab
        /// 더보기 옵션시트의 "전체 공유"
        case shareAll
        /// 선택모드 하단바의 "공유"
        case shareSelected(ids: [String])
    }

    enum DisplayTab: Equatable {
        case date
        case category
    }

    /// 분류순 한 줄(동행자 1명 또는 자연/음식/공간) — id는 그 사람/카테고리 앨범의 실제 id(더보기 매칭용)
    struct AlbumDetailCategorySection: Identifiable {
        let id: UUID
        let title: String
        let photos: [Photo]
    }

    public struct Output {
        let name: AnyPublisher<String, Never>
        let photos: AnyPublisher<[Photo], Never>
        let isLoading: AnyPublisher<Bool, Never>
        let errorMessage: AnyPublisher<String?, Never>
        let selectionMode: AnyPublisher<AlbumDetailPageMode, Never>
        let travelerInfo: AnyPublisher<TravelerInfo?, Never>
        let coverPhotoIdentifier: AnyPublisher<String?, Never>
        let displayTab: AnyPublisher<DisplayTab, Never>
        let categorySections: AnyPublisher<[AlbumDetailCategorySection], Never>
    }

    /// 여행 헤더에 "이름 문구"와 "인원 수"를 분리해서 보여주기 위한 값
    struct TravelerInfo {
        let name: String
        let count: Int
    }

    /// 실제 앨범일 때만 값이 있음 — "분류순" 더보기로 들어온 필터드 화면은 nil (실존 앨범이 아님)
    @Published private var album: Album?
    @Published private var albumName: String
    @Published private var photos: [Photo] = []
    @Published private var errorMessage: String?
    @Published private var selectionMode: AlbumDetailPageMode = .list
    @Published private var travelerInfo: TravelerInfo?
    @Published private var currentCoverId: String?
    @Published private var displayTab: DisplayTab = .date
    @Published private var categorySections: [AlbumDetailCategorySection] = []

    /// 필터드 소스일 때 미리 계산되어 들어온 사진 목록 — loadPhotos()가 재조회 대신 이걸 그대로 씀
    private let presetPhotos: [Photo]?
    /// 필터드 소스일 때, 삭제/제외가 실제로 반영될 진짜 여행 앨범 id
    private let filteredSourceAlbumId: UUID?
    private var effectiveAlbumId: UUID? { album?.id ?? filteredSourceAlbumId }

    var onAction: ((AlbumDetailViewModelAction) -> Void)?

    private let input = PassthroughSubject<Input, Never>()
    private(set) var photoDetails: [PhotoDetail] = []

    private let imageUseCase: PhotoImageUseCase
    private let detailUseCase: AlbumDetailUseCase
    private var cancellables = Set<AnyCancellable>()

    /// 얼굴 앨범 디버깅용: 사진 id별 이 앨범에 묶이게 한 얼굴의 boundingBox
    private var faceBoundingBoxes: [String: CGRect] = [:]
    var isFaceAlbum: Bool { album?.from == "face" }
    var isAnimalAlbum: Bool { album?.from == "animal" }
    var isTravelAlbum: Bool { album?.from == "travel" }
    /// AutoAlbumUseCase의 앨범 명명 기준과 동일하게, 당일치기면 "나들이" 아니면 "여행"
    private var tripSuffix: String {
        guard let album, let start = album.startDate, let end = album.endDate,
              Calendar.current.isDate(start, inSameDayAs: end) else {
            return String(localized: "여행", bundle: .module)
        }
        return String(localized: "나들이", bundle: .module)
    }

    public init(source: AlbumDetailSource,
                imageUseCase: PhotoImageUseCase,
                detailUseCase: AlbumDetailUseCase,
                startInSelectionMode: Bool = false) {
        switch source {
        case .album(let album):
            self.album = album
            // 얼굴 앨범은 자동 생성된 이름("인물 3")을 상단 타이틀에 그대로 보여주지 않고,
            // 사용자가 실제로 이름을 지어준 경우에만("isRenamed") 그 이름을 보여준다.
            // 빈 문자열("")을 쓰면 NaviBarView의 스택뷰가 .fillProportionally라 titleLabel의
            // intrinsic width가 0에 가까워지면서 옆 버튼들이 비율을 이상하게 나눠 갖는 버그가 있어서,
            // 공백 한 칸으로 "보이기엔 비어있지만 폭은 0이 아닌" 상태를 만든다 (NaviBarView 자체는 안 건드림)
            self.albumName = Self.computedAlbumName(for: album)
            self.currentCoverId = album.coverPhotoIdentifier
            self.presetPhotos = nil
            self.filteredSourceAlbumId = nil
        case .filtered(let title, let photos, let sourceAlbumId):
            self.album = nil
            self.albumName = title
            self.currentCoverId = nil
            self.presetPhotos = photos
            self.filteredSourceAlbumId = sourceAlbumId
        }
        self.imageUseCase = imageUseCase
        self.detailUseCase = detailUseCase
        self.selectionMode = startInSelectionMode ? .onlySelect : .list
        super.init()
        bind()
    }

    private static func computedAlbumName(for album: Album) -> String {
        ((album.from == "face" || album.from == "animal") && !album.isRenamed) ? " " : album.displayName
    }

    public func transform() -> Output {
        Output(
            name: $albumName.eraseToAnyPublisher(),
            photos: $photos.eraseToAnyPublisher(),
            isLoading: $isLoading.eraseToAnyPublisher(),
            errorMessage: $errorMessage.eraseToAnyPublisher(),
            selectionMode: $selectionMode.eraseToAnyPublisher(),
            travelerInfo: $travelerInfo.eraseToAnyPublisher(),
            coverPhotoIdentifier: $currentCoverId.eraseToAnyPublisher(),
            displayTab: $displayTab.eraseToAnyPublisher(),
            categorySections: $categorySections.eraseToAnyPublisher()
        )
    }

    func send(_ input: Input) {
        self.input.send(input)
    }

    func loadImage(id: String, size: CGSize) async -> UIImage? {
        do {
            guard let cgImage: CGImage = try await imageUseCase.loadImage(id: id, type: .specialSize(size)).cgImage else { return nil }
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    func loadImageProgressive(id: String, size: CGSize, onImage: @escaping (UIImage?, Bool) -> Void) {
        Task {
            await imageUseCase.loadImageProgressive(id: id, size: size) { (data: ImageData<CGImage>, isFinal) in
                let image = data.cgImage.map { UIImage(cgImage: $0) }
                Task { @MainActor in onImage(image, isFinal) }
            }
        }
    }

    /// 얼굴 앨범 디버깅용: 전체 사진이 아니라 이 앨범에 묶이게 한 얼굴 부분만 크롭해서 반환
    func loadFaceImage(id: String, size: CGSize) async -> UIImage? {
        guard let boundingBox = faceBoundingBoxes[id] else {
            return await loadImage(id: id, size: size)
        }
        do {
            guard let cgImage: CGImage = try await imageUseCase.loadImage(id: id, type: .specialSize(size)).cgImage,
                  let cropped = crop(cgImage, to: boundingBox) else { return nil }
            return UIImage(cgImage: cropped)
        } catch {
            return nil
        }
    }

    /// boundingBox는 Vision 정규화 좌표(원점 좌하단, 0~1) 기준
    private func crop(_ image: CGImage, to boundingBox: CGRect) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        let scale: CGFloat = 1.1
        let expandedWidth = boundingBox.width * scale
        let expandedHeight = boundingBox.height * scale
        let expandedX = boundingBox.minX - (expandedWidth - boundingBox.width) / 2
        let expandedY = boundingBox.minY - (expandedHeight - boundingBox.height) / 2

        let clampedX = max(0, expandedX)
        let clampedY = max(0, expandedY)
        let clampedWidth = min(expandedWidth, 1.0 - clampedX)
        let clampedHeight = min(expandedHeight, 1.0 - clampedY)

        let rect = CGRect(
            x: clampedX * width,
            y: (1.0 - clampedY - clampedHeight) * height,
            width: clampedWidth * width,
            height: clampedHeight * height
        )
        return image.cropping(to: rect)
    }

    private func bind() {
        input.sink { [weak self] input in
            guard let self else { return }
            Task { @MainActor in await self.handle(input) }
        }
        .store(in: &cancellables)
    }

    private func handle(_ input: Input) async {
        switch input {
        case .appear, .refresh:
            await loadPhotos()

        case .more:
            if let album {
                onAction?(.options(album: album))
            } else {
                onAction?(.optionsFiltered(photos: photos))
            }

        case .dismiss:
            onAction?(.pop)

        case .switchTab(let tab):
            displayTab = tab

        case .tapMore(let sectionId):
            guard let album, let section = categorySections.first(where: { $0.id == sectionId }) else { return }
            onAction?(.showFiltered(
                title: "\(section.title) · \(albumName)",
                photos: section.photos,
                sourceAlbumId: album.id
            ))

        case .enterSelectModeFromCategoryTab:
            displayTab = .date

        case .shareAll:
            onAction?(.share(photos: photos))

        case .shareSelected(let ids):
            let idSet = Set(ids)
            onAction?(.share(photos: photos.filter { idSet.contains($0.localIdentifier) }))

        case .selectItem(let id, let inSelectionMode):
            if let index = photoDetails.firstIndex(where: { $0.id == id }) {
                onAction?(.selectPhoto(photoDetails, index: index, inSelectionMode: inSelectionMode))
            }

        case .deleteSelected(let ids):
            // 취소할 수도 있는 선택지라, 동행자 영향 계산은 여기서 미리 안 하고 실제로 삭제
            // 버튼을 누른 뒤(confirmDelete)에만 한다 — 취소하면 그 계산 자체가 아예 필요 없어진다
            showAlert(
                title: String(localized: "사진 삭제", bundle: .module),
                message: String(localized: "선택한 사진을 삭제할까요?", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "이 앨범에서만 삭제", bundle: .module), style: .default) { [weak self] in
                        Task {
                            await self?.confirmDelete(ids: ids)
                        }
                    },
                    AlertButtonConfig(title: String(localized: "애플 사진 앱에서도 삭제", bundle: .module), style: .default) { [weak self] in
                        Task {
                            await self?.confirmDelete(ids: ids, deleteInLibrary: true)
                        }
                    },
                    AlertButtonConfig(title: String(localized: "취소", bundle: .module), style: .cancel, action: nil)
                ]
            )

        case .selectCoverCandidate(let id):
            guard let album else { return }
            onAction?(.previewCover(album: album, candidateId: id))

        case .tappedVideoAsCoverCandidate:
            showAlert(
                title: String(localized: "대표 사진으로 설정할 수 없어요", bundle: .module),
                message: String(localized: "영상은 대표 사진으로 선택할 수 없어요", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "확인", bundle: .module), style: .default, action: nil)
                ]
            )

        case .excludeSelected(let ids):
            showAlert(
                title: String(localized: "다른 사람 인가요?", bundle: .module),
                message: String(localized: "선택한 사진을 앨범에서 제외하고, 다시 묶이지 않게 할게요", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "취소", bundle: .module), style: .cancel, action: nil),
                    AlertButtonConfig(title: String(localized: "제외", bundle: .module), style: .destructive) { [weak self] in
                        Task { await self?.excludeSelected(ids: ids) }
                    }
                ]
            )
        }
    }

    private func loadPhotos() async {
        // 필터드 소스(분류순 더보기) — 실제 앨범이 아니라 미리 계산된 교집합을 그대로 퍼블리시만 한다
        if let presetPhotos {
            self.photos = presetPhotos
            self.photoDetails = presetPhotos.map {
                PhotoDetail(id: $0.localIdentifier, createdDate: $0.createdAt, photo: $0)
            }
            return
        }
        guard let album else { return }
        do {
            isLoading = true
            // 병합처럼 서버 쪽에서 기간/이름이 바뀔 수 있는 작업 후에도 이 화면이 들고 있는 album이
            // 그대로라 사진 추가 등에서 옛 기간을 기준으로 조회하는 문제가 있었다 — 매번 최신으로 갱신
            var currentAlbum = album
            if let refreshed = try await detailUseCase.fetchAlbum(id: album.id) {
                currentAlbum = refreshed
                self.album = refreshed
                albumName = Self.computedAlbumName(for: refreshed)
                currentCoverId = refreshed.coverPhotoIdentifier
            }
            let photos = try await detailUseCase.fetchPhotos(by: currentAlbum.id)
            // photos를 publish하면 셀이 바로 loadFaceImage를 호출하므로,
            // faceBoundingBoxes는 그보다 먼저 채워둬야 첫 진입에서도 크롭이 뜬다
            if isFaceAlbum {
                faceBoundingBoxes = try await detailUseCase.fetchFaceBoundingBoxes(clusterId: currentAlbum.name)
            }
            if isTravelAlbum {
                let linkedFaceAlbums = try await detailUseCase.fetchLinkedFaceAlbums(albumId: currentAlbum.id)
                let linkedAnimalAlbums = try await detailUseCase.fetchLinkedAnimalAlbums(albumId: currentAlbum.id)
                let companions = linkedFaceAlbums + linkedAnimalAlbums
                travelerInfo = formatTravelerInfo(companions)
                let sections = await loadCategorySections(tripPhotos: photos, companions: companions)
                categorySections = sections

                // 분류순 탭을 한 번도 안 열어도, 이 여행에 사진이 하나도 안 남은 동행자가 있으면
                // (다른 화면에서 "애플 사진 앱에서도 삭제"로 지워진 경우 등) 열 때마다 알려준다
                let sectionIds = Set(sections.map(\.id))
                let emptiedCompanions = companions.filter { !sectionIds.contains($0.id) }
                if !emptiedCompanions.isEmpty {
                    promptDisconnect(emptiedCompanions: emptiedCompanions, albumId: currentAlbum.id, allLinkedIds: companions.map(\.id))
                }
            }
            self.photos = photos
            self.photoDetails = photos.map {
                PhotoDetail(id: $0.localIdentifier, createdDate: $0.createdAt, photo: $0)
            }
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    /// "분류순" 보기용 — 동행자별 줄 + 자연/음식/공간 줄을, 이 여행 사진과의 교집합으로 계산.
    /// 0장인 줄은 결과에서 아예 빼서 호출부(UI)가 따로 필터링할 필요 없게 한다
    private func loadCategorySections(tripPhotos: [Photo], companions: [Album]) async -> [AlbumDetailCategorySection] {
        var sections: [AlbumDetailCategorySection] = []

        for companion in companions {
            guard let companionPhotos = try? await detailUseCase.fetchPhotos(by: companion.id) else { continue }
            let companionIds = Set(companionPhotos.map(\.localIdentifier))
            let matched = tripPhotos.filter { companionIds.contains($0.localIdentifier) }
            guard !matched.isEmpty else { continue }
            sections.append(AlbumDetailCategorySection(id: companion.id, title: companionDisplayName(companion), photos: matched))
        }

        // PhotoCategoriesRule.json의 키 그대로 — 카테고리 앨범 displayName은 로케일과 무관하게
        // 항상 이 한글 문자열이라(다른 카테고리 UI도 전부 그대로 노출), 매칭 키도 로컬라이즈하지 않는다
        let categoryNames = ["자연", "음식", "공간"]
        if let categoryAlbums = try? await detailUseCase.fetchAll(from: "category") {
            for name in categoryNames {
                guard let categoryAlbum = categoryAlbums.first(where: { $0.displayName == name }),
                      let categoryPhotos = try? await detailUseCase.fetchPhotos(by: categoryAlbum.id) else { continue }
                let categoryIds = Set(categoryPhotos.map(\.localIdentifier))
                let matched = tripPhotos.filter { categoryIds.contains($0.localIdentifier) }
                guard !matched.isEmpty else { continue }
                sections.append(AlbumDetailCategorySection(id: categoryAlbum.id, title: name, photos: matched))
            }
        }

        return sections
    }

    /// 이름 지어준 적 없으면 사람은 "사람", 동물은 "반려동물"로 — 동행자 표시 전반(헤더/분류순 줄/알럿)에서 공통으로 쓴다
    private func companionDisplayName(_ companion: Album) -> String {
        guard !companion.isRenamed else { return companion.displayName }
        let base = companion.from == "animal" ? String(localized: "반려동물", bundle: .module) : String(localized: "사람", bundle: .module)
        // 자동 생성된 이름이 "인물 3"/"반려동물 1"처럼 끝에 번호가 붙어있다 — 이름 안 지어준 동행자가
        // 여럿이면 전부 "사람"으로만 뜨면 구분이 안 되니, 그 번호만 뽑아서 같이 보여준다
        if let lastSpace = companion.name.lastIndex(of: " "),
           let number = Int(companion.name[companion.name.index(after: lastSpace)...]) {
            return "\(base) \(number)"
        }
        return base
    }

    /// 첫 번째 삭제 확인(.deleteSelected)에서 "삭제" 계열 버튼을 눌렀을 때만 호출 — 여기서야 비로소
    /// 동행자 영향을 계산한다. 영향이 있으면 한 번 더 확인받고, 없으면 바로 지운다
    private func confirmDelete(ids: [String], deleteInLibrary: Bool = false) async {
        guard let warning = await emptiedCompanionWarning(idsToDelete: ids) else {
            await deleteSelected(ids: ids, deleteInLibrary: deleteInLibrary)
            return
        }
        showAlert(
            title: String(localized: "동행자 연결 확인", bundle: .module),
            message: warning,
            buttons: [
                AlertButtonConfig(title: String(localized: "취소", bundle: .module), style: .cancel, action: nil),
                AlertButtonConfig(title: String(localized: "삭제", bundle: .module), style: .destructive) { [weak self] in
                    Task { await self?.deleteSelected(ids: ids, deleteInLibrary: deleteInLibrary) }
                }
            ]
        )
    }

    /// 필터드(분류순 더보기) 화면이 아니면 항상 nil — 이 삭제로 이 여행에서 사진이 0장이 되는
    /// 동행자가 있을 때만 경고 문구를 만들어 반환한다
    private func emptiedCompanionWarning(idsToDelete: [String]) async -> String? {
        guard let sourceAlbumId = filteredSourceAlbumId,
              let tripPhotos = try? await detailUseCase.fetchPhotos(by: sourceAlbumId) else { return nil }

        let tripIds = Set(tripPhotos.map(\.localIdentifier))
        let remainingTripIds = tripIds.subtracting(idsToDelete)

        let faceAlbums = (try? await detailUseCase.fetchLinkedFaceAlbums(albumId: sourceAlbumId)) ?? []
        let animalAlbums = (try? await detailUseCase.fetchLinkedAnimalAlbums(albumId: sourceAlbumId)) ?? []

        var emptiedNames: [String] = []
        for companion in faceAlbums + animalAlbums {
            guard let companionPhotos = try? await detailUseCase.fetchPhotos(by: companion.id) else { continue }
            let companionIds = Set(companionPhotos.map(\.localIdentifier))
            let hadPhotosInTrip = !companionIds.isDisjoint(with: tripIds)
            let hasPhotosAfter = !companionIds.isDisjoint(with: remainingTripIds)
            if hadPhotosInTrip && !hasPhotosAfter {
                emptiedNames.append(companionDisplayName(companion))
            }
        }

        guard !emptiedNames.isEmpty else { return nil }
        let namesText = emptiedNames.joined(separator: ", ")
        return String(localized: "\(namesText)님의 이 여행 마지막 사진이에요. 지우면 동행자 연결도 풀려요. 그래도 삭제할까요?", bundle: .module)
    }

    /// 사진이 0장인 동행자가 있을 때 "연결 끊을까요?" 확인
    private func promptDisconnect(emptiedCompanions: [Album], albumId: UUID, allLinkedIds: [UUID]) {
        let namesText = emptiedCompanions.map(companionDisplayName).joined(separator: ", ")
        showAlert(
            title: String(localized: "동행자 연결 확인", bundle: .module),
            message: String(localized: "\(namesText)님의 사진이 이 여행에 없어요. 동행자 연결을 끊을까요?", bundle: .module),
            buttons: [
                AlertButtonConfig(title: String(localized: "유지", bundle: .module), style: .cancel, action: nil),
                AlertButtonConfig(title: String(localized: "연결 끊기", bundle: .module), style: .destructive) { [weak self] in
                    Task {
                        await self?.disconnectCompanions(emptiedCompanions.map(\.id), albumId: albumId, allLinkedIds: allLinkedIds)
                    }
                }
            ]
        )
    }

    private func disconnectCompanions(_ idsToRemove: [UUID], albumId: UUID, allLinkedIds: [UUID]) async {
        let removeSet = Set(idsToRemove)
        let keptIds = allLinkedIds.filter { !removeSet.contains($0) }
        try? await detailUseCase.updateLinkedTravelerAlbums(albumId: albumId, albumIds: keptIds)
        let linkedFaceAlbums = (try? await detailUseCase.fetchLinkedFaceAlbums(albumId: albumId)) ?? []
        let linkedAnimalAlbums = (try? await detailUseCase.fetchLinkedAnimalAlbums(albumId: albumId)) ?? []
        travelerInfo = formatTravelerInfo(linkedFaceAlbums + linkedAnimalAlbums)
    }

    /// 여행에 등장한 얼굴/동물 앨범들을 "A와 B와 C의 여행"처럼 이름 나열 문구로 만들고, 인원 수는 따로 반환한다.
    /// 이름 지어준 경우는 실제 이름, 아직 안 지어준 경우는 사람은 "사람", 동물은 "반려동물"로 표시한다.
    /// 앨범 기간이 당일치기면(AutoAlbumUseCase의 명명 기준과 동일) "여행" 대신 "나들이"로 표시한다
    private func formatTravelerInfo(_ linkedAlbums: [Album]) -> TravelerInfo? {
        guard !linkedAlbums.isEmpty else { return nil }

        let names = linkedAlbums.map { album -> String in
            if album.isRenamed { return album.displayName }
            return album.from == "animal" ? String(localized: "반려동물", bundle: .module) : String(localized: "사람", bundle: .module)
        }
        let suffix = tripSuffix

        let name: String
        if names.count > 1 {
            let joinedPrefix = names.dropLast()
                .map { String(localized: "\($0)\($0.josa ? "과" : "와")", bundle: .module) }
                .joined(separator: " ")
            name = String(localized: "\(joinedPrefix) \(names.last!)의 \(suffix)", bundle: .module)
        } else {
            name = String(localized: "\(names[0])의 \(suffix)", bundle: .module)
        }

        return TravelerInfo(name: name, count: names.count)
    }

    private func deleteSelected(ids: [String], deleteInLibrary: Bool = false) async {
        guard let albumId = effectiveAlbumId else { return }
        do {
            isLoading = true
            try await detailUseCase.deletePhotos(ids, albumId: albumId, deleteInLibrary: deleteInLibrary)
            // 여행 앨범에서 사진을 지웠을 때, 연결된 얼굴/동물 앨범의 사진이 하나도 안 남았으면 그 연결도 같이 해제한다
            if isTravelAlbum {
                try await detailUseCase.pruneLinkedFaceAlbums(albumId: albumId)
                try await detailUseCase.pruneLinkedAnimalAlbums(albumId: albumId)
            }
            await reloadAfterMutation(removing: ids)
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    /// 삭제/제외 뒤 화면을 갱신한다. 실제 앨범이면 기존처럼 통째로 재조회하지만, 필터드 소스는
    /// presetPhotos가 상수라 재조회해도 그대로라서(지웠는데 다시 보임) 화면에 보이는 목록에서
    /// 직접 빼는 쪽으로 처리한다
    private func reloadAfterMutation(removing ids: [String]) async {
        guard presetPhotos != nil else {
            await loadPhotos()
            return
        }
        let idSet = Set(ids)
        photos.removeAll { idSet.contains($0.localIdentifier) }
        photoDetails = photos.map { PhotoDetail(id: $0.localIdentifier, createdDate: $0.createdAt, photo: $0) }
    }

    private func changeName(name: String) async {
        guard var album else { return }
        do {
            isLoading = true
            try await detailUseCase.editAlbumName(new: name, id: album.id)
            albumName = name
            // album 자체도 갱신해둬야, 다음에 다시 이름 변경 시트를 열었을 때 이전 이름이 아니라
            // 방금 저장한 이름/isRenamed 상태가 정확히 반영된다
            album.displayName = name
            album.isRenamed = true
            self.album = album
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func setCoverPhoto(id: String) async {
        guard var album else { return }
        do {
            try await detailUseCase.updateCoverPhoto(id: album.id, identifier: id)
            album.coverPhotoIdentifier = id
            self.album = album
            currentCoverId = id
        } catch {}
    }

    private func deleteAlbum() {
        guard let album else { return }
        isLoading = true
        Task {
            try await detailUseCase.deleteAlbum(album)
            isLoading = false
            onAction?(.pop)
        }
    }

    private func excludeSelected(ids: [String]) async {
        guard let albumId = effectiveAlbumId else { return }
        do {
            isLoading = true
            for id in ids {
                if isAnimalAlbum {
                    try await detailUseCase.excludeAnimalPhoto(id, fromAlbumId: albumId)
                } else {
                    try await detailUseCase.excludePhoto(id, fromAlbumId: albumId)
                }
            }
            await reloadAfterMutation(removing: ids)
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func mergeAlbums(targetAlbumIds: [UUID]) async {
        guard let album else { return }
        do {
            isLoading = true
            for targetId in targetAlbumIds {
                if isTravelAlbum {
                    try await detailUseCase.mergeTravelAlbums(sourceId: album.id, targetId: targetId)
                } else if isAnimalAlbum {
                    try await detailUseCase.mergeAnimalAlbums(sourceId: album.id, targetId: targetId)
                } else {
                    try await detailUseCase.mergeAlbums(sourceId: album.id, targetId: targetId)
                }
            }
            await loadPhotos()
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func splitAlbum(clusterIds: [UUID]) async {
        guard let album else { return }
        do {
            isLoading = true
            if isAnimalAlbum {
                try await detailUseCase.splitAnimalAlbum(albumId: album.id, clusterIds: clusterIds)
            } else {
                try await detailUseCase.splitAlbum(albumId: album.id, clusterIds: clusterIds)
            }
            await loadPhotos()
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}

extension AlbumDetailViewModel: ImageLoadable {}

/// 얼굴 앨범 디버깅용: 전체 사진 대신 얼굴 크롭 이미지를 반환하는 로더
struct FaceAlbumImageLoader: ImageLoadable {
    private let viewModel: AlbumDetailViewModel

    init(viewModel: AlbumDetailViewModel) {
        self.viewModel = viewModel
    }

    func loadImage(id: String, size: CGSize) async -> UIImage? {
        await viewModel.loadFaceImage(id: id, size: size)
    }
}

extension AlbumDetailViewModel: AlbumDetailViewModelDelegate {
    func save(name: String) {
        Task { await changeName(name: name) }
    }

    func deleteAlert() {
        showAlert(
            title: String(localized: "앨범 삭제", bundle: .module),
            message: String(localized: "앨범을 삭제 할까요?\n사진은 삭제하지 않아요", bundle: .module),
            buttons: [
                AlertButtonConfig(title: String(localized: "취소", bundle: .module), style: .default, action: {}),
                AlertButtonConfig(title: String(localized: "삭제", bundle: .module), style: .destructive, action: { self.deleteAlbum() })
            ]
        )
    }

    func changeMode(_ mode: AlbumDetailPageMode) {
        self.selectionMode = mode
    }

    func mergeTapped() {
        Task { [weak self] in
            guard let self, let album else { return }
            do {
                let candidates: [AlbumMergeCandidate]
                if isTravelAlbum {
                    candidates = try await detailUseCase.fetchOtherTravelAlbums(excluding: album.id)
                } else if isAnimalAlbum {
                    candidates = try await detailUseCase.fetchOtherAnimalAlbums(excluding: album.id)
                } else {
                    candidates = try await detailUseCase.fetchOtherFaceAlbums(excluding: album.id)
                }
                onAction?(.pickMergeTarget(candidates: candidates, isTravel: isTravelAlbum, currentAlbum: album))
            } catch {}
        }
    }

    func mergeInto(albumIds: [UUID]) {
        Task { await mergeAlbums(targetAlbumIds: albumIds) }
    }

    func splitTapped() {
        Task { [weak self] in
            guard let self, let album else { return }
            do {
                let clusters = isAnimalAlbum
                    ? try await detailUseCase.fetchAnimalClusters(albumId: album.id)
                    : try await detailUseCase.fetchClusters(albumId: album.id)
                onAction?(.pickSplitClusters(clusters: clusters))
            } catch {}
        }
    }

    func splitInto(clusterIds: [UUID]) {
        Task { await splitAlbum(clusterIds: clusterIds) }
    }

    func travelerManagementTapped() {
        Task { [weak self] in
            guard let self, let album else { return }
            do {
                let (travelers, others) = try await detailUseCase.fetchTravelerManagementCandidates(albumId: album.id)
                onAction?(.pickTravelerManagement(travelers: travelers, others: others))
            } catch {}
        }
    }

    func saveTravelerManagement(travelerIds: [UUID]) {
        Task { [weak self] in
            guard let self, let album else { return }
            do {
                try await detailUseCase.updateLinkedTravelerAlbums(albumId: album.id, albumIds: travelerIds)
                let linkedFaceAlbums = try await detailUseCase.fetchLinkedFaceAlbums(albumId: album.id)
                let linkedAnimalAlbums = try await detailUseCase.fetchLinkedAnimalAlbums(albumId: album.id)
                travelerInfo = formatTravelerInfo(linkedFaceAlbums + linkedAnimalAlbums)
            } catch {}
        }
    }

    func refreshAfterPhotosAdded() {
        send(.refresh)
    }

    func setCover(id: String) {
        Task { await setCoverPhoto(id: id) }
    }

    func shareAllTapped() {
        send(.shareAll)
    }
}
