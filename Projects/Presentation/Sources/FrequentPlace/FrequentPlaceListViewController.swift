//
//  FrequentPlaceListViewController.swift
//  Presentation
//
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import Combine
import SnapKit

/// 설정 > 정리 옵션 > 자주가는 동네 — 여행 판정에서 빼는 동네 목록. 행을 탭해 고르면 하단에 수정/삭제 버튼이 나온다
final class FrequentPlaceListViewController: UIViewController {

    var onTapAdd: (() -> Void)?
    var onTapEdit: ((FrequentPlaceRow) -> Void)?
    /// 화면을 완전히 빠져나갔을 때(뒤로가기 버튼/스와이프 모두) — 변경 여부를 넘긴다
    var onFinish: ((_ hasChanges: Bool) -> Void)?

    private let viewModel: FrequentPlaceListViewModel
    private var rows: [FrequentPlaceRow] = []
    private var selectedId: UUID?
    private var cancellables = Set<AnyCancellable>()

    private let naviView = NaviBarView()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.strokeSoft
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        return tableView
    }()

    private let descriptionLabel: UILabel = {
        let lb = UILabel()
        lb.text = String(localized: "여기 있는 동네 근처(20km)에서 찍은 사진은 여행 앨범으로 묶지 않아요", bundle: .module)
        lb.font = .systemFont(ofSize: 13, weight: .regular)
        lb.textColor = Theme.textSecondary
        lb.numberOfLines = 0
        return lb
    }()

    private let emptyLabel: UILabel = {
        let lb = UILabel()
        lb.text = String(localized: "아직 등록된 동네가 없어요\n오른쪽 위 + 버튼으로 추가해보세요", bundle: .module)
        lb.font = .systemFont(ofSize: 15, weight: .regular)
        lb.textColor = Theme.textTertiary
        lb.textAlignment = .center
        lb.numberOfLines = 0
        lb.isHidden = true
        return lb
    }()

    // 앨범 상세 선택모드 하단바와 같은 모양
    private let bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = Theme.background
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.08
        v.layer.shadowOffset = CGSize(width: 0, height: -2)
        v.layer.shadowRadius = 8
        v.isHidden = true
        return v
    }()

    private let editButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(named: "lucide_pencil_line", in: .module, with: nil)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.cornerStyle = .medium
        return UIButton(configuration: config)
    }()

    private let deleteButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(named: "lucide_trash_2", in: .module, with: nil)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.negative
        config.cornerStyle = .medium
        return UIButton(configuration: config)
    }()

    init(viewModel: FrequentPlaceListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bind()
        Task { await viewModel.load() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent {
            onFinish?(viewModel.hasChanges)
        }
    }

    private func setupUI() {
        view.backgroundColor = Theme.background
        naviView.setTitle(String(localized: "자주가는 동네", bundle: .module))
        naviView.addButtons([LeftButton(type: .back), RightButton(type: .add)])

        view.addSubview(descriptionLabel)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(bottomBar)
        bottomBar.addSubview(editButton)
        bottomBar.addSubview(deleteButton)
        view.addSubview(naviView)

        naviView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        descriptionLabel.snp.makeConstraints { make in
            make.top.equalTo(naviView.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(descriptionLabel.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }
        // 하단바가 떠도 마지막 행이 가려지지 않게
        tableView.contentInset.bottom = 88
        emptyLabel.snp.makeConstraints { make in
            make.center.equalTo(tableView)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        bottomBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(88)
        }
        editButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.centerY.equalToSuperview().offset(-10)
            make.size.equalTo(44)
        }
        deleteButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalTo(editButton)
            make.size.equalTo(44)
        }

        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }

    private func bind() {
        naviView.publisher
            .sink { [weak self] type in
                switch type {
                case .back: self?.navigationController?.popViewController(animated: true)
                case .add: self?.onTapAdd?()
                default: break
                }
            }
            .store(in: &cancellables)

        viewModel.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                guard let self else { return }
                self.rows = rows
                if let selectedId = self.selectedId, !rows.contains(where: { $0.id == selectedId }) {
                    self.selectedId = nil
                }
                self.emptyLabel.isHidden = !rows.isEmpty
                self.tableView.reloadData()
                self.updateBottomBar()
            }
            .store(in: &cancellables)
    }

    private func updateBottomBar() {
        bottomBar.isHidden = selectedId == nil
    }

    @objc private func editTapped() {
        guard let row = rows.first(where: { $0.id == selectedId }) else { return }
        onTapEdit?(row)
    }

    @objc private func deleteTapped() {
        guard let row = rows.first(where: { $0.id == selectedId }) else { return }
        viewModel.confirmDelete(row) { [weak self] in
            self?.selectedId = nil
            self?.updateBottomBar()
        }
    }
}

extension FrequentPlaceListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = rows[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.textProperties.color = Theme.textPrimary
        content.secondaryText = row.address
        content.secondaryTextProperties.font = .systemFont(ofSize: 14, weight: .regular)
        content.secondaryTextProperties.color = Theme.textSecondary
        content.secondaryTextProperties.numberOfLines = 0
        content.textToSecondaryTextVerticalPadding = 4
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        cell.contentConfiguration = content
        cell.backgroundColor = row.id == selectedId ? Theme.surfaceWarm : Theme.background
        cell.selectionStyle = .none
        return cell
    }

    // 같은 행을 다시 탭하면 선택 해제
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = rows[indexPath.row].id
        selectedId = selectedId == id ? nil : id
        tableView.reloadData()
        updateBottomBar()
    }
}
