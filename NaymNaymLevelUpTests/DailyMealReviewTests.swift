import XCTest
import CoreData
@testable import NaymNaymLevelUp

final class DailyMealReviewTests: XCTestCase {
    private var meal: RebuildMealDay { RebuildMealDay(date: "2026-09-13", menuItems: [
        RebuildMealItem(name: "현미밥", allergyCodes: [], nutrients: ["carbohydrate"], tags: [], sourceRawText: "현미밥"),
        RebuildMealItem(name: "우유", allergyCodes: [2], nutrients: ["calcium"], tags: [], sourceRawText: "우유(2)"),
        RebuildMealItem(name: "정보없음", allergyCodes: [], nutrients: [], tags: [], sourceRawText: "")
    ], calorie: "", nutrition: .empty) }
    private let id=UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private var responseData: Data { Data(#"{"source":"ai","reviewId":"00000000-0000-4000-8000-000000000001","day":"2026-09-13","generatedAt":"2026-09-13T04:00:00.000Z","model":"deepseek-v4.1-flash","policyVersion":"daily-v1","summary":"대표 영양소를 살펴봤어.","benefit":"활동에 쓰이는 에너지원이야.","highlights":[{"itemId":"m0","nutrient":"carbohydrate","reason":"움직이는 데 도움이 돼."}],"caution":"실제로 먹은 양은 알 수 없어.","tip":"다음 식사에서도 다양하게 만나 보자."}"#.utf8) }
    func testRequestExcludesAllergyUnknownAndPersonalMetadata() throws {
        let request=DailyMealReviewFactory.request(meal: meal, allergies: [2], requestId: id)
        XCTAssertEqual(request.items,[DailyMealReviewItem(id: "m0", nutrients: ["carbohydrate"])])
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["requestId","sessionId","items","wholeMeal"])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(request), as: UTF8.self).contains("현미밥"))
    }
    func testKoreaDateChangesAtUtcFifteen() {
        let parser=ISO8601DateFormatter()
        XCTAssertEqual(DailyMealReviewFactory.day(parser.date(from: "2026-09-13T14:59:59Z")!), "2026-09-13")
        XCTAssertEqual(DailyMealReviewFactory.day(parser.date(from: "2026-09-13T15:00:00Z")!), "2026-09-14")
    }
    func testTransportUsesDailyRouteAndKeepsCredentialOutOfBody() throws {
        let credential=String(repeating:"synthetic",count:5)
        let config=try XCTUnwrap(MealCoachConfiguration(endpoint:"http://127.0.0.1:64918/v1/meal-coach",accessToken:credential))
        let request=try DailyMealReviewClient.makeRequest(config,payload:DailyMealReviewFactory.request(meal:meal,allergies:[2]))
        XCTAssertEqual(request.url?.path,"/v2/meal-coach/daily")
        XCTAssertEqual(request.httpMethod,"POST")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+credential)
        XCTAssertFalse(String(decoding:try XCTUnwrap(request.httpBody),as:UTF8.self).contains(credential))
    }
    @MainActor func testCorruptSavedRecordFailsClosedWithoutDeletingIt() async throws {
        let container=try RebuildPersistentStore.makeInMemory()
        let context=container.viewContext
        let row=NSEntityDescription.insertNewObject(forEntityName:RebuildEntityName.dailyMealReview,into:context)
        row.setValue("test:"+meal.date,forKey:"id");row.setValue("test",forKey:"contextKey");row.setValue(meal.date,forKey:"day");row.setValue("corrupt fixture",forKey:"payloadJSON");try context.save()
        var calls=0
        let controller=DailyMealReviewController(meal:meal,contextKey:"test",allergies:[],store:DailyMealReviewStore(context:container.newBackgroundContext()),client:DailyMealReviewClient {_ in calls+=1;throw MealCoachError.unavailable},now:{ISO8601DateFormatter().date(from:"2026-09-13T03:00:00Z")!})
        await controller.generate(consent:true)
        XCTAssertFalse(controller.canGenerate);XCTAssertEqual(calls,0)
        XCTAssertEqual(try context.count(for:NSFetchRequest<NSFetchRequestResult>(entityName:RebuildEntityName.dailyMealReview)),1)
    }
    @MainActor func testDismissAndRecreateReusesPendingRequestWithinRecoveryWindow() async throws {
        let container=try RebuildPersistentStore.makeInMemory()
        let store=DailyMealReviewStore(context:container.newBackgroundContext())
        let key=UUID().uuidString
        var sent:[DailyMealReviewRequest]=[]
        let client=DailyMealReviewClient { request in sent.append(request);throw CancellationError() }
        let now={ISO8601DateFormatter().date(from:"2026-09-13T03:00:00Z")!}
        let first=DailyMealReviewController(meal:meal,contextKey:key,allergies:[],store:store,client:client,now:now)
        await first.generate(consent:true)
        let recreated=DailyMealReviewController(meal:meal,contextKey:key,allergies:[],store:store,client:client,now:now)
        await recreated.generate(consent:true)
        XCTAssertEqual(sent.count,2);XCTAssertEqual(sent.first,sent.last)
    }
    func testStructuredInvalidSavedRequestsFailClosed() throws {
        let container=try RebuildPersistentStore.makeInMemory()
        let store=DailyMealReviewStore(context:container.newBackgroundContext())
        let valid=DailyMealReviewFactory.request(meal:meal,allergies:[2],requestId:id)
        let response=try DailyMealReviewResponse.decode(responseData,request:valid)
        let emptyResponse=DailyMealReviewResponse(source:response.source,reviewId:response.reviewId,day:response.day,generatedAt:response.generatedAt,model:response.model,policyVersion:response.policyVersion,summary:response.summary,benefit:response.benefit,highlights:[],caution:response.caution,tip:response.tip)
        for request in [
            DailyMealReviewRequest(requestId:valid.requestId,sessionId:valid.sessionId,items:[],wholeMeal:[:]),
            DailyMealReviewRequest(requestId:valid.requestId,sessionId:"invalid",items:valid.items,wholeMeal:[:]),
            DailyMealReviewRequest(requestId:valid.requestId,sessionId:valid.sessionId,items:valid.items+valid.items,wholeMeal:[:]),
            DailyMealReviewRequest(requestId:valid.requestId,sessionId:valid.sessionId,items:valid.items,wholeMeal:["invented":12]),
            DailyMealReviewRequest(requestId:valid.requestId,sessionId:valid.sessionId,items:valid.items,wholeMeal:["protein":12])
        ] {
            XCTAssertThrowsError(try store.save(record:DailyMealReviewRecord(contextKey:UUID().uuidString,day:meal.date,meal:meal,request:request,response:emptyResponse)))
        }
    }
    @MainActor func testSaveFailureRetainsResultAndRetriesWithoutCallingAI() async throws {
        let container=try RebuildPersistentStore.makeInMemory()
        let context=DailyReviewFailingContext(concurrencyType:.privateQueueConcurrencyType)
        context.persistentStoreCoordinator=container.persistentStoreCoordinator
        var calls=0;let fixture=responseData
        let client=DailyMealReviewClient {request in
            calls+=1;context.performAndWait {context.failNextSave=true}
            return try .decode(Data(String(decoding:fixture,as:UTF8.self).replacingOccurrences(of:"00000000-0000-4000-8000-000000000001",with:request.requestId).utf8),request:request)
        }
        let controller=DailyMealReviewController(meal:meal,contextKey:UUID().uuidString,allergies:[2],store:DailyMealReviewStore(context:context),client:client,now:{ISO8601DateFormatter().date(from:"2026-09-13T03:00:00Z")!})
        await controller.generate(consent:true)
        XCTAssertNil(controller.record);XCTAssertNotNil(controller.unsaved)
        await controller.generate(consent:true);XCTAssertEqual(calls,1)
        controller.retrySave();XCTAssertNotNil(controller.record);XCTAssertNil(controller.unsaved);XCTAssertEqual(calls,1)
    }
    func testResponseChecksRequestIdentityAndHighlightMembership() throws {
        let request=DailyMealReviewFactory.request(meal: meal, allergies: [2], requestId: id)
        XCTAssertEqual(try DailyMealReviewResponse.decode(responseData, request: request).source,"ai")
        let wrong=Data(String(decoding: responseData,as: UTF8.self).replacingOccurrences(of: "m0",with: "m9").utf8)
        XCTAssertThrowsError(try DailyMealReviewResponse.decode(wrong,request: request))
        let unsupported=Data(String(decoding: responseData,as: UTF8.self).replacingOccurrences(of: "carbohydrate",with: "protein").utf8)
        XCTAssertThrowsError(try DailyMealReviewResponse.decode(unsupported,request: request))
        XCTAssertThrowsError(try DailyMealReviewResponse.decode(responseData,request: DailyMealReviewFactory.request(meal:meal,allergies:[])))
    }
    func testCurrentAllergiesMaskSavedRecommendations() throws {
        let request=DailyMealReviewFactory.request(meal: meal, allergies: [],requestId:id)
        let data=Data(String(decoding:responseData,as:UTF8.self).replacingOccurrences(of:"m0",with:"m1").replacingOccurrences(of:"carbohydrate",with:"calcium").utf8)
        let response=try DailyMealReviewResponse.decode(data,request:request)
        let record=DailyMealReviewRecord(contextKey:"test",day:meal.date,meal:meal,request:request,response:response)
        XCTAssertEqual(DailyMealReviewFactory.visibleHighlights(record,allergies:[]).count,1)
        XCTAssertTrue(DailyMealReviewFactory.visibleHighlights(record,allergies:[2]).isEmpty)
    }
    func testPersistentReviewReloadSeparationAndDeletePreserveProgress() throws {
        let container=try RebuildPersistentStore.makeInMemory()
        let context=container.viewContext
        let progress=NSEntityDescription.insertNewObject(forEntityName:RebuildEntityName.progressEvent,into:context)
        progress.setValue("fixture",forKey:"id");progress.setValue(10,forKey:"amount");progress.setValue(Date(),forKey:"occurredAt");try context.save()
        let request=DailyMealReviewFactory.request(meal:meal,allergies:[2],requestId:id)
        let record=DailyMealReviewRecord(contextKey:"school-a",day:meal.date,meal:meal,request:request,response:try .decode(responseData,request:request))
        let store=DailyMealReviewStore(context:container.newBackgroundContext())
        try store.save(record:record)
        let reopened=DailyMealReviewStore(context:container.newBackgroundContext())
        XCTAssertEqual(try reopened.load(context:"school-a",day:meal.date),record)
        XCTAssertNil(try reopened.load(context:"school-b",day:meal.date))
        try reopened.deleteAll()
        XCTAssertNil(try store.load(context:"school-a",day:meal.date))
        XCTAssertEqual(try context.count(for:NSFetchRequest<NSFetchRequestResult>(entityName:RebuildEntityName.progressEvent)),1)
    }
    func testExistingStoreMigratesWithoutLosingProfileOrProgress() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let old=NSPersistentContainer(name:"NaymRebuild",managedObjectModel:RebuildManagedModel.make(includeDailyReview:false))
        let description=RebuildPersistentStore.makePersistentStoreDescription(storeDirectory:directory)
        old.persistentStoreDescriptions=[description]
        var loadError:Error?;old.loadPersistentStores {_,error in loadError=error};if let loadError {throw loadError}
        let item=NSEntityDescription.insertNewObject(forEntityName:RebuildEntityName.progressEvent,into:old.viewContext)
        item.setValue("preserve",forKey:"id");item.setValue(10,forKey:"amount");item.setValue(Date(),forKey:"occurredAt");try old.viewContext.save()
        for store in old.persistentStoreCoordinator.persistentStores {try old.persistentStoreCoordinator.remove(store)}
        let upgraded=try RebuildPersistentStore.makePersistent(storeDirectory:directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath:directory.appendingPathComponent("NaymRebuild.before-daily-review.sqlite").path))
        XCTAssertEqual(try upgraded.viewContext.count(for:NSFetchRequest<NSFetchRequestResult>(entityName:RebuildEntityName.progressEvent)),1)
        XCTAssertEqual(try upgraded.viewContext.count(for:NSFetchRequest<NSFetchRequestResult>(entityName:RebuildEntityName.dailyMealReview)),0)
    }
    @MainActor func testSavedReviewReopensWithoutAnotherClientCall() async throws {
        let container=try RebuildPersistentStore.makeInMemory();let store=DailyMealReviewStore(context:container.newBackgroundContext())
        var calls=0
        let fixture=responseData
        let client=DailyMealReviewClient { request in
            calls+=1
            let body=Data(String(decoding:fixture,as:UTF8.self).replacingOccurrences(of:"00000000-0000-4000-8000-000000000001",with:request.requestId).utf8)
            return try .decode(body,request:request)
        }
        let now={ ISO8601DateFormatter().date(from:"2026-09-13T03:00:00Z")! }
        let first=DailyMealReviewController(meal:meal,contextKey:"test",allergies:[2],store:store,client:client,now:now)
        await first.generate(consent:false);XCTAssertEqual(calls,0)
        await first.generate(consent:true);XCTAssertNotNil(first.record)
        let second=DailyMealReviewController(meal:meal,contextKey:"test",allergies:[2],store:store,client:client,now:now)
        second.load();await second.generate(consent:true)
        XCTAssertEqual(calls,1);XCTAssertEqual(second.record,first.record)
    }
    @MainActor func testConflictAndUnrecoverableRequestsDoNotOfferAnotherGeneration() async throws {
        for code in ["request_conflict", "recovery_unavailable"] {
            let container=try RebuildPersistentStore.makeInMemory()
            var calls=0
            let client=DailyMealReviewClient { _ in calls+=1;throw DailyMealReviewFailure.server(code) }
            let controller=DailyMealReviewController(meal:meal,contextKey:"test",allergies:[],store:DailyMealReviewStore(context:container.newBackgroundContext()),client:client,now:{ISO8601DateFormatter().date(from:"2026-09-13T03:00:00Z")!})
            await controller.generate(consent:true)
            XCTAssertFalse(controller.canGenerate)
            await controller.generate(consent:true)
            XCTAssertEqual(calls,1)
        }
    }
    @MainActor func testPastFutureAndAllFlaggedMealsDoNotCallAI() async throws {
        let container=try RebuildPersistentStore.makeInMemory();let store=DailyMealReviewStore(context:container.newBackgroundContext())
        var calls=0;let client=DailyMealReviewClient {_ in calls+=1;throw MealCoachError.unavailable}
        for timestamp in ["2026-09-12T03:00:00Z","2026-09-14T03:00:00Z"] {
            let controller=DailyMealReviewController(meal:meal,contextKey:"test",allergies:[],store:store,client:client,now:{ISO8601DateFormatter().date(from:timestamp)!})
            await controller.generate(consent:true);XCTAssertFalse(controller.canGenerate)
        }
        let flagged=RebuildMealDay(date:meal.date,menuItems:[meal.menuItems[1]],calorie:"",nutrition:.empty)
        let controller=DailyMealReviewController(meal:flagged,contextKey:"test",allergies:[2],store:store,client:client,now:{ISO8601DateFormatter().date(from:"2026-09-13T03:00:00Z")!})
        await controller.generate(consent:true);XCTAssertFalse(controller.canGenerate);XCTAssertEqual(calls,0)
    }
}

private final class DailyReviewFailingContext:NSManagedObjectContext, @unchecked Sendable {
    var failNextSave=false
    override func save() throws {
        if failNextSave {failNextSave=false;throw NSError(domain:"SyntheticSaveFailure",code:1)}
        try super.save()
    }
}
