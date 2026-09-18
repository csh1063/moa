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

/// 상세화면에서 영상(PHAssetMediaType.video)을 실제로 재생하는 셀. 그리드/썸네일은 정지 프레임으로
/// 충분해서 여전히 PhotoCell 등 기존 이미지 경로를 그대로 쓰고, 여기 상세화면에서만 AVPlayer로 재생한다.
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
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        btn.tintColor = .white
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
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        let thumb = UIImage(systemName: "circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10))
        slider.setThumbImage(thumb, for: .normal)
        slider.tintColor = .white
        return slider
    }()

    // MARK: - State

    /// 재사용 도중 뒤늦게 도착하는 포스터 콜백이 이미 다른 사진으로 바뀐 셀에 잘못 그려지는 걸
    /// 막기 위한 식별자 — 호출부(ImageViewerViewController)가 콜백마다 비교한다
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

        // 화면 전체가 아니라 좌/우 가장자리 40pt 폭에서만 길게 눌러야 2배속이 걸리게, 그 폭만큼의
        // 안 보이는 뷰 두 개에만 제스처를 붙인다 (가운데를 길게 눌러도 아무 반응 없음)
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
        // 가운데 대신 우측 상단 — 상단 네비게이션 바(topBarView, 높이 100pt)와 안 겹치게 그 바로 아래
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

        // 하단정보(ImageViewerViewController.bottomInfoView, 높이 96pt + 아래쪽 여백 8pt)와
        // 안 겹치게 그 바로 위에 둔다. 높이를 실제 트랙(가는 선)보다 훨씬 크게 잡아서 — UISlider는
        // 보이는 트랙 두께와 무관하게 자기 bounds 전체로 터치를 받으므로, 시각적으론 그대로 얇고
        // 손가락으로 잡기는 훨씬 쉬워진다
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

    /// poster는 이 화면에 들어오자마자 보여줄 정지 프레임(기존 이미지 로딩 경로 재사용), playerItem은
    /// 준비되는 대로 비동기로 채워진다 — 재생을 누르기 전까지는 poster만 보인다
    func configure(poster: UIImage?) {
        posterImageView.image = poster
        // 저화질→고화질 두 번 불릴 수 있는데, 그 사이에 사용자가 이미 재생을 눌렀다면 이미지만
        // 갱신하고(화면엔 안 보이지만) 재생 상태는 건드리지 않는다
        guard !isPlaying else { return }
        posterImageView.isHidden = false
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)), for: .normal)
    }

    func setPlayerItem(_ playerItem: AVPlayerItem?) {
        guard let playerItem else { return }
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
        ) { [weak self] _ in
            self?.pause()
            player.seek(to: .zero)
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

        // 로컬 파일이라 보통 setPlayerItem 시점에 duration을 바로 알 수 있지만, 혹시 그때
        // 아직 안 채워졌던 경우를 대비해 재생되는 동안에도 계속 다시 확인한다
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
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)), for: .normal)
    }

    /// 상단바/하단정보와 같은 그룹으로 묶여서 화면 탭할 때 같이 사라졌다 나타난다. 숨겨진 동안은
    /// 터치를 안 받게 해서, 숨은 자리를 탭하면 재생/일시정지가 아니라 다시 나타나는 쪽으로 간다.
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
            playPauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)), for: .normal)
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
