//
//  TabbarViewModel.swift
//  Presentation
//
//  Created by sanghyeon on 4/29/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Combine
import Domain

enum TabbarViewModelAction {
    case progressSheet(AnalyzeProgress)
    /// 분석 시작 안내 — 시트는 바로 띄우고 사진 수/예상 시간은 loadEstimate로 나중에 채운다
    case analysisGuide(isFirstAnalysis: Bool, loadEstimate: () async -> AnalysisEstimate?, onStart: () -> Void)
    case showLibraryImportPicker(LibraryAlbumImportUseCase)
}

/// 분석 시트를 분석하기/재생성이 같이 쓴다 — 재생성은 사진 분석 줄을 숨긴다
enum AnalyzeMode {
    case analysis
    /// 전체 재생성 — 앨범 줄 "자세히" 유지
    case regenerateAll
    /// 개별 앨범 재생성 — 앨범 줄 "자세히" 숨김
    case regenerateSingle
}

struct AnalyzeProgress {
    let mode: AnalyzeMode
    let photoProgress: AnyPublisher<Double, Never>
    let photoCompleted: AnyPublisher<Void, Never>
    let albumProgress: AnyPublisher<Double, Never>
    let albumCompleted: AnyPublisher<Void, Never>
    let analysisChecklist: AnalysisChecklistProgress
    let albumChecklist: AlbumChecklistProgress
}

/// 시트 "자세히" 목록 — 사진 분석 쪽 7항목. 얼굴/반려동물/사진은 같은 라벨 스트림 진행률을 공유한다
struct AnalysisChecklistProgress {
    let dateCheck: AnyPublisher<Double, Never>
    let addressConvert: AnyPublisher<Double, Never>
    let travelSpot: AnyPublisher<Double, Never>
    let photoLabel: AnyPublisher<Double, Never>
    let face: AnyPublisher<Double, Never>
    let animal: AnyPublisher<Double, Never>
    let similar: AnyPublisher<Double, Never>
}

/// 시트 "자세히" 목록 — 앨범 생성 쪽 7항목
struct AlbumChecklistProgress {
    let date: AnyPublisher<Double, Never>
    let travel: AnyPublisher<Double, Never>
    let region: AnyPublisher<Double, Never>
    let category: AnyPublisher<Double, Never>
    let face: AnyPublisher<Double, Never>
    let animal: AnyPublisher<Double, Never>
    let duplicate: AnyPublisher<Double, Never>
}

@MainActor
public final class TabbarViewModel: BaseViewModel {

    enum Input {
        case analysis
        case reAutoAlbum
        /// 자주가는 동네를 바꾼 뒤 여행 앨범 전체를 다시 만든다
        case rebuildTravelAlbums
        case clear
        case permission
        case showConsent
        case afterConsent
        case showOnboarding
        case afterOnboarding
        case importLibraryAlbum
    }

    public struct Output {
        let photoProgress: AnyPublisher<Double, Never>
        let albumProgress: AnyPublisher<Double, Never>
        let onboarding: AnyPublisher<Bool?, Never>
        let consent: AnyPublisher<Bool?, Never>
        let permission: AnyPublisher<PhotoPermission, Never>
        let isComplete: AnyPublisher<Bool, Never>
    }

    @Published private var progressRatio: Double = 0
    @Published private var autoAlbumProgressRatio: Double = 0
    // 진행률 값은 구독 시점에 리플레이되므로 "완료"는 리플레이 없는 이벤트로 따로 보낸다
    private let photoCompletedSubject = PassthroughSubject<Void, Never>()

    // MARK: - 진행률 컴포넌트 (사용자 확정 가중치)
    //
    // 각 항목은 자기 가중치만큼의 독립적인 0~1 값이고, 전체 진행률은 매번 가중합으로 다시 계산한다(순서 무관)
    // 사진 분석: 날짜 5% + (지오코딩+라벨/임베딩) 85% + 중복사진 탐지 10%
    @Published private var dateProgress: Double = 0
    @Published private var addressProgress: Double = 0
    @Published private var streamProgress: Double = 0
    @Published private var dupDetectProgress: Double = 0
    // 앨범 생성: 날짜 5% + 여행 30% + 지역 5% + 얼굴 15%/동물 15% + 여행자연결 10% + 카테고리 10% + 중복앨범저장 10%
    @Published private var dateAlbumProgress: Double = 0
    @Published private var travelProgress: Double = 0
    @Published private var regionProgress: Double = 0
    @Published private var faceProgress: Double = 0
    @Published private var animalProgress: Double = 0
    private var travelerLinkProgress: Double = 0
    @Published private var categoryProgress: Double = 0
    @Published private var dupSaveProgress: Double = 0

