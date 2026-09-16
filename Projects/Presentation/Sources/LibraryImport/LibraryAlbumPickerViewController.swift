//
//  LibraryAlbumPickerViewController.swift
//  Presentation
//
//  Created by sanghyeon on 9/15/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Combine
import SnapKit
import Domain

final class LibraryAlbumPickerViewController: BaseViewController {

    private let naviView = NaviBarView()

    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        return tableView
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "가져올 수 있는 앨범이 없어요", bundle: .module)
        label.textColor = Theme.textTertiary
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private let importAllRow = LibraryAlbumPickerImportAllRow()

    private let viewModel: LibraryAlbumPickerViewModel

    private var albums: [AlbumAsset] = []
    private var cancellables = Set<AnyCancellable>()

    override var pageTitle: String? { "사진첩 앨범 불러오기" }

    init(viewModel: LibraryAlbumPickerViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError(Self.fatalMessage)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        binding()

        viewModel.send(.appear)
    }

    private func setupView() {
        naviView.setTitle(String(localized: "사진첩 앨범 불러오기", bundle: .module))
        naviView.addButtons([LeftButton(type: .back)])

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(LibraryAlbumPickerCell.self, forCellReuseIdentifier: LibraryAlbumPickerCell.identifier)

        importAllRow.frame = CGRect(x: 0, y: 0, width: 0, height: 60)
        importAllRow.onTap = { [weak self] in
            self?.viewModel.send(.importAll)
        }
        tableView.tableHeaderView = importAllRow

        view.addSubview(naviView)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        naviView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(naviView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        emptyLabel.snp.makeConstraints { make in
            make.center.equalTo(tableView)
            make.leading.trailing.equalToSuperview().inset(40)
        }
    }

    private func binding() {
        naviView.publisher.sink { [weak self] type in
            guard let self, type == .back else { return }
            self.viewModel.send(.dismiss)
        }
        .store(in: &cancellables)

        viewModel.transform().albums
            .receive(on: DispatchQueue.main)
            .sink { [weak self] albums in
                guard let self else { return }
                self.albums = albums
                self.emptyLabel.isHidden = !albums.isEmpty
                self.tableView.tableHeaderView = albums.isEmpty ? nil : self.importAllRow
                self.tableView.reloadData()
            }
            .store(in: &cancellables)
    }
}

extension LibraryAlbumPickerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        albums.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: LibraryAlbumPickerCell.identifier,
            for: indexPath
        ) as? LibraryAlbumPickerCell else { return UITableViewCell() }
        cell.configure(with: albums[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 60 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.send(.selectAlbum(albums[indexPath.row]))
    }
}

private final class LibraryAlbumPickerCell: UITableViewCell {

    static let identifier = "LibraryAlbumPickerCell"

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Theme.textPrimary
        return label
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = Theme.textTertiary
        return label
    }()

    /// 다음 화면으로 넘어가는 게 아니라 "이 앨범을 가져온다"는 동작이라, 화살표(chevron)
    /// 대신 저장/다운로드 느낌의 트레이 아이콘을 쓴다
    private let importIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "tray.and.arrow.down.fill")
        iv.tintColor = Theme.textTertiary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        contentView.addSubview(nameLabel)
        contentView.addSubview(countLabel)
        contentView.addSubview(importIcon)

        nameLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(countLabel.snp.leading).offset(-8)
        }

        countLabel.snp.makeConstraints { make in
            make.trailing.equalTo(importIcon.snp.leading).offset(-12)
            make.centerY.equalToSuperview()
        }

        importIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with albumAsset: AlbumAsset) {
        nameLabel.text = albumAsset.name
        countLabel.text = String(localized: "\(albumAsset.count)장", bundle: .module)
    }
}

/// 목록 맨 위에 얹는 "전체 가져오기" 행 — 개별 앨범 셀과 똑같은 구조라 UITableViewCell로
/// 만들 수도 있었지만, 재사용 셀 목록에 안 섞이게 tableHeaderView로 별도 배치했다
private final class LibraryAlbumPickerImportAllRow: UIView {

    var onTap: (() -> Void)?

    private let iconBackground: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.primary.withAlphaComponent(0.12)
        view.layer.cornerRadius = 16
        return view
    }()

    private let icon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "tray.full.fill")
        iv.tintColor = Theme.primary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "전체 가져오기", bundle: .module)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = Theme.primary
        return label
    }()

    private let importIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "tray.and.arrow.down.fill")
        iv.tintColor = Theme.primary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let divider: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.strokeSoft
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(iconBackground)
        iconBackground.addSubview(icon)
        addSubview(titleLabel)
        addSubview(importIcon)
        addSubview(divider)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        iconBackground.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
        icon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(16)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconBackground.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
        }
        importIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }
        divider.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.trailing.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() {
        onTap?()
    }
}
