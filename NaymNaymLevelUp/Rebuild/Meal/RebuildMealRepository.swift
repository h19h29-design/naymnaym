import CoreData
import Foundation

actor RebuildMealRepository {
    typealias Clock = @Sendable () -> Date

    private let store: RebuildMealDayStore
    private let client: RebuildMealClientProtocol
    private let now: Clock
    private var states: [String: MealLoadState] = [:]
    private var observers:
        [String: [UUID: AsyncStream<MealLoadState>.Continuation]] = [:]

    init(
        store: RebuildMealDayStore,
        client: RebuildMealClientProtocol,
        now: @escaping Clock = { Date() }
    ) {
        self.store = store
        self.client = client
        self.now = now
    }

    func observe(date: String) -> AsyncStream<MealLoadState> {
        let observerID = UUID()
        let initialState = currentState(date: date)
        return AsyncStream(bufferingPolicy: .bufferingNewest(4)) {
            continuation in
            observers[date, default: [:]][observerID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeObserver(
                        id: observerID,
                        date: date
                    )
                }
            }
            continuation.yield(initialState)
        }
    }

    func currentState(date: String) -> MealLoadState {
        if let state = states[date] {
            return state
        }

        let initialState: MealLoadState
        do {
            if let cached = try store.load(date: date) {
                initialState = .cached(
                    cached.meal,
                    refreshedAt: cached.refreshedAt
                )
            } else {
                initialState = .empty
            }
        } catch {
            initialState = .failed(
                message: Self.message(for: error),
                cached: nil
            )
        }
        states[date] = initialState
        return initialState
    }

    func refresh(date: String, school: RebuildSchool) async {
        let cached: RebuildCachedMealDay?
        do {
            cached = try store.load(date: date)
        } catch {
            update(
                .failed(message: Self.message(for: error), cached: nil),
                date: date
            )
            return
        }

        update(.refreshing(cached?.meal), date: date)

        do {
            guard let meal = try await client.fetch(date: date, school: school)
            else {
                try store.remove(date: date)
                update(.empty, date: date)
                return
            }
            let refreshedAt = now()
            try store.save(meal, refreshedAt: refreshedAt, source: "neis")
            update(.live(meal), date: date)
        } catch {
            if let cached {
                update(
                    .cached(
                        cached.meal,
                        refreshedAt: cached.refreshedAt
                    ),
                    date: date
                )
            } else {
                update(
                    .failed(
                        message: Self.message(for: error),
                        cached: nil
                    ),
                    date: date
                )
            }
        }
    }

    private func update(_ state: MealLoadState, date: String) {
        states[date] = state
        guard let dateObservers = observers[date] else {
            return
        }

        for (id, continuation) in dateObservers {
            if case .terminated = continuation.yield(state) {
                observers[date]?[id] = nil
            }
        }
        if observers[date]?.isEmpty == true {
            observers[date] = nil
        }
    }

    private func removeObserver(id: UUID, date: String) {
        observers[date]?[id] = nil
        if observers[date]?.isEmpty == true {
            observers[date] = nil
        }
    }

    private static func message(for error: Error) -> String {
        String(describing: error)
    }
}

final class CoreDataRebuildMealDayStore: RebuildMealDayStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load(date: String) throws -> RebuildCachedMealDay? {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildMealDayManagedObject>(
                entityName: RebuildEntityName.mealDay
            )
            request.predicate = NSPredicate(format: "date == %@", date)
            request.fetchLimit = 1
            guard let object = try context.fetch(request).first else {
                return nil
            }
            return RebuildCachedMealDay(
                meal: try JSONDecoder().decode(
                    RebuildMealDay.self,
                    from: Data(object.payloadJSON.utf8)
                ),
                refreshedAt: object.fetchedAt,
                source: object.source
            )
        }
    }

    func save(
        _ meal: RebuildMealDay,
        refreshedAt: Date,
        source: String
    ) throws {
        let payload = String(
            decoding: try JSONEncoder().encode(meal),
            as: UTF8.self
        )
        try context.performAndWait {
            let request = NSFetchRequest<RebuildMealDayManagedObject>(
                entityName: RebuildEntityName.mealDay
            )
            request.predicate = NSPredicate(format: "date == %@", meal.date)
            request.fetchLimit = 1

            let object: RebuildMealDayManagedObject
            if let existing = try context.fetch(request).first {
                object = existing
            } else {
                guard
                    let inserted = NSEntityDescription.insertNewObject(
                        forEntityName: RebuildEntityName.mealDay,
                        into: context
                    ) as? RebuildMealDayManagedObject
                else {
                    throw RebuildRepositoryError.unexpectedManagedObjectType(
                        entityName: RebuildEntityName.mealDay
                    )
                }
                object = inserted
            }

            object.date = meal.date
            object.payloadJSON = payload
            object.fetchedAt = refreshedAt
            object.source = source
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func remove(date: String) throws {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildMealDayManagedObject>(
                entityName: RebuildEntityName.mealDay
            )
            request.predicate = NSPredicate(format: "date == %@", date)
            for object in try context.fetch(request) {
                context.delete(object)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
