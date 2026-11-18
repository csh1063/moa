//
//  TravelerManagementSheet.swift
//  Presentation
//
//  Created by sanghyeon on 7/12/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import UIKit
import SnapKit
import Domain

/// 여행 동행자 관리 — "여행자"/"인물 앨범" 두 섹션, 사진 탭으로 이동, 이름은 즉시 저장, "저장"으로 여행자 확정
final class TravelerManagementSheet: UIViewController {

    // MARK: - Properties

    private var travelers: [Album]
    private var others: [Album]
    private let imageUseCase: PhotoImageUseCase
    private let albumUseCase: AlbumUseCase
    private let detailUseCase: AlbumDetailUseCase

    var onConfirm: (([UUID]) -> Void)?

    // MARK: - UI

    private let grabberView: UIView = {
        let v = UIView()
        v.backgroundColor = Theme.strokeSoft
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let titleLabel: UILabel = {
        let lb = UILabel()
        lb.text = String(localized: "여행자 관리", bundle: .module)
        lb.font = .systemFont(ofSize: 20, weight: .bold)
        lb.textColor = Theme.textPrimary
        return lb
    }()

    private let subtitleLabel: UILabel = {
        let lb = UILabel()
        lb.text = String(localized: "사진을 탭하면 여행자로 넣거나 뺄 수 있어요", bundle: .module)
        lb.font = .systemFont(ofSize: 14, weight: .regular)
        lb.textColor = Theme.textSecondary
        lb.numberOfLines = 0
        return lb
    }()

    private let confirmButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "저장", bundle: .module)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = Theme.primary
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        return btn
    }()

    private lazy var collectionView: UICollectionView = {
        let space: CGFloat = 12
        let count: CGFloat = 3
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = UIEdgeInsets(top: 4, left: 20, bottom: 20, right: 20)
        layout.minimumLineSpacing = space
        layout.minimumInteritemSpacing = space
        let width = (UIScreen.main.bounds.width - 40 - (space * (count - 1))) / count
        layout.itemSize = CGSize(width: width, height: width + 24)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.register(TravelerManagementCell.self, forCellWithReuseIdentifier: TravelerManagementCell.reuseIdentifier)
        cv.register(
            TravelerSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: TravelerSectionHeaderView.reuseIdentifier
        )
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    // MARK: - Init

    init(travelers: [Album], others: [Album], imageUseCase: PhotoImageUseCase, albumUseCase: AlbumUseCase, detailUseCase: AlbumDetailUseCase) {
        self.travelers = travelers
        self.others = others
        self.imageUseCase = imageUseCase
        self.albumUseCase = albumUseCase
        self.detailUseCase = detailUseCase
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("TravelerManagementSheet does not support NSCoding.")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface
        setupLayout()
    }

    // MARK: - Setup

    private func setupLayout() {
        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4

        view.addSubview(grabberView)
        view.addSubview(headerStack)
        view.addSubview(collectionView)
        view.addSubview(confirmButton)

        grabberView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.centerX.equalToSuperview()
            make.width.equalTo(42)
            make.height.equalTo(5)
        }
        headerStack.snp.makeConstraints { make in
            make.top.equalTo(grabberView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(headerStack.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(confirmButton.snp.top).offset(-12)
        }
        confirmButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(32)
            make.height.equalTo(52)
        }

        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func confirmTapped() {
        let ids = travelers.map { $0.id }
        dismiss(animated: true) { [weak self] in self?.onConfirm?(ids) }
    }

    // MARK: - Section move

    // 셀 하나만 옮기는 애니메이션으로 깜빡임을 없앤다
    private func moveToTravelers(from indexPath: IndexPath) {
        guard others.indices.contains(indexPath.item) else { return }
        let person = others.remove(at: indexPath.item)
        travelers.append(person)

        let destination = IndexPath(item: travelers.count - 1, section: 0)
        collectionView.performBatchUpdates {
            collectionView.deleteItems(at: [indexPath])
            collectionView.insertItems(at: [destination])
        }
    }

    private func moveToOthers(from indexPath: IndexPath) {
        guard travelers.indices.contains(indexPath.item) else { return }
        let person = travelers.remove(at: indexPath.item)
        // 방금 뺀 사람이 "인물 앨범" 목록에서 바로 눈에 띄도록 맨 뒤가 아니라 맨 앞에 붙인다
        others.insert(person, at: 0)

        let destination = IndexPath(item: 0, section: 1)
        collectionView.performBatchUpdates {
            collectionView.deleteItems(at: [indexPath])
            collectionView.insertItems(at: [destination])
        }
    }

    // MARK: - Rename

    private func presentRename(for person: Album, section: Int, index: Int) {
        let renameSheet = AlbumRenameSheet(
            albumName: person.isRenamed ? person.displayName : "",
            title: String(localized: "이름 변경", bundle: .module),
            subtitle: String(localized: "이름을 정해주세요", bundle: .module)
        )
        renameSheet.onSave = { [weak self] newName in
            guard let self, !newName.isEmpty else { return }
            Task {
                try? await self.detailUseCase.editAlbumName(new: newName, id: person.id)
                if section == 0, self.travelers.indices.contains(index) {
                    self.travelers[index].displayName = newName
                    self.travelers[index].isRenamed = true
                } else if section == 1, self.others.indices.contains(index) {
                    self.others[index].displayName = newName
                    self.others[index].isRenamed = true
                }
                // 이름 바뀐 셀 하나만 갱신 — reloadData()로 전체를 다시 그리면 깜빡인다
                self.collectionView.reloadItems(at: [IndexPath(item: index, section: section)])
            }
        }

        if let presentation = renameSheet.sheetPresentationController {
            presentation.detents = [.custom { _ in 260 }]
            presentation.preferredCornerRadius = 28
        }

        present(renameSheet, animated: true)
    }
}

// MARK: - UICollectionViewDataSource

extension TravelerManagementSheet: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? travelers.count : others.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TravelerManagementCell.reuseIdentifier, for: indexPath
        ) as? TravelerManagementCell else {
            return UICollectionViewCell()
        }

        let person = indexPath.section == 0 ? travelers[indexPath.item] : others[indexPath.item]
        cell.configure(
            with: person,
            name: person.displayName,
            isRenamed: person.isRenamed,
            imageUseCase: imageUseCase,
            albumUseCase: albumUseCase
        )

        cell.onTapPhoto = { [weak self] in
            guard let self else { return }
            if indexPath.section == 0 {
                self.moveToOthers(from: indexPath)
            } else {
                self.moveToTravelers(from: indexPath)
            }
        }
        cell.onTapRename = { [weak self] in
            self?.presentRename(for: person, section: indexPath.section, index: indexPath.item)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: TravelerSectionHeaderView.reuseIdentifier,
                for: indexPath
              ) as? TravelerSectionHeaderView else {
            return UICollectionReusableView()
        }
        header.configure(title: indexPath.section == 0 ? String(localized: "여행자", bundle: .module) : String(localized: "후보", bundle: .module))
        return header
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension TravelerManagementSheet: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: 32)
    }
}

