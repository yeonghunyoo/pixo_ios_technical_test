import Photos
import PhotosUI
import UIKit
import CoreData

// MARK: - PhotoCollectionViewController

class PhotoItem: NSObject {
    var model: PhotoAsset
    var thumbnail: UIImage?
    
    init(model: PhotoAsset, thumbnail: UIImage? = nil) {
        self.model = model
        self.thumbnail = thumbnail
    }
}

class PhotoCollectionViewController: UIViewController {
    enum Section {
        case main
    }
    
    typealias Item = PhotoItem
    
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    
    private let coreDataManager = CoreDataManager.shared
    private let imageManager = PHCachingImageManager()
    
    private var currentColumnCount: CGFloat = 9.0
    private let possibleColumnCounts: [CGFloat] = [1.0, 3.0, 5.0, 7.0, 9.0, 11.0, 13.0, 15.0, 17.0, 19.0, 21.0]

    private var cumulativeScale: CGFloat = 1.0
    private var lastChangeTime: TimeInterval = 0
    private var velocityHistory: [CGFloat] = []

    private weak var progressAlert: UIAlertController?
    private var importTask: Task<Void, Error>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        setupCollectionView()
        setupDataSource()
        setupNavigationBar()
        setupPinchGesture()
        loadPhotoAssets()
    }
    
    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let spacing: CGFloat = 0
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        collectionView.collectionViewLayout = layout
        collectionView.delegate = self
        collectionView.register(PhotoCollectionViewCell.self, forCellWithReuseIdentifier: "PhotoCell")

        collectionView.showsVerticalScrollIndicator = true
        collectionView.showsHorizontalScrollIndicator = false
        
        collectionView.indicatorStyle = .default  // .default, .black, .white
        
        if #available(iOS 13.0, *) {
            collectionView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
        }

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            (collectionView: UICollectionView, indexPath: IndexPath, photoAsset: Item) -> UICollectionViewCell? in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PhotoCell", for: indexPath) as! PhotoCollectionViewCell
            cell.configure(with: photoAsset, imageManager: self.imageManager, currentColumnCount: self.currentColumnCount)
            return cell
        }
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonTapped))
    }
    
    private func setupPinchGesture() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        collectionView.addGestureRecognizer(pinchGesture)
    }
    
    @objc private func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            resetPinchState()
            
        case .changed:
            let previousColumnCount = currentColumnCount
            updateVelocityHistory(with: abs(gesture.velocity))
            cumulativeScale *= gesture.scale
            
            if shouldProcessPinchChange() {
                processColumnChange()
            }
            
            if previousColumnCount != currentColumnCount {
                updateLayoutAndImages()
            }
            gesture.scale = 1.0
            
        case .ended, .cancelled:
            resetPinchState()
            
        default:
            break
        }
    }

    // MARK: - Pinch Gesture Helpers
    
    private func resetPinchState() {
        cumulativeScale = 1.0
        velocityHistory.removeAll()
    }
    
    private func updateVelocityHistory(with velocity: CGFloat) {
        velocityHistory.append(velocity)
        if velocityHistory.count > 5 { 
            velocityHistory.removeFirst() 
        }
    }
    
    private func shouldProcessPinchChange() -> Bool {
        let now = CACurrentMediaTime()
        let avgVelocity = velocityHistory.reduce(0, +) / CGFloat(velocityHistory.count)
        let (_, interval) = calculateDynamicParameters(velocity: avgVelocity)
        return now - lastChangeTime > interval
    }
    
    private func processColumnChange() {
        let avgVelocity = velocityHistory.reduce(0, +) / CGFloat(velocityHistory.count)
        let (threshold, _) = calculateDynamicParameters(velocity: avgVelocity)
        let stepsToChange = calculateStepsToChange(for: avgVelocity)
        
        if cumulativeScale > (1.0 + threshold) {
            changeColumnCount(direction: -stepsToChange)
            resetColumnChangeState()
        } else if cumulativeScale < (1.0 - threshold) {
            changeColumnCount(direction: stepsToChange)
            resetColumnChangeState()
        }
    }
    
    private func calculateStepsToChange(for velocity: CGFloat) -> Int {
        if velocity > 8.0 { return 3 }
        if velocity > 5.0 { return 2 }
        return 1
    }
    
    private func resetColumnChangeState() {
        cumulativeScale = 1.0
        lastChangeTime = CACurrentMediaTime()
    }
    
    private func calculateDynamicParameters(velocity: CGFloat) -> (threshold: CGFloat, interval: TimeInterval) {
        switch velocity {
        case 0..<2.0: return (0.15, 0.4)
        case 2.0..<4.0: return (0.12, 0.25)
        case 4.0..<7.0: return (0.08, 0.15)
        default: return (0.05, 0.08)
        }
    }

    private func changeColumnCount(direction: Int) {
        guard let currentIndex = possibleColumnCounts.firstIndex(of: currentColumnCount) else { return }
        let newIndex = currentIndex + direction
        guard newIndex >= 0 && newIndex < possibleColumnCounts.count else { return }
        
        currentColumnCount = possibleColumnCounts[newIndex]
    }

    private func updateLayoutAndImages() {
        print("updateLayoutAndImages")
        
        UIView.animate(withDuration: 0.3) {
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.reconfigureVisibleCells()
        }
    }

    private func reconfigureVisibleCells() {
        if (currentColumnCount >= 5.0) { return }
        
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        for indexPath in visibleIndexPaths {
            if let item = dataSource.itemIdentifier(for: indexPath) {
                item.thumbnail = nil
            }
        }
        
        let visibleItems = visibleIndexPaths.compactMap { dataSource.itemIdentifier(for: $0) }
        if !visibleItems.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                var snapshot = self.dataSource.snapshot()
                snapshot.reconfigureItems(visibleItems)
                
                // 메인 스레드에서 적용
                DispatchQueue.main.async {
                    self.dataSource.apply(snapshot, animatingDifferences: false)
                }
            }
        }
    }
    
    private func loadPhotoAssets() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }

        let photoAssets = coreDataManager.fetchPhotoAssets()
        
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(photoAssets.map({ .init(model: $0) }))
        
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    @objc private func addButtonTapped() {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos, .livePhotos])
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension PhotoCollectionViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let availableWidth = collectionView.frame.inset(by: collectionView.contentInset).width
        let width = availableWidth / currentColumnCount
        
        // 부동소수점 오차로 인한 오버플로우 방지
        let totalWidth = width * currentColumnCount
        if totalWidth > availableWidth {
            let adjustedWidth = floor(width * 1000) / 1000
            return CGSize(width: adjustedWidth, height: adjustedWidth)
        }
        
        return CGSize(width: width, height: width)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let photoAsset = dataSource.itemIdentifier(for: indexPath) else { return }
        let detailVC = PhotoDetailViewController(photoAsset: photoAsset.model)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.reconfigureVisibleCells()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // 관성 스크롤도중 드래깅시 감속과 드래깅 End함수가 함께 호출되므로 체크
        if (!scrollView.isDecelerating) {
            self.reconfigureVisibleCells()
        }
    }
    
}

