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

    // MARK: - State

    private var player: AVPlayer?
    private var isPlaying = false
    private var endObserver: NSObjectProtocol?

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
        player = nil
        playerLayer.player = nil
        posterImageView.image = nil
        posterImageView.isHidden = false
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

        contentView.addSubview(playPauseButton)
        playPauseButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(68)
        }

        playPauseButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
    }

    // MARK: - Configure

    /// poster는 이 화면에 들어오자마자 보여줄 정지 프레임(기존 이미지 로딩 경로 재사용), playerItem은
    /// 준비되는 대로 비동기로 채워진다 — 재생을 누르기 전까지는 poster만 보인다
    func configure(poster: UIImage?) {
        posterImageView.image = poster
        posterImageView.isHidden = false
        isPlaying = false
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)), for: .normal)
    }

    func setPlayerItem(_ playerItem: AVPlayerItem?) {
        guard let playerItem else { return }
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        playerLayer.player = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
            player.seek(to: .zero)
        }
    }

    /// 페이지가 바뀌어 화면 밖으로 나갈 때 호출 — 재생 중이던 영상을 멈춘다
    func pause() {
        player?.pause()
        isPlaying = false
        playPauseButton.isHidden = false
        playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)), for: .normal)
    }

    /// 상단바/하단정보와 같은 그룹으로 묶여서 화면 탭할 때 같이 사라졌다 나타난다. 숨겨진 동안은
    /// 터치를 안 받게 해서, 숨은 자리를 탭하면 재생/일시정지가 아니라 다시 나타나는 쪽으로 간다.
    func setControlsHidden(_ hidden: Bool, animated: Bool) {
        playPauseButton.isUserInteractionEnabled = !hidden
        let alpha: CGFloat = hidden ? 0 : 1
        guard animated else {
            playPauseButton.alpha = alpha
            return
        }
        UIView.animate(withDuration: 0.2) {
            self.playPauseButton.alpha = alpha
        }
    }

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
}
