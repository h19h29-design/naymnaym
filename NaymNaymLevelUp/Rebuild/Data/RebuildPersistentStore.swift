import CoreData

enum RebuildPersistentStore {
    static let storeFilename = "NaymRebuild.sqlite"

    static func makePersistent() throws -> NSPersistentContainer {
        try makePersistent(storeDirectory: NSPersistentContainer.defaultDirectoryURL())
    }

    static func makePersistent(storeDirectory: URL) throws -> NSPersistentContainer {
        let description = makePersistentStoreDescription(storeDirectory: storeDirectory)
        return try makeContainer(description: description)
    }

    static func makeInMemory() throws -> NSPersistentContainer {
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        return try makeContainer(description: description)
    }

    static func makePersistentStoreDescription(
        storeDirectory: URL
    ) -> NSPersistentStoreDescription {
        let storeURL = storeDirectory.appendingPathComponent(storeFilename, isDirectory: false)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    private static func makeContainer(
        description: NSPersistentStoreDescription
    ) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: "NaymRebuild",
            managedObjectModel: RebuildManagedModel.make()
        )
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        container.viewContext.performAndWait {
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            container.viewContext.automaticallyMergesChangesFromParent = true
        }
        return container
    }
}
