import CoreData

enum RebuildPersistentStore {
    static let storeFilename = "NaymRebuild.sqlite"

    static func makePersistent() throws -> NSPersistentContainer {
        try makePersistent(storeDirectory: NSPersistentContainer.defaultDirectoryURL())
    }

    static func makePersistent(storeDirectory: URL) throws -> NSPersistentContainer {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let description = makePersistentStoreDescription(storeDirectory: storeDirectory)
        if let url=description.url { try migrateDailyReviewIfNeeded(at:url) }
        return try makeContainer(description: description)
    }

    private static func migrateDailyReviewIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath:url.path) else{return}
        let metadata=try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType:NSSQLiteStoreType,at:url,options:nil)
        let destination=RebuildManagedModel.make()
        guard !destination.isConfiguration(withName:nil,compatibleWithStoreMetadata:metadata) else{return}
        let source=RebuildManagedModel.make(includeDailyReview:false)
        guard source.isConfiguration(withName:nil,compatibleWithStoreMetadata:metadata) else {
            throw NSError(domain:"DailyMealReviewMigration",code:1,userInfo:[NSLocalizedDescriptionKey:"지원하지 않는 저장소 버전이에요. 기존 데이터는 보존했어요."])
        }
        let backup=url.deletingLastPathComponent().appendingPathComponent("NaymRebuild.before-daily-review.sqlite")
        let coordinator=NSPersistentStoreCoordinator(managedObjectModel:source)
        if !FileManager.default.fileExists(atPath:backup.path) {
            try coordinator.replacePersistentStore(at:backup,destinationOptions:nil,withPersistentStoreFrom:url,sourceOptions:nil,ofType:NSSQLiteStoreType)
        }
        let temporary=url.deletingLastPathComponent().appendingPathComponent("daily-review-migration-\(UUID().uuidString).sqlite")
        let mapping=try NSMappingModel.inferredMappingModel(forSourceModel:source,destinationModel:destination)
        let manager=NSMigrationManager(sourceModel:source,destinationModel:destination)
        try manager.migrateStore(from:url,sourceType:NSSQLiteStoreType,options:nil,with:mapping,toDestinationURL:temporary,destinationType:NSSQLiteStoreType,destinationOptions:nil)
        try coordinator.replacePersistentStore(at:url,destinationOptions:nil,withPersistentStoreFrom:temporary,sourceOptions:nil,ofType:NSSQLiteStoreType)
        // Preserve the pre-migration backup and migration artifact for recovery.
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
