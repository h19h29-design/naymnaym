import CoreData
import SwiftUI

final class DailyMealReviewStore {
    let context: NSManagedObjectContext
    init(context: NSManagedObjectContext) { self.context=context }
    func load(context key: String, day: String) throws -> DailyMealReviewRecord? {
        try context.performAndWait {
            let request=NSFetchRequest<NSManagedObject>(entityName:RebuildEntityName.dailyMealReview)
            request.predicate=NSPredicate(format:"contextKey == %@ AND day == %@",key,day);request.fetchLimit=1
            guard let row=try context.fetch(request).first else{return nil}
            guard let text=row.value(forKey:"payloadJSON") as? String,let data=text.data(using:.utf8),data.count<=131072 else{throw MealCoachError.invalidResponse}
            let record=try JSONDecoder().decode(DailyMealReviewRecord.self,from:data)
            guard record.contextKey==key,record.day==day else{throw MealCoachError.invalidResponse}
            try validate(record);return record
        }
    }
    func save(record: DailyMealReviewRecord) throws {
        try validate(record)
        let data=try JSONEncoder().encode(record)
        guard data.count<=131072,let text=String(data:data,encoding:.utf8) else{throw MealCoachError.invalidResponse}
        try context.performAndWait {
            let request=NSFetchRequest<NSManagedObject>(entityName:RebuildEntityName.dailyMealReview)
            request.predicate=NSPredicate(format:"contextKey == %@ AND day == %@",record.contextKey,record.day)
            if let row=try context.fetch(request).first {
                guard let old=row.value(forKey:"payloadJSON") as? String,
                      let oldRecord=try? JSONDecoder().decode(DailyMealReviewRecord.self,from:Data(old.utf8)),oldRecord==record else{throw MealCoachError.invalidResponse}
                return
            }
            let row=NSEntityDescription.insertNewObject(forEntityName:RebuildEntityName.dailyMealReview,into:context)
            row.setValue(record.contextKey+":"+record.day,forKey:"id");row.setValue(record.contextKey,forKey:"contextKey")
            row.setValue(record.day,forKey:"day");row.setValue(text,forKey:"payloadJSON")
            do {try context.save()} catch {context.rollback();throw error}
        }
    }
    func deleteAll() throws {
        try context.performAndWait {
            let rows=try context.fetch(NSFetchRequest<NSManagedObject>(entityName:RebuildEntityName.dailyMealReview))
            rows.forEach(context.delete)
            do {try context.save()} catch{context.rollback();throw error}
        }
    }
    private func validate(_ record: DailyMealReviewRecord) throws {
        try record.request.validate()
        guard !record.contextKey.isEmpty,record.day==record.meal.date,record.day==record.response.day else{throw MealCoachError.invalidResponse}
        _=try DailyMealReviewResponse.decode(JSONEncoder().encode(record.response),request:record.request)
        let available=DailyMealReviewFactory.request(meal:record.meal,allergies:[]).items
        guard record.request.wholeMeal==MealCoachRequest.wholeMealValues(record.meal),
              record.request.items.allSatisfy({ item in available.contains(where:{$0==item}) }) else{throw MealCoachError.invalidResponse}
    }
}

private struct DailyReviewContainerKey: EnvironmentKey { static let defaultValue: NSPersistentContainer? = nil }
extension EnvironmentValues {
    var dailyReviewContainer: NSPersistentContainer? {
        get { self[DailyReviewContainerKey.self] }
        set { self[DailyReviewContainerKey.self]=newValue }
    }
}