// MARK: - TravelerSectionHeaderView

private final class TravelerSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "TravelerSectionHeaderView"

    private let titleLabel: UILabel = {
        let lb = UILabel()
        lb.font = .systemFont(ofSize: 15, weight: .bold)
        lb.textColor = Theme.textPrimary
        return lb
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.bottom.equalToSuperview().offset(-6)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        titleLabel.text = title
    }
}

// MARK: - TravelerManagementCell

private final class TravelerManagementCell: UICollectionViewCell {
    static let reuseIdentifier = "TravelerManagementCell"

    // 여행자 후보 풀에 사람/동물 앨범이 섞여 있어서, 두 크롭 뷰를 겹쳐두고 종에 맞는 쪽만 보여준다
    private let faceCellView = FaceCellView()
    private let animalCellView = AnimalCellView()
    private let nameRow = UIView()

    private let nameLabel: UILabel = {
        let lb = UILabel()
        lb.font = .systemFont(ofSize: 12, weight: .medium)
        return lb
    }()

    private let penIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(named: "lucide_pencil", in: .module, with: nil)?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = Theme.textTertiary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    var onTapPhoto: (() -> Void)?
    var onTapRename: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        faceCellView.prepareForReuse()
        animalCellView.prepareForReuse()
        onTapPhoto = nil
        onTapRename = nil
    }

    func configure(with person: Album, name: String, isRenamed: Bool, imageUseCase: PhotoImageUseCase, albumUseCase: AlbumUseCase) {
        let isAnimal = person.from == "animal"
        faceCellView.isHidden = isAnimal
        animalCellView.isHidden = !isAnimal

        if isAnimal {
            let viewModel = AnimalCellViewModel(
                albumId: person.id,
                photoId: person.coverPhotoIdentifier ?? "",
                imageUseCase: imageUseCase,
                albumUseCase: albumUseCase
            )
            animalCellView.configure(with: viewModel)
        } else {
            let viewModel = FaceCellViewModel(
                albumId: person.id,
                photoId: person.coverPhotoIdentifier ?? "",
                imageUseCase: imageUseCase,
                albumUseCase: albumUseCase
            )
            faceCellView.configure(with: viewModel)
        }

        nameLabel.text = isRenamed ? name : String(localized: "미정", bundle: .module)
        nameLabel.textColor = isRenamed ? Theme.textPrimary : Theme.textTertiary
    }

    private func setupLayout() {
        faceCellView.layer.cornerRadius = 14
        faceCellView.layer.masksToBounds = true
        faceCellView.isUserInteractionEnabled = true

        animalCellView.layer.cornerRadius = 14
        animalCellView.layer.masksToBounds = true
        animalCellView.isUserInteractionEnabled = true

        contentView.addSubview(faceCellView)
        contentView.addSubview(animalCellView)
        contentView.addSubview(nameRow)
        nameRow.addSubview(nameLabel)
        nameRow.addSubview(penIcon)

        faceCellView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(faceCellView.snp.width)
        }
        animalCellView.snp.makeConstraints { make in
            make.edges.equalTo(faceCellView)
        }
        nameRow.snp.makeConstraints { make in
            make.top.equalTo(faceCellView.snp.bottom).offset(4)
            make.leading.trailing.bottom.equalToSuperview()
        }
        nameLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(penIcon.snp.leading).offset(-4)
        }
        penIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }

        faceCellView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handlePhotoTap)))
        animalCellView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handlePhotoTap)))

        nameRow.isUserInteractionEnabled = true
        let renameTap = UITapGestureRecognizer(target: self, action: #selector(handleRenameTap))
        nameRow.addGestureRecognizer(renameTap)
    }

    @objc private func handlePhotoTap() { onTapPhoto?() }
    @objc private func handleRenameTap() { onTapRename?() }
}