// MARK: - PHPickerViewControllerDelegate

extension PhotoCollectionViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        
        importTask = Task.detached { [weak self] in
            await self?.fetchPhotosInBackground(results)
        }
    }

    private func fetchPhotosInBackground(_ results: [PHPickerResult]) async {
        let totalCount = results.count
        var collectedAssets: [PHAsset] = []  // 🔧 PHAsset만 수집
        
        showProgressDialog(total: totalCount)
        
        // 🎯 1단계: PHAsset들만 수집 (CoreData 저장 안함)
        for (currentIndex, result) in results.enumerated() {
 
            guard let identifier = result.assetIdentifier else { return }

            let result = await Task.detached {
                let fetchedAssets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                return fetchedAssets.firstObject
            }.value
            guard let asset = result else { return }
            collectedAssets.append(asset)
            updateProgress(current: currentIndex + 1, total: totalCount)
        }
        
        if !Task.isCancelled && !collectedAssets.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.saveBatchToCoreData(assets: collectedAssets)
            }
        } 
    }

    private func saveBatchToCoreData(assets: [PHAsset]) {
        dismissProgressDialog()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Task {
                if !(self.importTask?.isCancelled ?? true) {
                    let photoAssets = await self.coreDataManager.createPhotoAssetsBatch(from: assets)
                    await MainActor.run {
                        self.addPhotosToGallery(photoAssets)
                    }
                }
            }
        }
    }

    // MARK: - UI Updates

    @MainActor
    private func replaceWithCompleteButton() {
         guard let alert = progressAlert else { return }
        
        // 제목과 메시지 변경
        alert.title = "완료"
        alert.message = "사진이 성공적으로 추가되었습니다"
        
        // 기존 액션들 수정
        alert.actions.forEach { action in
            if action.title == "취소" {
                // 취소 버튼을 완료 버튼으로 변경
                action.setValue("완료", forKey: "title")
                action.setValue(UIAlertAction.Style.default.rawValue, forKey: "style")
            }
        }
    }

    private func addPhotosToGallery(_ photos: [PhotoAsset]) {
        guard !photos.isEmpty else { return }
        
        var gallerySnapshot = dataSource.snapshot()
        let photoItems = photos.map { PhotoItem(model: $0) }
        
        gallerySnapshot.appendItems(photoItems, toSection: .main)
        dataSource.apply(gallerySnapshot, animatingDifferences: true) {
//            self.replaceWithCompleteButton(
        }
    }

    @MainActor
    private func showProgressDialog(total: Int) {
        let alert = UIAlertController(
            title: "사진 가져오는 중",
            message: createProgressMessage(current: 0, total: total),
            preferredStyle: .alert
        )
        
        let cancelButton = UIAlertAction(title: "취소", style: .cancel) { _ in
            self.cancelImport()
        }
        
        alert.addAction(cancelButton)
        progressAlert = alert
        
        present(progressAlert!, animated: true)
    }

    @MainActor
    private func updateProgress(current: Int, total: Int) {
        progressAlert?.message = createProgressMessage(current: current, total: total)
    }

   @MainActor
    private func dismissProgressDialog(completion: (() -> Void)? = nil) {
        self.progressAlert?.dismiss(animated: true, completion: completion)
        self.progressAlert = nil
    }

    // MARK: - Helper Methods
    private func createProgressMessage(current: Int, total: Int) -> String {
        let percentage = total > 0 ? Int((Double(current) / Double(total)) * 100) : 0
        return "\(current) / \(total) (\(percentage)%)"
    }

    @MainActor
    private func fetchPhotosCancelled() {
        dismissProgressDialog()
        
        let alert = UIAlertController(
            title: "취소됨",
            message: "사진 가져오기가 취소되었습니다.\n아무것도 저장되지 않았습니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func cancelImport() {
        print("cancelImport \(importTask)")
        importTask?.cancel()
        // importTask = nil
    }
}

