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
    
    func createPhotoAsset(identifier: String, creationDate: Date, mediaType: PHAssetMediaType, mediaSubTypes: PHAssetMediaSubtype) -> PhotoAsset {
        let photoAsset = PhotoAsset(context: context)
        photoAsset.identifier = identifier
        photoAsset.creationDate = creationDate
        photoAsset.mediaType = Int16(mediaType.rawValue)
        photoAsset.mediaSubTypes = Int64(mediaSubTypes.rawValue)
        saveContext()
        return photoAsset
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
