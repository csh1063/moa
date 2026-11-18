//
//  AlbumAnalysisSheet.swift
//  Presentation
//
//  Created by sanghyeon on 4/27/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import UIKit
import Combine

final class AlbumAnalysisSheet: UIViewController {

    var progress: AnalyzeProgress
    /// 최소화 버튼을 눌렀을 때만 불린다 — 스와이프로는 안 닫혀서 이게 유일한 닫힘 신호
    var onMinimize: (() -> Void)?

    private let minimizeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "lucide_x", in: .module, with: nil), for: .normal)
        button.tintColor = Theme.textSecondary
        return button
    }()

    private let grabberView: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.strokeSoft
        view.layer.cornerRadius = 2.5
        return view
    }()

    private let circleBackground: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.surfaceCool
        view.layer.cornerRadius = 42
        return view
    }()

    private let logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "icon", in: .module, with: nil))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "새 앨범 만드는 중", bundle: .module)
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = Theme.textPrimary
        label.textAlignment = .center
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "사진과 얼굴, 위치를 분석하고\n관련 앨범을 만들고 있어요\n완료될 때까지 조금만 기다려주세요", bundle: .module)
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = Theme.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let photoRow = ProgressRow(icon: "lucide_image_plus", title: String(localized: "사진 분석 중", bundle: .module))
    private let albumRow = ProgressRow(icon: "lucide_layers", title: String(localized: "앨범 생성 중", bundle: .module))

    // MARK: - 자세히 체크리스트

    private let dateCheckItem = ChecklistItemRow(icon: "lucide_calendar", title: String(localized: "날짜 확인", bundle: .module))
    private let addressConvertItem = ChecklistItemRow(icon: "lucide_map_pin", title: String(localized: "좌표를 주소로", bundle: .module))
    private let travelSpotItem = ChecklistItemRow(icon: "lucide_briefcase", title: String(localized: "여행지 확인", bundle: .module))
    private let photoLabelItem = ChecklistItemRow(icon: "lucide_image", title: String(localized: "사진 분석", bundle: .module))
    private let faceAnalysisItem = ChecklistItemRow(icon: "lucide_circle_user", title: String(localized: "얼굴 분석", bundle: .module))
    private let animalAnalysisItem = ChecklistItemRow(icon: "lucide_paw_print", title: String(localized: "반려동물 분석", bundle: .module))
    private let similarItem = ChecklistItemRow(icon: "lucide_copy", title: String(localized: "비슷한 사진", bundle: .module))

    private let dateAlbumItem = ChecklistItemRow(icon: "lucide_calendar", title: String(localized: "날짜 앨범", bundle: .module))
    private let travelAlbumItem = ChecklistItemRow(icon: "lucide_briefcase", title: String(localized: "여행 앨범", bundle: .module))
    private let regionAlbumItem = ChecklistItemRow(icon: "lucide_map_pin", title: String(localized: "지역 앨범", bundle: .module))
    private let categoryAlbumItem = ChecklistItemRow(icon: "lucide_grid_2x2", title: String(localized: "카테고리 앨범", bundle: .module))
    private let faceAlbumItem = ChecklistItemRow(icon: "lucide_circle_user", title: String(localized: "얼굴 앨범", bundle: .module))
    private let animalAlbumItem = ChecklistItemRow(icon: "lucide_paw_print", title: String(localized: "반려동물 앨범", bundle: .module))
    private let duplicateAlbumItem = ChecklistItemRow(icon: "lucide_copy", title: String(localized: "중복 사진 앨범", bundle: .module))

    private let photoChecklistContainer = UIStackView()
    private let albumChecklistContainer = UIStackView()
    private var photoChecklistWrapper: UIView!
    private var albumChecklistWrapper: UIView!
    private var isPhotoChecklistExpanded = false
    private var isAlbumChecklistExpanded = false

    private let scrollView = UIScrollView()

    private let progressPublisher: AnyPublisher<Double, Never>
    private let photoCompletedPublisher: AnyPublisher<Void, Never>
    private let albumProgressPublisher: AnyPublisher<Double, Never>
    private let albumCompletedPublisher: AnyPublisher<Void, Never>
    private var cancellables = Set<AnyCancellable>()

    init(progress: AnalyzeProgress) {
        self.progress = progress

        self.progressPublisher = progress.photoProgress
        self.photoCompletedPublisher = progress.photoCompleted
        self.albumProgressPublisher = progress.albumProgress
        self.albumCompletedPublisher = progress.albumCompleted

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("AlbumAnalysisSheet does not support NSCoding.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface
        setupLayout()
        setupBindings()
        minimizeButton.addTarget(self, action: #selector(minimizeTapped), for: .touchUpInside)
    }

    @objc private func minimizeTapped() {
        onMinimize?()
        dismiss(animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        photoRow.updateBorderColor()
        albumRow.updateBorderColor()
    }

    // MARK: - Layout

    private func setupLayout() {
        // Circle
        circleBackground.addSubview(logoImageView)
        logoImageView.snp.makeConstraints { make in
            make.center.equalTo(circleBackground)
            make.width.height.equalTo(48)
        }

        // Text stack
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 8

        // 자세히 체크리스트 — 각각 얇은 구분선 + 세로 스택
        [photoChecklistContainer, albumChecklistContainer].forEach {
            $0.axis = .vertical
            $0.spacing = 6
        }
        [dateCheckItem, addressConvertItem, travelSpotItem, photoLabelItem, faceAnalysisItem, animalAnalysisItem, similarItem]
            .forEach { photoChecklistContainer.addArrangedSubview($0) }
        [dateAlbumItem, travelAlbumItem, regionAlbumItem, categoryAlbumItem, faceAlbumItem, animalAlbumItem, duplicateAlbumItem]
            .forEach { albumChecklistContainer.addArrangedSubview($0) }

        photoChecklistWrapper = wrapWithTopDivider(photoChecklistContainer)
        albumChecklistWrapper = wrapWithTopDivider(albumChecklistContainer)
        // 펼침은 wrapper의 isHidden으로만 — 그래야 공간까지 사라진다
        photoChecklistWrapper.isHidden = true
        albumChecklistWrapper.isHidden = true

        let photoGroup = UIStackView(arrangedSubviews: [photoRow, photoChecklistWrapper])
        photoGroup.axis = .vertical
        photoGroup.spacing = 10
        // 재생성은 사진 분석 없이 앨범만 다시 만든다
        photoGroup.isHidden = progress.mode != .analysis
        albumRow.setDetailToggleHidden(progress.mode == .regenerateSingle)
        if progress.mode != .analysis {
            titleLabel.text = String(localized: "앨범 다시 만드는 중", bundle: .module)
            subtitleLabel.text = String(localized: "분석된 사진으로 앨범을 다시 만들고 있어요\n완료될 때까지 조금만 기다려주세요", bundle: .module)
        }

        let albumGroup = UIStackView(arrangedSubviews: [albumRow, albumChecklistWrapper])
        albumGroup.axis = .vertical
        albumGroup.spacing = 10

        // Row stack
        let rowStack = UIStackView(arrangedSubviews: [photoGroup, albumGroup])
        rowStack.axis = .vertical
        rowStack.spacing = 10

        // Main stack
        let mainStack = UIStackView(arrangedSubviews: [
            circleBackground,
            textStack,
            rowStack
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 18
        mainStack.alignment = .center
        mainStack.setCustomSpacing(12, after: rowStack)

        view.addSubview(grabberView)
        view.addSubview(scrollView)
        view.addSubview(minimizeButton)
        scrollView.addSubview(mainStack)

        grabberView.snp.makeConstraints { make in
            make.top.equalTo(view).offset(10)
            make.centerX.equalTo(view)
            make.width.equalTo(42)
            make.height.equalTo(5)
        }

        minimizeButton.snp.makeConstraints { make in
            // 탭 영역 44x44, 아이콘 위치는 기존 그대로
            make.top.equalTo(grabberView.snp.bottom).offset(8)
            make.trailing.equalTo(view).inset(12)
            make.width.height.equalTo(44)
        }

        circleBackground.snp.makeConstraints { make in
            make.width.height.equalTo(84)
        }

        scrollView.snp.makeConstraints { make in
            make.top.equalTo(grabberView.snp.bottom).offset(10)
            make.leading.trailing.bottom.equalTo(view)
        }

        mainStack.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide).offset(10)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-24)
            make.leading.trailing.equalTo(view).inset(20)
        }

        rowStack.snp.makeConstraints { make in
            make.leading.trailing.equalTo(mainStack)
        }

        subtitleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view).inset(24)
        }
    }

    /// 위에 구분선을 붙인 wrapper — 펼침/접힘은 반드시 이 wrapper의 isHidden으로 한다
    private func wrapWithTopDivider(_ content: UIStackView) -> UIView {
        let divider = UIView()
        divider.backgroundColor = Theme.strokeSoft

        let wrapper = UIView()
        wrapper.addSubview(divider)
        wrapper.addSubview(content)

        divider.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(wrapper)
            make.height.equalTo(1)
        }
        content.snp.makeConstraints { make in
            make.top.equalTo(divider.snp.bottom).offset(10)
            make.leading.trailing.bottom.equalTo(wrapper)
        }
        return wrapper
    }

    // MARK: - Bindings

    private func setupBindings() {
        // 두 트랙이 동시에 진행돼서 두 인디케이터를 처음부터 같이 돌린다
        photoRow.startSpinner()
        albumRow.setTitle(String(localized: "앨범 생성 중", bundle: .module))
        albumRow.startSpinner()

        photoRow.onToggleDetail = { [weak self] in self?.toggleChecklist(isPhoto: true) }
        albumRow.onToggleDetail = { [weak self] in self?.toggleChecklist(isPhoto: false) }

        // 진행률 값은 리플레이되므로 "완료" 판단은 별도 완료 이벤트로만 한다
        progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.photoRow.updateProgress(progress)
            }
            .store(in: &cancellables)

        albumProgressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.albumRow.updateProgress(progress)
            }
            .store(in: &cancellables)

        photoCompletedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.photoRow.updateProgress(1.0)
                self.photoRow.setTitle(String(localized: "사진 분석 완료", bundle: .module))
                self.photoRow.stopSpinner()
            }
            .store(in: &cancellables)

        albumCompletedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.albumRow.updateProgress(1.0)
                self.albumRow.setTitle(String(localized: "앨범 생성 완료", bundle: .module))
                self.albumRow.stopSpinner()
                self.endPage()
            }
            .store(in: &cancellables)

        bindChecklistItem(dateCheckItem, to: progress.analysisChecklist.dateCheck)
        bindChecklistItem(addressConvertItem, to: progress.analysisChecklist.addressConvert)
        bindChecklistItem(travelSpotItem, to: progress.analysisChecklist.travelSpot)
        bindChecklistItem(photoLabelItem, to: progress.analysisChecklist.photoLabel)
        bindChecklistItem(faceAnalysisItem, to: progress.analysisChecklist.face)
        bindChecklistItem(animalAnalysisItem, to: progress.analysisChecklist.animal)
        bindChecklistItem(similarItem, to: progress.analysisChecklist.similar)

        bindChecklistItem(dateAlbumItem, to: progress.albumChecklist.date)
        bindChecklistItem(travelAlbumItem, to: progress.albumChecklist.travel)
        bindChecklistItem(regionAlbumItem, to: progress.albumChecklist.region)
        bindChecklistItem(categoryAlbumItem, to: progress.albumChecklist.category)
        bindChecklistItem(faceAlbumItem, to: progress.albumChecklist.face)
        bindChecklistItem(animalAlbumItem, to: progress.albumChecklist.animal)
        bindChecklistItem(duplicateAlbumItem, to: progress.albumChecklist.duplicate)
    }

    private func bindChecklistItem(_ item: ChecklistItemRow, to publisher: AnyPublisher<Double, Never>) {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { ratio in
                let state: ChecklistItemRow.State = ratio <= 0 ? .waiting : (ratio >= 1 ? .done : .inProgress)
                item.setState(state)
            }
            .store(in: &cancellables)
    }

    // MARK: - 자세히 아코디언

    /// 한쪽을 펼치면 다른 쪽은 접고, 펼친 게 있으면 .large, 없으면 .medium
    private func toggleChecklist(isPhoto: Bool) {
        let willExpandPhoto = isPhoto ? !isPhotoChecklistExpanded : false
        let willExpandAlbum = isPhoto ? false : !isAlbumChecklistExpanded
        isPhotoChecklistExpanded = willExpandPhoto
        isAlbumChecklistExpanded = willExpandAlbum

        photoRow.setDetailExpanded(willExpandPhoto)
        albumRow.setDetailExpanded(willExpandAlbum)

        if let sheetPresentation = sheetPresentationController {
            let anyExpanded = willExpandPhoto || willExpandAlbum
            sheetPresentation.animateChanges {
                sheetPresentation.selectedDetentIdentifier = anyExpanded ? .large : .medium
            }
        }

        UIView.animate(withDuration: 0.3) {
            self.photoChecklistWrapper.isHidden = !willExpandPhoto
            self.albumChecklistWrapper.isHidden = !willExpandAlbum
            self.view.layoutIfNeeded()
        }
    }

    private func endPage() {
        self.dismiss(animated: true)
    }
}