// MARK: - PhotoCollectionViewCell

class PhotoCollectionViewCell: UICollectionViewCell {
    private var configureTask: Task<Void, Never>?

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()
    
    private let videoIndicator: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "video.fill"))
        imageView.tintColor = .white
        imageView.isHidden = true
        return imageView
    }()
    
    private let livePhotoIndicator: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "livephoto"))
        imageView.tintColor = .white
        imageView.isHidden = true
        return imageView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        configureTask?.cancel()
        imageView.image = nil
        videoIndicator.isHidden = true
        livePhotoIndicator.isHidden = true
    }
    
    private func setupViews() {
        contentView.addSubview(imageView)
        contentView.addSubview(videoIndicator)
        contentView.addSubview(livePhotoIndicator)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        videoIndicator.translatesAutoresizingMaskIntoConstraints = false
        livePhotoIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            videoIndicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            videoIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            
            livePhotoIndicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            livePhotoIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5)
        ])
    }
    
    func configure(with photoAsset: PhotoItem, imageManager: PHCachingImageManager, currentColumnCount: CGFloat) {
        configureTask?.cancel()

        if let thumbnail = photoAsset.thumbnail {
            self.imageView.image = thumbnail
            setMediaType(with: photoAsset, columnCount: currentColumnCount)
        } else {
            let cellBounds = self.bounds
            let screenScale = UIScreen.main.scale
            
            configureTask = Task {
                
                let result = await Task.detached(priority: .userInitiated) {
                    PHAsset.fetchAssets(
                        withLocalIdentifiers: [photoAsset.model.identifier!], 
                        options: nil
                    ).firstObject
                }.value
                
                guard let asset = result else { return }
                
                let size = CGSize(width: cellBounds.width, height: cellBounds.width)
                    .applying(.init(scaleX: screenScale, y: screenScale))
                
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isSynchronous = false
                options.isNetworkAccessAllowed = true

                let image = await withCheckedContinuation { continuation in
                    imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
                        continuation.resume(returning: image)
                    }
                }
                
                // 셀 스크롤시 재사용셀에서 이전 Task가 이미지를 동시에 할당하면 안되므로 취소 확인
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.imageView.image = image
                    photoAsset.thumbnail = image
                    self.setMediaType(with: photoAsset, columnCount: currentColumnCount)
                }
            }
        }
    }
    
    func setMediaType(with photoAsset: PhotoItem, columnCount: CGFloat) {
        let mediaType = PHAssetMediaType(rawValue: Int(photoAsset.model.mediaType)) ?? .unknown
        switch mediaType {
        case .video:
            videoIndicator.isHidden = false
        case .image:
            let mediaSubTypes = PHAssetMediaSubtype(rawValue: UInt(photoAsset.model.mediaSubTypes))
            if mediaSubTypes.contains(.photoLive) {
                livePhotoIndicator.isHidden = false
            }
        default:
            break
        }
    }
}

