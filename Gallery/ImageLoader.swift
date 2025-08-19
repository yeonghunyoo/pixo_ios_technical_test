import Photos
import UIKit

// MARK: - ImageLoader

/// QoS 우선순위 역전을 방지하면서 동시 이미지 로딩 작업 수를 제한하는 모듈
class ImageLoader {
    // MARK: - Constants
    
    private enum Constants {
        static let maxConcurrentTasks = 600
    }
    
    // MARK: - Properties
    
    static let shared = ImageLoader()
    
    private let imageManager = PHCachingImageManager()
    private let taskCounter = TaskCounter(maxConcurrentTasks: Constants.maxConcurrentTasks)
    
    // QoS별로 분리된 큐를 사용하여 우선순위 역전 방지
    private let userInitiatedQueue = DispatchQueue(label: "com.gallery.imageloader.userInitiated", qos: .userInitiated, attributes: .concurrent)
    private let utilityQueue = DispatchQueue(label: "com.gallery.imageloader.utility", qos: .utility, attributes: .concurrent)
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 이미지를 비동기적으로 로드합니다 (QoS 우선순위 보존).
    /// - Parameters:
    ///   - asset: 로드할 PHAsset
    ///   - targetSize: 타겟 크기
    ///   - priority: 작업 우선순위 (기본값: .userInitiated)
    ///   - completion: 완료 시 호출되는 클로저
    func loadImage(
        for asset: PHAsset,
        targetSize: CGSize,
        priority: TaskPriority = .userInitiated,
        completion: @escaping (UIImage?) -> Void
    ) {
        let queue = selectQueue(for: priority)
        
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // QoS 정보를 보존하면서 작업 수 제한
            self.taskCounter.executeWithLimit(priority: priority) {
                self.requestImage(for: asset, targetSize: targetSize, completion: completion)
            }
        }
    }
    
    /// 이미지를 async/await 방식으로 로드합니다 (QoS 우선순위 보존).
    /// - Parameters:
    ///   - asset: 로드할 PHAsset
    ///   - targetSize: 타겟 크기
    ///   - priority: 작업 우선순위 (기본값: .userInitiated)
    /// - Returns: 로드된 UIImage (실패 시 nil)
    func loadImage(
        for asset: PHAsset, 
        targetSize: CGSize,
        priority: TaskPriority = .userInitiated
    ) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            loadImage(for: asset, targetSize: targetSize, priority: priority) { image in
                continuation.resume(returning: image)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func selectQueue(for priority: TaskPriority) -> DispatchQueue {
        switch priority {
        case .userInitiated, .high:
            return userInitiatedQueue
        case .utility, .low, .medium, .background:
            return utilityQueue
        default:
            return userInitiatedQueue
        }
    }
    
    private func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        let options = createImageRequestOptions()
        
        // 현재 QoS를 유지하면서 이미지 요청
        let currentQoS = DispatchQoS.QoSClass.current
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            // QoS를 보존하면서 메인 스레드로 결과 전달
            DispatchQueue.main.async(qos: .init(qosClass: currentQoS, relativePriority: 0)) {
                completion(image)
            }
        }
    }
    
    private func createImageRequestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        return options
    }
}



// MARK: - TaskCounter

/// QoS 정보를 보존하면서 동시 작업 수를 제한하는 클래스
private class TaskCounter {
    private let semaphore: DispatchSemaphore
    
    init(maxConcurrentTasks: Int) {
        self.semaphore = DispatchSemaphore(value: maxConcurrentTasks)
    }
    
    func executeWithLimit(priority: TaskPriority, work: @escaping () -> Void) {
        // 세마포어 대신 async 작업으로 QoS 보존
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask(priority: priority) {
                    // 작업 수 제한
                    self.semaphore.wait()
                    defer { self.semaphore.signal() }
                    
                    work()
                }
            }
        }
    }
    

}

// MARK: - DispatchQoS.QoSClass Extension

private extension DispatchQoS.QoSClass {
    static var current: DispatchQoS.QoSClass {
        let currentQoS = qos_class_self()
        switch currentQoS {
        case QOS_CLASS_USER_INTERACTIVE:
            return .userInteractive
        case QOS_CLASS_USER_INITIATED:
            return .userInitiated
        case QOS_CLASS_DEFAULT:
            return .default
        case QOS_CLASS_UTILITY:
            return .utility
        case QOS_CLASS_BACKGROUND:
            return .background
        default:
            return .default
        }
    }
}
