//
//  VideoViewerCell.swift
//  Presentation
//
//  Created by sanghyeon on 9/4/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import AVFoundation
import SnapKit

/// 뷰어에서 영상을 AVPlayer로 재생하는 셀 — 그리드/썸네일은 기존 이미지 경로를 쓴다
final class VideoViewerCell: UICollectionViewCell {

    static let identifier = "VideoViewerCell"

    // MARK: - UI

    private let playerLayer = AVPlayerLayer()

    private let posterImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        return iv
    }()

    private let playPauseButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: "lucide_play", in: .module, with: nil), for: .normal)
        btn.tintColor = Theme.primary
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        btn.layer.cornerRadius = 34
        btn.layer.masksToBounds = true
        return btn
    }()

    /// 좌/우 아무 쪽이나 길게 누르면 2배속 — 어느 쪽인지는 구분하지 않고 같은 동작
    private let fastForwardBadge: UILabel = {
        let label = UILabel()
        label.text = "2x"
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.textAlignment = .center
        label.layer.cornerRadius = 14
        label.layer.masksToBounds = true
        label.alpha = 0
        return label
    }()

    private let currentTimeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.text = "0:00"
        return label
    }()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.75)
        label.text = "0:00"
        return label
    }()

    private let leftEdgeZone = UIView()
    private let rightEdgeZone = UIView()

    private let progressSlider: UISlider = {
        let slider = UISlider()
        slider.minimumTrackTintColor = Theme.primary
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.setThumbImage(VideoViewerCell.filledThumbImage(), for: .normal)
        slider.tintColor = Theme.primary
        return slider
    }()

    /// Lucide circle은 속이 빈 외곽선이라, 같은 크기로 속이 찬 원을 직접 그린다
    private static func filledThumbImage() -> UIImage {
        let side = UIImage(named: "lucide_circle", in: .module, with: nil)?.size.width ?? 24
        // Lucide circle의 실제 원(r=10, 선두께 2)은 24 캔버스 중 지름 22를 차지한다
        let diameter = side * 22 / 24
        let inset = (side - diameter) / 2
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            Theme.primary.setFill()
            UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: diameter, height: diameter)).fill()
        }.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - State

    /// 재사용된 셀에 늦게 온 포스터가 그려지지 않게 비교하는 식별자
    var currentPhotoId: String?
    private var player: AVPlayer?
    private var isPlaying = false
    private var isScrubbing = false
    private var isFastForwarding = false
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pause()
        setControlsHidden(false, animated: false)
        removeTimeObserver()
        player = nil
        playerLayer.player = nil
        posterImageView.image = nil
        posterImageView.isHidden = false
        currentPhotoId = nil
        currentTimeLabel.text = "0:00"
        durationLabel.text = "0:00"
        progressSlider.value = 0
        removeEndObserver()
    }

    deinit {
        // 블록 옵저버는 지우기 전까지 NotificationCenter가 붙잡고 있어서, 셀이 사라질 때도 직접 지워야 한다
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    // MARK: - Setup

    private func setupViews() {
        contentView.layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect

        contentView.addSubview(posterImageView)
        posterImageView.snp.makeConstraints { $0.edges.equalToSuperview() }

        // 좌/우 가장자리 40pt에서만 길게 누르면 2배속
        [leftEdgeZone, rightEdgeZone].forEach { zone in
            contentView.addSubview(zone)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.delegate = self
            zone.addGestureRecognizer(longPress)
        }
        leftEdgeZone.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(40)
        }
        rightEdgeZone.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
            make.width.equalTo(40)
        }

        contentView.addSubview(fastForwardBadge)
        // 상단바(100pt) 바로 아래 우측
        fastForwardBadge.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(112)
            make.trailing.equalToSuperview().inset(16)
            make.width.height.equalTo(44)
        }

        contentView.addSubview(playPauseButton)
        playPauseButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(68)
        }

        contentView.addSubview(currentTimeLabel)
        contentView.addSubview(durationLabel)
        contentView.addSubview(progressSlider)

        // 하단 정보(96pt + 여백 8pt) 바로 위 — 높이를 크게 잡아 얇은 트랙도 잡기 쉽게
        progressSlider.snp.makeConstraints { make in
            make.leading.equalTo(currentTimeLabel.snp.trailing).offset(8)
            make.trailing.equalTo(durationLabel.snp.leading).offset(-8)
            make.centerY.equalTo(currentTimeLabel)
            make.height.equalTo(44)
        }
        currentTimeLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.bottom.equalTo(contentView.safeAreaLayoutGuide).offset(-8 - 96 - 16)
        }
        durationLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalTo(currentTimeLabel)
        }

        playPauseButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        progressSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    // MARK: - Configure

    /// poster는 바로 보여줄 정지 프레임, playerItem은 준비되는 대로 비동기로 채운다
    func configure(poster: UIImage?) {
        posterImageView.image = poster
        // 저화질→고화질 두 번 불릴 수 있다 — 이미 재생 중이면 재생 상태는 건드리지 않는다
        guard !isPlaying else { return }
        posterImageView.isHidden = false
        playPauseButton.setImage(UIImage(named: "lucide_play", in: .module, with: nil), for: .normal)
    }

    func setPlayerItem(_ playerItem: AVPlayerItem?) {
        guard let playerItem else { return }
        // 빠르게 넘겼다 돌아오면 두 번 불릴 수 있어서, 이전 옵저버를 먼저 정리해야 덮어쓰며 새지 않는다
        removeTimeObserver()
        removeEndObserver()
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        playerLayer.player = player

        let durationSeconds = CMTimeGetSeconds(playerItem.asset.duration)
        if durationSeconds.isFinite && durationSeconds > 0 {
            durationLabel.text = Self.formatTime(durationSeconds)
            progressSlider.maximumValue = Float(durationSeconds)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self, weak player] _ in
            self?.pause()
            player?.seek(to: .zero)
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.handleTimeUpdate(time)
        }
    }

    private func handleTimeUpdate(_ time: CMTime) {
        guard !isScrubbing else { return }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return }
        currentTimeLabel.text = Self.formatTime(seconds)
        progressSlider.value = Float(seconds)

        // duration이 처음에 비어 있었을 수 있어서 재생 중에도 다시 확인한다
        if progressSlider.maximumValue <= 0, let duration = player?.currentItem?.duration {
            let durationSeconds = CMTimeGetSeconds(duration)
            if durationSeconds.isFinite && durationSeconds > 0 {
                durationLabel.text = Self.formatTime(durationSeconds)
                progressSlider.maximumValue = Float(durationSeconds)
            }
        }
    }

    /// 페이지가 바뀌어 화면 밖으로 나갈 때 호출 — 재생 중이던 영상을 멈춘다
    func pause() {
        player?.rate = 1.0
        player?.pause()
        isPlaying = false
        isFastForwarding = false
        fastForwardBadge.alpha = 0
        playPauseButton.isHidden = false
        playPauseButton.setImage(UIImage(named: "lucide_play", in: .module, with: nil), for: .normal)
    }

    /// 화면 탭에 상단바/하단정보와 같이 숨김 — 숨긴 동안엔 터치를 받지 않는다
    func setControlsHidden(_ hidden: Bool, animated: Bool) {
        let views: [UIView] = [playPauseButton, currentTimeLabel, durationLabel, progressSlider]
        views.forEach { $0.isUserInteractionEnabled = !hidden }
        let alpha: CGFloat = hidden ? 0 : 1
        guard animated else {
            views.forEach { $0.alpha = alpha }
            return
        }
        UIView.animate(withDuration: 0.2) {
            views.forEach { $0.alpha = alpha }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Actions

    @objc private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            pause()
        } else {
            posterImageView.isHidden = true
            player.play()
            isPlaying = true
            playPauseButton.setImage(UIImage(named: "lucide_pause", in: .module, with: nil), for: .normal)
        }
    }

    @objc private func sliderTouchDown() {
        isScrubbing = true
        // 재생 전(포스터가 덮여있는 상태)에 바로 진행바부터 당겨도 실제 프레임이 보이게 한다
        posterImageView.isHidden = true
    }

    @objc private func sliderValueChanged() {
        currentTimeLabel.text = Self.formatTime(Double(progressSlider.value))
    }

    @objc private func sliderTouchUp() {
        isScrubbing = false
        let target = CMTime(seconds: Double(progressSlider.value), preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard isPlaying else { return }
            isFastForwarding = true
            player?.rate = 2.0
            UIView.animate(withDuration: 0.15) { self.fastForwardBadge.alpha = 1 }
        case .ended, .cancelled, .failed:
            guard isFastForwarding else { return }
            isFastForwarding = false
            player?.rate = 1.0
            UIView.animate(withDuration: 0.15) { self.fastForwardBadge.alpha = 0 }
        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension VideoViewerCell: UIGestureRecognizerDelegate {
    /// 재생 버튼/진행바 위에서 시작된 길게 누르기는 2배속 제스처로 안 잡히게 제외한다
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIButton || touch.view is UISlider)
    }
}
