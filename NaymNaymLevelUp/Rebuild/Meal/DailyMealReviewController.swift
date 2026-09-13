import Foundation
import Combine

enum DailyMealReviewFailure: Error { case server(String) }
struct DailyMealReviewClient {
    var answer: (DailyMealReviewRequest) async throws -> DailyMealReviewResponse
    static func live(_ configuration: MealCoachConfiguration) -> Self {
        Self { payload in
            let settings=URLSessionConfiguration.ephemeral
            settings.timeoutIntervalForRequest=15;settings.timeoutIntervalForResource=15;settings.urlCache=nil;settings.httpCookieStorage=nil
            let session=URLSession(configuration:settings,delegate:MealCoachNoRedirect(),delegateQueue:nil)
            defer{session.invalidateAndCancel()}
            let request=try makeRequest(configuration,payload:payload)
            let (bytes,response)=try await session.bytes(for:request)
            var data=Data()
            for try await byte in bytes {try Task.checkCancellation();guard data.count<16384 else{throw MealCoachError.invalidResponse};data.append(byte)}
            guard (response as? HTTPURLResponse)?.statusCode==200 else {
                let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
                let permitted=["daily_used","daily_attempt_limit","usage_limit","in_progress","recovery_unavailable","storage_unavailable","not_configured","request_conflict"]
                let code=value?["error"] as? String ?? "unavailable"
                throw DailyMealReviewFailure.server(permitted.contains(code) ? code : "unavailable")
            }
            return try .decode(data,request:payload)
        }
    }
    static func makeRequest(_ configuration: MealCoachConfiguration,payload:DailyMealReviewRequest) throws -> URLRequest {
        try payload.validate()
        var components=URLComponents(url:configuration.endpoint,resolvingAgainstBaseURL:false)!
        components.path="/v2/meal-coach/daily"
        var request=URLRequest(url:components.url!);request.httpMethod="POST"
        request.setValue("Bearer \(configuration.accessToken)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let data=try JSONEncoder().encode(payload);guard data.count<=8192 else{throw MealCoachError.invalidResponse}
        request.httpBody=data;return request
    }
}

// Keep only anonymous requests briefly across sheet dismissal, never answers or credentials.
@MainActor
private final class DailyReviewPendingRequests {
    static let shared=DailyReviewPendingRequests()
    private var entries:[String:(request:DailyMealReviewRequest,at:Date)]=[:]
    func request(key:String,proposed:DailyMealReviewRequest,now:Date) -> DailyMealReviewRequest {
        entries=entries.filter {now.timeIntervalSince($0.value.at)>=0 && now.timeIntervalSince($0.value.at)<=90}
        if let prior=entries[key],prior.request.items==proposed.items,prior.request.wholeMeal==proposed.wholeMeal{return prior.request}
        if entries.count>=64,let oldest=entries.min(by:{$0.value.at<$1.value.at})?.key {entries.removeValue(forKey:oldest)}
        entries[key]=(proposed,now);return proposed
    }
    func remove(key:String){entries.removeValue(forKey:key)}
}

@MainActor
final class DailyMealReviewController: ObservableObject {
    @Published private(set) var record: DailyMealReviewRecord?
    @Published private(set) var unsaved: DailyMealReviewRecord?
    @Published private(set) var isLoading=false
    @Published private(set) var notice: String?
    let meal: RebuildMealDay
    let contextKey: String
    private let store: DailyMealReviewStore?
    private let client: DailyMealReviewClient?
    private let now: () -> Date
    private var allergies: [Int]
    private var pendingKey:String {contextKey+":"+meal.date}
    private var storageFailed=false
    private var blocked=false
    init(meal: RebuildMealDay, contextKey: String, allergies: [Int], store: DailyMealReviewStore?, client: DailyMealReviewClient?, now: @escaping () -> Date = Date.init) {
        self.meal=meal;self.contextKey=contextKey;self.allergies=allergies;self.store=store;self.client=client;self.now=now
    }
    func load() {
        guard let store else{storageFailed=true;notice="평가 저장소를 열 수 없어요. 기존 기록은 지우지 않았어요.";return}
        do {record=try store.load(context:contextKey,day:meal.date);storageFailed=false}
        catch {storageFailed=true;notice="저장된 평가를 읽지 못했어요. 기존 기록은 보존했어요."}
    }
    func generate(consent: Bool) async {
        guard !isLoading else{return}
        load();guard record==nil,unsaved==nil,canGenerate,consent,let client else{return}
        let proposed=DailyMealReviewFactory.request(meal:meal,allergies:allergies)
        let request=DailyReviewPendingRequests.shared.request(key:pendingKey,proposed:proposed,now:now())
        isLoading=true;notice=nil;defer{isLoading=false}
        do {
            let response=try await client.answer(request);try Task.checkCancellation()
            guard response.day==meal.date else{throw MealCoachError.invalidResponse}
            unsaved=DailyMealReviewRecord(contextKey:contextKey,day:meal.date,meal:meal,request:request,response:response)
            retrySave()
        } catch is CancellationError {return}
        catch DailyMealReviewFailure.server(let code) {
            switch code {
            case "daily_used":blocked=true;notice="오늘 AI 평가는 이미 생성했어요. 이 기기에 저장된 기록이 없으면 다시 생성할 수 없어요."
            case "daily_attempt_limit":blocked=true;notice="오늘 연결 시도 한도에 도달했어요. 기본 영양 안내를 확인해 주세요."
            case "recovery_unavailable":blocked=true;notice="이전 요청의 결과를 복구할 수 없어요. 중복 생성을 막기 위해 오늘은 기본 안내를 보여드려요."
            case "request_conflict":blocked=true;notice="이전 요청과 식단 정보가 달라 다시 생성하지 않았어요. 오늘은 기본 영양 안내를 확인해 주세요."
            case "storage_unavailable":notice="AI 서버의 사용 기록을 확인하지 못했어요. 기본 안내를 보여드려요."
            default:notice="AI 설명을 받지 못했어요. 기본 영양 안내를 보여드려요. 자동으로 다시 요청하지 않아요."
            }
        } catch {notice="AI 설명을 받지 못했어요. 기본 영양 안내를 보여드려요. 자동으로 다시 요청하지 않아요."}
    }
    func retrySave() {
        guard let unsaved,let store else{return}
        do{try store.save(record:unsaved);record=unsaved;self.unsaved=nil;DailyReviewPendingRequests.shared.remove(key:pendingKey);notice=nil}
        catch{notice="AI 설명은 받았지만 기기에 저장하지 못했어요. 다시 저장하면 추가 AI 호출 없이 보관해요."}
    }
    func updateAllergies(_ codes: [Int]) {allergies=codes;objectWillChange.send()}
    var canGenerate: Bool { !storageFailed && !blocked && store != nil && client != nil && record==nil && unsaved==nil && meal.date==DailyMealReviewFactory.day(now()) && !DailyMealReviewFactory.request(meal:meal,allergies:allergies).items.isEmpty }
    var eligibilityMessage: String {
        if meal.date != DailyMealReviewFactory.day(now()) {return "이 날짜에 저장된 AI 평가가 없어요. 새 평가는 오늘 식단만 만들 수 있어요."}
        if meal.menuItems.isEmpty{return "등록된 급식이 없어 AI 평가를 만들지 않아요."}
        if DailyMealReviewFactory.request(meal:meal,allergies:allergies).items.isEmpty{return "알레르기 주의 또는 정보가 부족한 메뉴는 추천하지 않아요. 보호자·선생님에게 확인해 주세요."}
        if client==nil{return "현재는 기본 영양 안내를 이용할 수 있어요. AI 연결은 개발 테스트에서만 제공돼요."}
        return "하루 한 번 생성하고, 저장된 평가는 언제든 다시 볼 수 있어요."
    }
    var hasClient: Bool {client != nil}
}
