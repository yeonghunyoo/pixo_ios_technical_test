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
    
    private let imageManager = PHCachingImageManager()
    private let coreDataManager = CoreDataManager.shared
    
    private var currentColumnCount: CGFloat = 9.0
    private let possibleColumnCounts: [CGFloat] = [1.0, 3.0, 5.0, 7.0, 9.0, 11.0, 13.0, 15.0, 17.0, 19.0, 21.0]
    
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
            cell.configure(with: photoAsset, imageManager: self.imageManager)
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
        if gesture.state == .changed {
            let scale = gesture.scale
            if scale > 1.1 {
                if let index = possibleColumnCounts.firstIndex(of: currentColumnCount),
                   index > 0 {
                    currentColumnCount = possibleColumnCounts[index - 1]
                }
            } else if scale < 0.9 {
                if let index = possibleColumnCounts.firstIndex(of: currentColumnCount),
                   index < possibleColumnCounts.count - 1 {
                    currentColumnCount = possibleColumnCounts[index + 1]
                }
            }
            
            UIView.animate(withDuration: 0.3) {
                self.collectionView.collectionViewLayout.invalidateLayout()
            }
            
            gesture.scale = 1.0
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
        let width = collectionView.frame.inset(by: collectionView.contentInset).width / currentColumnCount
        let height = width
        return CGSize(width: width, height: height)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard let photoAsset = dataSource.itemIdentifier(for: indexPath) else { return }
        let detailVC = PhotoDetailViewController(photoAsset: photoAsset.model)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension PhotoCollectionViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        
        for result in results {
            guard let assetIdentifier = result.assetIdentifier else { continue }
            
            let assetResults = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = assetResults.firstObject else { continue }
            
            let photoAsset = coreDataManager.createPhotoAsset(
                identifier: asset.localIdentifier,
                creationDate: Date(),
                mediaType: asset.mediaType
            )
            
            var snapshot = dataSource.snapshot()
            snapshot.appendItems([.init(model: photoAsset)], toSection: .main)
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }
}

// MARK: - PhotoCollectionViewCell

class PhotoCollectionViewCell: UICollectionViewCell {
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
    
    func configure(with photoAsset: PhotoItem, imageManager: PHImageManager) {
        if let thumbnail = photoAsset.thumbnail {
            self.imageView.image = thumbnail
        } else {
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photoAsset.model.identifier!], options: nil).firstObject
            
            if let asset = asset {
                let size = CGSize(width: self.bounds.width, height: self.bounds.width)
                    .applying(.init(scaleX: UIScreen.main.scale, y: UIScreen.main.scale))
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isSynchronous = false
                options.isNetworkAccessAllowed = true
                
                Task {
                    let image = await withCheckedContinuation { continuation in
                        PHCachingImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                            continuation.resume(returning: image)
                        }
                    }
                    self.imageView.image = image
                    photoAsset.thumbnail = image
                }
                
                
                let mediaType = PHAssetMediaType(rawValue: Int(photoAsset.model.mediaType)) ?? .unknown
                switch mediaType {
                case .video:
                    videoIndicator.isHidden = false
                case .image:
                    if asset.mediaSubtypes.contains(.photoLive) {
                        livePhotoIndicator.isHidden = false
                    }
                default:
                    break
                }
            }
        }
    }
}