    private func resetProgressComponents() {
        dateProgress = 0; addressProgress = 0; streamProgress = 0; dupDetectProgress = 0
        dateAlbumProgress = 0
        travelProgress = 0; regionProgress = 0; faceProgress = 0; animalProgress = 0
        travelerLinkProgress = 0; categoryProgress = 0; dupSaveProgress = 0
    }

    private func recomputePhotoProgress() {
        progressRatio = dateProgress * 0.05 + streamProgress * 0.85 + dupDetectProgress * 0.1
    }

    private func recomputeAlbumProgress() {
        autoAlbumProgressRatio = dateAlbumProgress * 0.05
            + travelProgress * 0.3
            + regionProgress * 0.05
            + faceProgress * 0.15
            + animalProgress * 0.15
            + travelerLinkProgress * 0.1
            + categoryProgress * 0.1
            + dupSaveProgress * 0.1
    }
    private let albumCompletedSubject = PassthroughSubject<Void, Never>()
    @Published private var isAnalyzing: Bool = false {
        // 분석/재생성 중엔 화면 자동 잠금을 막는다 — 화면이 꺼지면 분석도 멈춘다
        didSet { UIApplication.shared.isIdleTimerDisabled = isAnalyzing }
    }
    /// 이번 분석에서 실제로 분석할 사진 수 — 끝난 뒤 이 기기의 장당 속도를 저장할 때 쓴다
    private var analysisPhotoCount = 0
    /// 분석 중에 앱을 나갔다 왔으면 멈춰 있던 시간이 섞여서 속도를 저장하지 않는다
    private var leftAppDuringAnalysis = false
    @Published private var isComplete: Bool = false
    @Published private var onboarding: Bool?
    @Published private var consent: Bool?
    @Published private var permission: PhotoPermission = .notDetermined

    var onAction: ((TabbarViewModelAction) -> Void)?

    let input = PassthroughSubject<Input, Never>()

    private let permissionUseCase: PermissionUseCase
    private let analysisUseCase: PhotoAnalysisUseCase
    private let autoAlbumUseCase: AutoAlbumUseCase
    private let legacyAccessUseCase: LegacyAccessUseCase
    private let libraryAlbumImportUseCase: LibraryAlbumImportUseCase

    private var cancellables = Set<AnyCancellable>()

