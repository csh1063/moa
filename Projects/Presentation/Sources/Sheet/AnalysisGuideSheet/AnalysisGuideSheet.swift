//
//  AnalysisGuideSheet.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Domain

/// 분석하기를 누르면 뜨는 시작 안내 — 분석할 사진 수와 예상 시간, 기다리는 동안 알아둘 것.
/// 처음(분석된 사진이 없을 때)은 오래 걸려서 안내 3개, 추가 분석은 Wi-Fi 안내만 보여준다.
/// 사진 수는 사진첩 전체를 훑어야 해서, 시트를 먼저 띄우고 두 숫자 칸만 "..."로 돌리다가 채운다
final class AnalysisGuideSheet: UIViewController {

    var onStart: (() -> Void)?

    private let isFirstAnalysis: Bool
    private let loadEstimate: () async -> AnalysisEstimate?
    private let countValueLabel = UILabel()
    private let timeValueLabel = UILabel()
    private var dotsTimer: Timer?

    private let grabberView: UIView = {
        let grabberView = UIView()
        grabberView.backgroundColor = Theme.strokeSoft
        grabberView.layer.cornerRadius = 2.5
        return grabberView
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        return stack
    }()

    private lazy var laterButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "나중에", bundle: .module)
        config.baseForegroundColor = Theme.textPrimary
        config.background.backgroundColor = Theme.surface
        config.background.strokeColor = Theme.strokeSoft
        config.background.strokeWidth = 1
        config.background.cornerRadius = 18
        return UIButton(configuration: config)
    }()

    private lazy var startButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "분석 시작", bundle: .module)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.background.cornerRadius = 18
        return UIButton(configuration: config)
    }()

    init(isFirstAnalysis: Bool, loadEstimate: @escaping () async -> AnalysisEstimate?) {
        self.isFirstAnalysis = isFirstAnalysis
        self.loadEstimate = loadEstimate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface
        setupLayout()
        laterButton.addTarget(self, action: #selector(didTapLater), for: .touchUpInside)
        startButton.addTarget(self, action: #selector(didTapStart), for: .touchUpInside)
        startDots()
        Task { [weak self] in
            guard let self else { return }
            let estimate = await self.loadEstimate()
            self.dotsTimer?.invalidate()
            self.countValueLabel.text = estimate.map { String(localized: "\($0.photoCount.formatted())장", bundle: .module) } ?? "-"
            self.timeValueLabel.text = estimate.map { Self.durationText($0.estimatedSeconds) } ?? "-"
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        dotsTimer?.invalidate()
    }

    private func startDots() {
        var step = 0
        let update = { [weak self] in
            let dots = String(repeating: ".", count: step % 3 + 1)
            self?.countValueLabel.text = dots
            self?.timeValueLabel.text = dots
            step += 1
        }
        update()
        dotsTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in update() }
    }

    /// 내용 높이에 맞춘 시트 높이 — 처음/추가 분석, 언어에 따라 줄 수가 달라서 고정값을 안 쓴다
    func fittingHeight(width: CGFloat) -> CGFloat {
        loadViewIfNeeded()
        let contentHeight = contentStack.systemLayoutSizeFitting(
            CGSize(width: width - 40, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        // 그래버(10+5) + 위 여백 16 + 내용 + 버튼 위 24 + 버튼 50 + 아래 여백 12
        return 15 + 16 + contentHeight + 24 + 50 + 12
    }

    // MARK: - Layout

    private func setupLayout() {
        let isFirst = isFirstAnalysis

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.text = isFirst
            ? String(localized: "사진 분석을 시작할게요", bundle: .module)
            : String(localized: "새 사진을 분석할게요", bundle: .module)

        let subtitleLabel = UILabel()
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = Theme.textSecondary
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = isFirst
            ? String(localized: "처음 한 번만 오래 걸려요", bundle: .module)
            : String(localized: "지난 분석 이후 추가된 사진이에요", bundle: .module)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4

        let statStack = UIStackView(arrangedSubviews: [
            makeStatCard(
                title: isFirst
                    ? String(localized: "분석할 사진", bundle: .module)
                    : String(localized: "새 사진", bundle: .module),
                valueLabel: countValueLabel
            ),
            makeStatCard(
                title: String(localized: "예상 시간", bundle: .module),
                valueLabel: timeValueLabel
            )
        ])
        statStack.axis = .horizontal
        statStack.spacing = 10
        statStack.distribution = .fillEqually

        var guides: [UIView] = []
        if isFirst {
            guides.append(makeGuideRow(
                icon: "lucide_smartphone",
                title: String(localized: "앱을 켜두면 좋아요", bundle: .module),
                detail: String(localized: "다른 앱으로 가거나 화면을 끄면 잠시 멈춰요", bundle: .module)
            ))
            guides.append(makeGuideRow(
                icon: "lucide_battery_charging",
                title: String(localized: "충전기를 연결해두면 좋아요", bundle: .module),
                detail: String(localized: "분석하는 동안 화면이 켜져 있어서 배터리를 많이 쓸 수 있어요", bundle: .module)
            ))
        }
        guides.append(makeGuideRow(
            icon: "lucide_wifi",
            title: String(localized: "Wi-Fi에 연결해두면 좋아요", bundle: .module),
            detail: String(localized: "iCloud에 있는 사진을 받느라 데이터를 쓸 수 있어요", bundle: .module)
        ))
        let guideStack = UIStackView(arrangedSubviews: guides)
        guideStack.axis = .vertical
        guideStack.spacing = 14

        [headerStack, statStack, guideStack].forEach { contentStack.addArrangedSubview($0) }

        let buttonStack = UIStackView(arrangedSubviews: [laterButton, startButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 10
        buttonStack.distribution = .fillEqually

        [grabberView, contentStack, buttonStack].forEach { view.addSubview($0) }

        grabberView.snp.makeConstraints { make in
            make.top.equalTo(view).offset(10)
            make.centerX.equalTo(view)
            make.width.equalTo(42)
            make.height.equalTo(5)
        }
        contentStack.snp.makeConstraints { make in
            make.top.equalTo(grabberView.snp.bottom).offset(16)
            make.leading.trailing.equalTo(view).inset(20)
        }
        buttonStack.snp.makeConstraints { make in
            make.top.equalTo(contentStack.snp.bottom).offset(24)
            make.leading.trailing.equalTo(view).inset(20)
            make.height.equalTo(50)
        }
    }

    private func makeStatCard(title: String, valueLabel: UILabel) -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.background
        card.layer.cornerRadius = 14

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = Theme.textSecondary
        titleLabel.text = title

        valueLabel.font = .systemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = Theme.textPrimary
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.text = " "  // 시트 높이 계산 시점에 한 줄 높이를 잡아두려고

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        card.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
        return card
    }

    private func makeGuideRow(icon: String, title: String, detail: String) -> UIView {
        let iconView = UIImageView(image: UIImage(named: icon, in: .module, with: nil)?.withRenderingMode(.alwaysTemplate))
        iconView.tintColor = Theme.primary
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.text = title

        let detailLabel = UILabel()
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = Theme.textSecondary
        detailLabel.numberOfLines = 0
        detailLabel.text = detail

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let row = UIView()
        row.addSubview(iconView)
        row.addSubview(textStack)
        iconView.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
            make.size.equalTo(20)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(12)
            make.top.trailing.bottom.equalToSuperview()
        }
        return row
    }

    /// "1분 이내" / "약 33분" / "약 1시간 5분"
    static func durationText(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return String(localized: "1분 이내", bundle: .module) }
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "약 \(minutes)분", bundle: .module) }
        if rest == 0 { return String(localized: "약 \(hours)시간", bundle: .module) }
        return String(localized: "약 \(hours)시간 \(rest)분", bundle: .module)
    }

    // MARK: - Actions

    @objc private func didTapLater() {
        dismiss(animated: true)
    }

    @objc private func didTapStart() {
        // 안내 시트가 다 닫힌 뒤에 분석 시트를 띄워야 present가 겹치지 않는다
        let onStart = onStart
        dismiss(animated: true) { onStart?() }
    }
}
