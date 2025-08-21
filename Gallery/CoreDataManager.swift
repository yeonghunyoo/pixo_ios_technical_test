import CoreData
import Photos

class CoreDataManager {
    static let shared = CoreDataManager()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Gallery")
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        return container
    }()
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
    
    // func createPhotoAsset(identifier: String, creationDate: Date, mediaType: PHAssetMediaType, mediaSubTypes: PHAssetMediaSubtype) -> PhotoAsset {
    //     let photoAsset = PhotoAsset(context: context)
    //     photoAsset.identifier = identifier
    //     photoAsset.creationDate = creationDate
    //     photoAsset.mediaType = Int16(mediaType.rawValue)
    //     photoAsset.mediaSubTypes = Int64(mediaSubTypes.rawValue)
    //     saveContext()
    //     return photoAsset
    // }
    
    func createPhotoAssetsBatch(from phAssets: [PHAsset]) async -> [PhotoAsset] {
        return await withCheckedContinuation { continuation in
            let backgroundContext = persistentContainer.newBackgroundContext()
            
            backgroundContext.perform {
                var photoAssets: [PhotoAsset] = []
                
                for phAsset in phAssets {
                    let photoAsset = PhotoAsset(context: backgroundContext)
                    photoAsset.identifier = phAsset.localIdentifier
                    photoAsset.creationDate = Date()
                    photoAsset.mediaType = Int16(phAsset.mediaType.rawValue)
                    photoAsset.mediaSubTypes = Int64(phAsset.mediaSubtypes.rawValue)
                    photoAssets.append(photoAsset)
                }
                
                do {
                    try backgroundContext.save()
                    
                    let objectIDs = photoAssets.map { $0.objectID }
                    let mainContextPhotoAssets = objectIDs.compactMap { 
                        self.context.object(with: $0) as? PhotoAsset 
                    }
                    
                    continuation.resume(returning: mainContextPhotoAssets)
                } catch {
                    print("배치 저장 실패: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func fetchPhotoAssets() -> [PhotoAsset] {
        let fetchRequest: NSFetchRequest<PhotoAsset> = PhotoAsset.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Error fetching PhotoAssets: \(error)")
            return []
        }
    }
}