    init(permissionUseCase: PermissionUseCase,
         analysisUseCase: PhotoAnalysisUseCase,
         autoAlbumUseCase: AutoAlbumUseCase,
         legacyAccessUseCase: LegacyAccessUseCase,
         libraryAlbumImportUseCase: LibraryAlbumImportUseCase) {
        self.permissionUseCase = permissionUseCase
        self.analysisUseCase = analysisUseCase
        self.autoAlbumUseCase = autoAlbumUseCase
        self.legacyAccessUseCase = legacyAccessUseCase
        self.libraryAlbumImportUseCase = libraryAlbumImportUseCase

        super.init()

        self.bind()

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self, self.isAnalyzing else { return }
                self.leftAppDuringAnalysis = true
            }
            .store(in: &cancellables)
    }

    public func transform() -> Output {
        return Output(
            photoProgress: $progressRatio.eraseToAnyPublisher(),
            albumProgress: $autoAlbumProgressRatio.eraseToAnyPublisher(),
            onboarding: $onboarding.eraseToAnyPublisher(),
            consent: $consent.eraseToAnyPublisher(),
            permission: $permission.eraseToAnyPublisher(),
            isComplete: $isComplete.eraseToAnyPublisher()
        )
    }

    func send(_ input: Input) {
        self.input.send(input)
    }

    private func bind() {
        self.input.sink { [weak self] input in
            guard let self else { return }
            Task { @MainActor in await self.handle(input) }
        }
        .store(in: &cancellables)
    }

    private func makeAnalyzeProgress(mode: AnalyzeMode = .analysis) -> AnalyzeProgress {
        AnalyzeProgress(
            mode: mode,
            photoProgress: $progressRatio.eraseToAnyPublisher(),
            photoCompleted: photoCompletedSubject.eraseToAnyPublisher(),
            albumProgress: $autoAlbumProgressRatio.eraseToAnyPublisher(),
            albumCompleted: albumCompletedSubject.eraseToAnyPublisher(),
            analysisChecklist: AnalysisChecklistProgress(
                dateCheck: $dateProgress.eraseToAnyPublisher(),
                addressConvert: $addressProgress.eraseToAnyPublisher(),
                travelSpot: $travelProgress.eraseToAnyPublisher(),
                photoLabel: $streamProgress.eraseToAnyPublisher(),
                face: $faceProgress.eraseToAnyPublisher(),
                animal: $animalProgress.eraseToAnyPublisher(),
                similar: $dupDetectProgress.eraseToAnyPublisher()
            ),
            albumChecklist: AlbumChecklistProgress(
                date: $dateAlbumProgress.eraseToAnyPublisher(),
                travel: $travelProgress.eraseToAnyPublisher(),
                region: $regionProgress.eraseToAnyPublisher(),
                category: $categoryProgress.eraseToAnyPublisher(),
                face: $faceProgress.eraseToAnyPublisher(),
                animal: $animalProgress.eraseToAnyPublisher(),
                duplicate: $dupSaveProgress.eraseToAnyPublisher()
            )
        )
    }

    private func handle(_ input: Input) async {
        switch input {
        case .showConsent:
            await checkConsent()
        case .afterConsent:
            await consentComplete()
        case .showOnboarding:
            await checkOnboarding()
        case .afterOnboarding:
            await onboardingComplete()
        case .importLibraryAlbum:
            self.onAction?(.showLibraryImportPicker(libraryAlbumImportUseCase))
        case .analysis:
            // 진행 중에 다시 시작하면 진행률이 튀고 쓰는 중인 앨범을 지우게 된다
            guard !isAnalyzing else { showAnalyzingAlert(); return }
            analysisPhotoCount = 0
            let loadEstimate: () async -> AnalysisEstimate? = { [weak self] in
                guard let self, let estimate = try? await self.analysisUseCase.estimate() else { return nil }
                self.analysisPhotoCount = estimate.photoCount
                return estimate
            }
            onAction?(.analysisGuide(isFirstAnalysis: (try? analysisUseCase.isFirstAnalysis()) ?? false, loadEstimate: loadEstimate, onStart: { [weak self] in
                Task {
                    guard let self else { return }
                    // 지난 실행 값(1.0)이 남아 있으면 새 시트가 바로 "완료"로 보인다
                    self.progressRatio = 0
                    self.autoAlbumProgressRatio = 0
                    self.onAction?(.progressSheet(self.makeAnalyzeProgress()))
                    await self.analysis()
                }
            }))
        case .reAutoAlbum:
            // 진행 중에 다시 시작하면 진행률이 튀고 쓰는 중인 앨범을 지우게 된다
            guard !isAnalyzing else { showAnalyzingAlert(); return }
            showAlert(
                title: String(localized: "앨범 재생성", bundle: .module),
                message: String(localized: "앨범들을 삭제 후 다시 생성해요.\n어떤 앨범을 다시 생성할까요?", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "취소", bundle: .module), style: .cancel, action: nil),
                    AlertButtonConfig(title: String(localized: "전체 자동 앨범", bundle: .module), style: .default) { [weak self] in
                        Task {
                            guard let self else {return}
                            let startedAt = Date()
                            debugLog("⏱️ [재생성] 시작: \(startedAt)")
                            self.isAnalyzing = true
                            defer { self.isAnalyzing = false }

                            await self.albumClear()
                            debugLog("⏱️ [재생성] 기존 앨범 삭제 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")

                            self.autoAlbumProgressRatio = 0
                            self.onAction?(.progressSheet(self.makeAnalyzeProgress(mode: .regenerateAll)))

                            // 재생성은 사진 분석 없이 앨범만 만들어서 사진 분석은 바로 완료 처리한다
                            self.progressRatio = 1.0
                            self.photoCompletedSubject.send(())
                            await self.runAlbumGeneration(fullRegenerate: true)

                            let finishedAt = Date()
                            let elapsedMinutes = finishedAt.timeIntervalSince(startedAt) / 60
                            debugLog("⏱️ [재생성] 종료: \(finishedAt) — 총 \(String(format: "%.1f", elapsedMinutes))분 소요")
                        }
                    },
                    AlertButtonConfig(title: String(localized: "날짜 앨범", bundle: .module), style: .default) { [weak self] in
                        Task {
                            guard let self else {return}
                            await self.createDateAutoAlbum()
                        }
                    },
                    AlertButtonConfig(title: String(localized: "주소 앨범", bundle: .module), style: .default) { [weak self] in
                        Task {
                            guard let self else {return}
                            await self.createLocationAutoAlbum()
                        }
                    },
                    AlertButtonConfig(title: String(localized: "카테고리 앨범", bundle: .module), style: .default) { [weak self] in
                        Task {
                            guard let self else {return}
                            await self.createCategoryAutoAlbum()
                        }
                    },
                    AlertButtonConfig(title: String(localized: "얼굴/동물 앨범", bundle: .module), style: .default) { [weak self] in
                        Task {
                            guard let self else {return}
                            await self.createFaceAnimalAutoAlbum()
                        }
                    },
                    AlertButtonConfig(title: String(localized: "여행 앨범", bundle: .module), style: .default) { [weak self] in
                        Task {
                            guard let self else {return}
                            await self.createTravelAutoAlbum()
                        }
                    },
                    AlertButtonConfig(title: String(localized: "비슷한 사진 앨범", bundle: .module), style: .default) { [weak self] in
                        Task {
                            guard let self else {return}
                            await self.createSimilarAutoAlbum()
                        }
                    }
                ]
            )
        case .rebuildTravelAlbums:
            guard !isAnalyzing else { showAnalyzingAlert(); return }
            await regenerateSingleAlbum(deleting: ["travel"]) { onProgress in
                try await self.autoAlbumUseCase.rebuildAllTravelAlbums(onProgress: onProgress)
            }
        case .clear:
            guard !isAnalyzing else {
                showAlert(
                    title: String(localized: "삭제할 수 없어요", bundle: .module),
                    message: String(localized: "분석이 진행 중일 때는 사진과 앨범을 삭제할 수 없어요\n분석이 끝난 뒤 다시 시도해주세요", bundle: .module),
                    buttons: [
                        AlertButtonConfig(title: String(localized: "확인", bundle: .module), style: .default, action: nil)
                    ]
                )
                return
            }
            showAlert(
                title: String(localized: "초기화", bundle: .module),
                message: String(localized: "저장된 사진 및 앨범을 모두 삭제할까요?", bundle: .module),
                buttons: [
                    AlertButtonConfig(title: String(localized: "취소", bundle: .module), style: .cancel, action: nil),
                    AlertButtonConfig(title: String(localized: "삭제", bundle: .module), style: .destructive) { [weak self] in
                        Task {
                            await self?.clear()
                        }
                    }
                ]
            )
        case .permission:
            await checkPermission()
        }
    }

    // MARK: - 분석 + 앨범 생성 통합 플로우

    /// 사진 분석과 앨범 생성을 같이 진행한다 — 데이터가 준비되는 대로 관련 앨범을 바로 만든다
    /// - 주소 트랙: 지오코딩 완료 → 여행 앨범 → 지역 앨범
    /// - 라벨 트랙: 라벨+임베딩 완료 → 얼굴/동물 앨범, (주소 트랙이 끝난 뒤) 카테고리 앨범 → 중복사진 탐지
    /// 완료 신호는 두 스트림과 파생 작업이 전부 끝난 뒤에 보낸다
    private func analysis() async {
        guard !isAnalyzing else { return }
        self.isAnalyzing = true
        self.progressRatio = 0
        self.autoAlbumProgressRatio = 0
        self.isComplete = false
        self.resetProgressComponents()

        let startedAt = Date()
        leftAppDuringAnalysis = false
        debugLog("⏱️ [분석] 시작: \(startedAt)")

        // 완료 신호는 이 세 작업이 실제로 다 끝난 뒤에 보낸다
        var basicScanTask: Task<Void, Never>?
        var addressTrackTask: Task<Void, Never>?
        var labelTrackTask: Task<Void, Never>?
        // 카테고리는 분류 완료 표시를 남겨 지역 패스가 그 사진을 못 보게 되므로, 주소 트랙이 끝난 뒤에 돈다
        let (addressTrackDone, addressTrackDoneContinuation) = AsyncStream<Void>.makeStream()

        do {
            for try await progress in analysisUseCase.analysis(
                onBasicScanCompleted: { [weak self] in
                    debugLog("⏱️ [분석] 기본 스캔 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                    debugLog("⏱️ [분석] 지오코딩+라벨 스트림 시작 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                    // 동기 SwiftData 루프라 메인에서 돌면 UI가 멈춘다 — 메인 밖에서 돌리고 상태 갱신만 메인에서
                    basicScanTask = Task.detached(priority: .userInitiated) {
                        let stepStartedAt = Date()
                        debugLog("⏱️ [분석] 날짜 앨범 생성 시작 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                        try? await self?.autoAlbumUseCase.createDateAlbumsEarly()
                        // 영상은 라벨/좌표가 필요 없어 날짜 앨범과 같이 처리
                        try? await self?.autoAlbumUseCase.createVideoAlbumEarly()
                        await MainActor.run {
                            guard let self else { return }
                            self.dateProgress = 1
                            self.recomputePhotoProgress()
                            self.dateAlbumProgress = 1
                            self.recomputeAlbumProgress()
                        }
                        debugLog("⏱️ [분석] 날짜 앨범 생성 완료 — 구간 \(String(format: "%.1f", Date().timeIntervalSince(stepStartedAt)))초, 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                    }
                },
                onAddressStreamCompleted: { [weak self] in
                    debugLog("⏱️ [분석] 주소(지오코딩) 스트림 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                    addressTrackTask = Task.detached(priority: .userInitiated) {
                        await MainActor.run {
                            guard let self else { return }
                            self.addressProgress = 1
                            self.recomputePhotoProgress()
                        }
                        let stepStartedAt = Date()
                        debugLog("⏱️ [분석] 여행+지역 앨범 생성 시작 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                        // 여행 + 지역까지 처리
                        try? await self?.autoAlbumUseCase.createTravelAlbumsEarly()
                        await MainActor.run {
                            guard let self else { return }
                            self.travelProgress = 1
                            self.regionProgress = 1
                            self.recomputeAlbumProgress()
                        }
                        addressTrackDoneContinuation.finish()
                        debugLog("⏱️ [분석] 여행+지역 앨범 생성 완료 — 구간 \(String(format: "%.1f", Date().timeIntervalSince(stepStartedAt)))초, 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                    }
                },
                onLabelStreamCompleted: { [weak self] in
                    debugLog("⏱️ [분석] 라벨+임베딩 스트림 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                    labelTrackTask = Task.detached(priority: .userInitiated) {
                        let stepStartedAt = Date()
                        debugLog("⏱️ [분석] 얼굴/동물 앨범 생성 시작 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                        // 얼굴(0~0.5)/동물(0.5~1) 진행률을 나눠서, 추출 단계에서 채운 절반 뒤로 이어 채운다
                        try? await self?.autoAlbumUseCase.createPersonAndSimilarAlbums { ratio in
                            Task { @MainActor in
                                guard let self else { return }
                                if ratio <= 0.5 {
                                    self.faceProgress = max(self.faceProgress, 0.5 + ratio)
                                } else {
                                    self.faceProgress = 1
                                    self.animalProgress = max(self.animalProgress, ratio)
                                }
                                self.recomputeAlbumProgress()
                            }
                        }
                        // 여행자 연결까지 끝난 뒤 리턴된다
                        await MainActor.run {
                            guard let self else { return }
                            self.faceProgress = 1
                            self.animalProgress = 1
                            self.travelerLinkProgress = 1
                            self.recomputeAlbumProgress()
                        }
                        debugLog("⏱️ [분석] 얼굴/동물 앨범 생성 + 여행자 연결 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")

                        // 카테고리는 지역 패스가 끝난 뒤에 — 얼굴/동물은 기다리지 않고 먼저 돈다
                        for await _ in addressTrackDone {}

                        debugLog("⏱️ [분석] 카테고리 앨범 생성 시작 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                        try? await self?.autoAlbumUseCase.createCategoryAlbumsEarly()
                        await MainActor.run {
                            guard let self else { return }
                            self.categoryProgress = 1
                            self.recomputeAlbumProgress()
                        }
                        debugLog("⏱️ [분석] 카테고리 앨범 생성 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")

                        // 중복 사진 탐지 — 앨범 저장까지 같이 끝나서 끝나면 중복앨범저장 몫도 같이 올린다
                        debugLog("⏱️ [분석] 중복 사진 탐지 시작 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                        try? await self?.autoAlbumUseCase.detectDuplicatePhotos { ratio in
                            Task { @MainActor in
                                guard let self else { return }
                                self.dupDetectProgress = max(self.dupDetectProgress, ratio)
                                self.recomputePhotoProgress()
                            }
                        }
                        await MainActor.run {
                            guard let self else { return }
                            self.dupDetectProgress = 1
                            self.dupSaveProgress = 1
                            self.recomputePhotoProgress()
                            self.recomputeAlbumProgress()
                        }
                        debugLog("⏱️ [분석] 라벨 트랙(카테고리/얼굴/동물/중복탐지) 전체 완료 — 구간 \(String(format: "%.1f", Date().timeIntervalSince(stepStartedAt)))초, 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")
                    }
                }
            ) {
                switch progress.state {
                case .progress(let ratio):
                    self.streamProgress = max(self.streamProgress, ratio)
                    // 주소/얼굴/동물도 이 스트림 안에서 같이 진행되므로 같이 올린다 — 얼굴/동물은 추출분 절반까지만
                    self.addressProgress = max(self.addressProgress, ratio)
                    self.faceProgress = max(self.faceProgress, ratio * 0.5)
                    self.animalProgress = max(self.animalProgress, ratio * 0.5)
                    self.recomputePhotoProgress()
                    self.recomputeAlbumProgress()
                case .completed:
                    self.streamProgress = 1
                    self.recomputePhotoProgress()
                case .unavailable:
                    break
                }
            }
            self.streamProgress = 1
            self.recomputePhotoProgress()
            debugLog("⏱️ [분석] 주소+라벨 스트림 전체 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")

            // 파생 앨범 작업이 다 끝날 때까지 기다린 뒤에 완료 신호를 보낸다
            await basicScanTask?.value
            await addressTrackTask?.value
            await labelTrackTask?.value
            debugLog("⏱️ [분석] 파생 앨범 생성 작업(날짜/여행/지역/카테고리/얼굴/동물/중복) 전체 완료 — 누적 \(String(format: "%.1f", Date().timeIntervalSince(startedAt)))초")

            self.photoCompletedSubject.send(())
            try? await legacyAccessUseCase.markLegacyFreeAccess()
            if !leftAppDuringAnalysis {
                try? await analysisUseCase.recordAnalysisDuration(Date().timeIntervalSince(startedAt), photoCount: analysisPhotoCount)
            }

            self.progressRatio = 1.0
            self.autoAlbumProgressRatio = 1.0
            self.isComplete = true
            self.albumCompletedSubject.send(())
            self.endAllProcess()
        } catch {
            // 실패해도 트랙들은 계속 DB에 쓰고 있어서 끝날 때까지 기다린다(초기화 등과 겹치지 않게)
            await basicScanTask?.value
            await addressTrackTask?.value
            await labelTrackTask?.value
            self.progressRatio = 1.0
            self.autoAlbumProgressRatio = 1.0
            self.isComplete = true
            self.photoCompletedSubject.send(())
            self.albumCompletedSubject.send(())
        }
        self.isAnalyzing = false

        let finishedAt = Date()
        let elapsedMinutes = finishedAt.timeIntervalSince(startedAt) / 60
        debugLog("⏱️ [분석] 종료: \(finishedAt) — 총 \(String(format: "%.1f", elapsedMinutes))분 소요")
    }

    private func showAnalyzingAlert() {
        showAlert(
            title: String(localized: "분석이 진행 중이에요", bundle: .module),
            message: String(localized: "분석이 끝난 뒤 다시 시도해주세요", bundle: .module),
            buttons: [
                AlertButtonConfig(title: String(localized: "확인", bundle: .module), style: .default, action: nil)
            ]
        )
    }

    private func runAlbumGeneration(fullRegenerate: Bool = false) async {
        self.isComplete = false
        // 지난 실행 값이 남아 "자세히"가 엉뚱하게 보이지 않게 초기화
        self.resetAlbumProgressComponents()
        do {
            for try await progress in autoAlbumUseCase.generateAllAlbums(fullRegenerate: fullRegenerate) {
                self.autoAlbumProgressRatio = progress.ratio
                self.updateAlbumChecklist(ratio: progress.ratio)
                if case .completed = progress.step {
                    self.autoAlbumProgressRatio = 1.0
                    self.completeAlbumChecklist()
                    self.isComplete = true
                    self.albumCompletedSubject.send(())
                    self.endAllProcess()
                }
            }
        } catch {
            self.autoAlbumProgressRatio = 1.0
            self.completeAlbumChecklist()
            self.isComplete = true
            self.albumCompletedSubject.send(())
        }
    }

    private func resetAlbumProgressComponents() {
        dateAlbumProgress = 0; travelProgress = 0; regionProgress = 0
        faceProgress = 0; animalProgress = 0; categoryProgress = 0; dupSaveProgress = 0
    }

    private func completeAlbumChecklist() {
        dateAlbumProgress = 1; travelProgress = 1; regionProgress = 1
        faceProgress = 1; animalProgress = 1; categoryProgress = 1; dupSaveProgress = 1
    }

    /// generateAllAlbums의 5단계(각 1/5)를 "자세히" 7항목에 맞춰 반영한다
    private func updateAlbumChecklist(ratio: Double) {
        let step1 = min(ratio / 0.2, 1.0)
        dateAlbumProgress = max(dateAlbumProgress, step1)
        regionProgress = max(regionProgress, step1)
        categoryProgress = max(categoryProgress, step1)

        if ratio > 0.2 {
            faceProgress = max(faceProgress, min((ratio - 0.2) / 0.2, 1.0))
        }
        if ratio > 0.4 {
            animalProgress = max(animalProgress, min((ratio - 0.4) / 0.2, 1.0))
        }
        if ratio > 0.6 {
            travelProgress = max(travelProgress, min((ratio - 0.6) / 0.2, 1.0))
        }
        if ratio > 0.8 {
            dupSaveProgress = max(dupSaveProgress, min((ratio - 0.8) / 0.2, 1.0))
        }
    }

    // MARK: - 개별 앨범 (재)생성

    /// 삭제 카드 → 분석 시트(앨범 줄만, 이 앨범 하나의 진행이 0~100%). 도는 동안 다른 분석/재생성/초기화는 막는다
    private func regenerateSingleAlbum(
        deleting types: [String],
        _ work: (@escaping @Sendable (Double) -> Void) async throws -> Void
    ) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        if !types.isEmpty {
            await albumClear(types)
        }

        isComplete = false
        autoAlbumProgressRatio = 0
        onAction?(.progressSheet(makeAnalyzeProgress(mode: .regenerateSingle)))

        do {
            try await work { [weak self] ratio in
                Task { @MainActor in
                    guard let self else { return }
                    self.autoAlbumProgressRatio = max(self.autoAlbumProgressRatio, ratio)
                }
            }
        } catch {
            debugLog("error: \(error.localizedDescription)")
        }

        autoAlbumProgressRatio = 1.0
        isComplete = true
        albumCompletedSubject.send(())
        endAllProcess()
    }

    private func createTravelAutoAlbum() async {
        await regenerateSingleAlbum(deleting: ["travel"]) { onProgress in
            try await self.autoAlbumUseCase.rebuildAllTravelAlbums(onProgress: onProgress)
        }
    }

    private func createSimilarAutoAlbum() async {
        await regenerateSingleAlbum(deleting: ["similar"]) { onProgress in
            try await self.autoAlbumUseCase.createSimilarAlbum(onProgress: onProgress)
        }
    }

    private func createDateAutoAlbum() async {
        await regenerateSingleAlbum(deleting: ["date"]) { onProgress in
            try await self.autoAlbumUseCase.createDateAlbums(onProgress: onProgress)
        }
    }

    private func createLocationAutoAlbum() async {
        await regenerateSingleAlbum(deleting: ["location"]) { onProgress in
            try await self.autoAlbumUseCase.createLocationAlbums(onProgress: onProgress)
        }
    }

    private func createCategoryAutoAlbum() async {
        await regenerateSingleAlbum(deleting: ["category"]) { onProgress in
            try await self.autoAlbumUseCase.createCategoryAlbums(onProgress: onProgress)
        }
    }

    // 메인 화면에서 얼굴/동물이 한 섹션이라 재생성도 하나로 묶는다
    private func createFaceAnimalAutoAlbum() async {
        await regenerateSingleAlbum(deleting: ["face", "animal"]) { onProgress in
            try await self.autoAlbumUseCase.createFaceAlbums { onProgress($0 * 0.5) }
            try await self.autoAlbumUseCase.createAnimalAlbums { onProgress(0.5 + $0 * 0.5) }
        }
    }

    private func clear() async {
        do {
            self.isComplete = false
            try await withDeletionProgress(title: String(localized: "초기화 중", bundle: .module)) { onProgress in
                try await self.autoAlbumUseCase.deletePhotos(onProgress: onProgress)
            }
            self.isComplete = true
        } catch {
            debugLog("error: \(error.localizedDescription)")
        }
    }

    // isComplete는 안 보낸다 — 마이페이지 로딩 화면이 사라지는 중이면 이어지는 재생성 로딩이 무시된다
    private func albumClear(_ types: [String] = ["all"]) async {
        do {
            try await withDeletionProgress(title: String(localized: "기존 앨범 삭제 중", bundle: .module)) { onProgress in
                try await self.autoAlbumUseCase.deleteAutoAlbums(from: types, onProgress: onProgress)
            }
        } catch {
            debugLog("error: \(error.localizedDescription)")
        }
    }

    /// 닫을 수 없는 삭제 진행률 카드를 띄운 채로 실행한다
    private func withDeletionProgress(
        title: String,
        _ work: (@escaping @Sendable (Double) -> Void) async throws -> Void
    ) async throws {
        ProgressAlertManager.shared.show(title: title)
        defer { ProgressAlertManager.shared.hide() }
        try await work { ratio in
            DispatchQueue.main.async { ProgressAlertManager.shared.update(ratio) }
        }
        ProgressAlertManager.shared.update(1.0)
    }

    private func checkConsent() async {
        do {
            self.consent = try await permissionUseCase.showConsent()
        } catch {
            debugLog("checkConsent failed")
        }
    }

    private func consentComplete() async {
        do {
            try await permissionUseCase.completeConsent()
        } catch {
            debugLog("consentComplete fail")
        }
    }

    private func checkOnboarding() async {
        do {
            self.onboarding = try await permissionUseCase.showOnboarding()
        } catch {
            debugLog("checkConsent failed")
        }
    }

    private func onboardingComplete() async {
        do {
            try await permissionUseCase.completeOnboarding()
        } catch {
            debugLog("consentComplete fail")
        }
    }

    private func checkPermission() async {
        do {
            self.permission = try await permissionUseCase.checkPermission()
        } catch {
            debugLog("checkPermission failed")
        }
    }

    private func endAllProcess() {
        self.progressRatio = 0.0
        self.autoAlbumProgressRatio = 0.0
    }
}
