import SwiftUI
import CoreData

struct DailyReviewSheet: View {
    let meal: RebuildMealDay
    let allergies: [Int]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    var body: some View {
        NavigationStack {
            ScrollView {DailyMealReviewView(meal:meal,registeredAllergyCodes:appState.profile?.selectedAllergyCodes ?? allergies).padding(16)}
                .background(RebuildDesignTokens.cream50).navigationTitle("오늘 식단 AI 해설").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction){Button("닫기"){dismiss()}}}
        }
    }
}

struct DailyMealReviewView: View {
    let meal: RebuildMealDay
    let registeredAllergyCodes: [Int]
    var showsSourceNutrition=true
    @EnvironmentObject private var appState: AppState
    @Environment(\.dailyReviewContainer) private var container
    var body: some View {
        Group {
            if let container,let profile=appState.profile {
                let key=DailyMealReviewFactory.contextKey(profileID:profile.id.uuidString,officeCode:profile.officeCode,schoolCode:profile.schoolCode)
                DailyMealReviewContent(meal:meal,contextKey:key,allergies:registeredAllergyCodes,container:container,showsSourceNutrition:showsSourceNutrition)
                    .id(key+meal.date+String(describing:meal))
            } else {
                Label("평가 저장소를 열 수 없어요. 기존 기록은 보존했어요.",systemImage:"exclamationmark.shield")
                    .font(.footnote).padding()
            }
        }
    }
}

private struct DailyMealReviewContent: View {
    let meal: RebuildMealDay
    let allergies: [Int]
    let showsSourceNutrition: Bool
    @StateObject private var controller: DailyMealReviewController
    @State private var consent=false
    @State private var action: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    init(meal:RebuildMealDay,contextKey:String,allergies:[Int],container:NSPersistentContainer,showsSourceNutrition:Bool) {
        self.meal=meal;self.allergies=allergies;self.showsSourceNutrition=showsSourceNutrition
        _controller=StateObject(wrappedValue:DailyMealReviewController(meal:meal,contextKey:contextKey,allergies:allergies,
            store:DailyMealReviewStore(context:container.newBackgroundContext()),client:MealCoachConfiguration.development().map(DailyMealReviewClient.live)))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:12) {
                CompanionAnimationView(clip:controller.isLoading ? .thinking : (controller.record==nil ? .idleBreathing : .encouraging),reduceMotion:reduceMotion,playbackRevision:controller.isLoading ? 1 : 0,isActive:scenePhase == .active)
                    .frame(width:84,height:84).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5) {
                    Text("냠냠이의 하루 식단 이야기").font(.headline)
                    Label("AI 영양 안내",systemImage:"sparkles").font(.caption.bold()).foregroundStyle(RebuildDesignTokens.forest700)
                    Text(meal.date+" · 점심").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let record=controller.record ?? controller.unsaved {
                report(record)
                if controller.unsaved != nil {
                    Button("기기에 다시 저장하기") {controller.retrySave()}.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("daily_review_retry_save")
                }
            } else {
                Text(controller.eligibilityMessage).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                if controller.hasClient && controller.canGenerate {
                    Toggle("AI 전송에 동의하고 식단 해설 받기",isOn:$consent).font(.subheadline)
                        .accessibilityIdentifier("daily_review_consent")
                    Text("AI 안내 · OpenCode Go에 익명 메뉴 ID·대표 영양소·확인된 전체 영양량·세션 식별자를 보내요. 이름·학교·메뉴 이름·날짜·먹은 기록·등록 알레르기는 보내지 않아요. 보호자와 함께 확인해 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {action=UUID()} label: {
                        Label(controller.isLoading ? "식단 이야기를 준비해요" : "오늘 식단 AI 해설 · 하루 1회",systemImage:"sparkles")
                            .font(.subheadline.bold()).frame(maxWidth:.infinity,minHeight:48)
                    }.buttonStyle(.borderedProminent).tint(RebuildDesignTokens.forest700)
                        .disabled(!consent || controller.isLoading).accessibilityIdentifier("daily_review_generate")
                }
                if controller.isLoading {ProgressView("냠냠이가 식단을 살펴보고 있어요")}
                if !controller.isLoading {
                    let basic=MealCoachAnswer.basic(question:.overview,nutrientIDs:MealCoachRequest.nutrientIDs(meal:meal,selectedIndex:-1))
                    section("기본 영양 안내",body:basic.summary+"\n"+basic.benefit)
                }
            }
            if let notice=controller.notice {Text(notice).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("daily_review_notice")}
            if showsSourceNutrition {sourceNutrition(controller.record?.meal ?? meal)}
            Text("영양 교육용 참고 안내이며 실제 영양사·의료 상담을 대신하지 않아요. 대표 영양소는 메뉴를 바탕으로 한 추정이며, 실제 먹은 양과 다를 수 있어요.")
                .font(.caption).foregroundStyle(.secondary)
            Text("평가는 이 기기에 보관돼요. 앱 삭제·기기 교체 시 복구를 보장하지 않아요.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth:.infinity,alignment:.leading)
        .background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))
        .accessibilityIdentifier("daily_review_card")
        .task {controller.load()}
        .task(id:action) {
            guard let current=action else{return}
            defer{if action==current {action=nil}}
            await controller.generate(consent:consent)
        }
        .onChange(of:consent) {_ in action=nil}
        .onChange(of:allergies) {codes in action=nil;controller.updateAllergies(codes)}
    }
    private func report(_ record:DailyMealReviewRecord) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Label("AI가 생성한 영양 안내",systemImage:"sparkles").font(.subheadline.bold()).foregroundStyle(RebuildDesignTokens.forest700)
                .accessibilityIdentifier("daily_review_ai_source")
            Text("생성: "+record.response.generatedAt).font(.caption).foregroundStyle(.secondary)
            if record.meal != meal {Text("평가 당시 식단이에요. 현재 급식표 내용과 다를 수 있어요.").font(.footnote).foregroundStyle(.orange)}
            section("오늘 식단의 특징",body:record.response.summary)
            section("만날 수 있는 영양소",body:record.response.benefit)
            VStack(alignment:.leading,spacing:8) {
                Text("눈여겨볼 메뉴").font(.subheadline.bold())
                let highlights=DailyMealReviewFactory.visibleHighlights(record,allergies:allergies)
                ForEach(highlights,id:\.itemId) {highlight in
                    if let index=Int(highlight.itemId.dropFirst()),record.meal.menuItems.indices.contains(index) {
                        Label(record.meal.menuItems[index].normalizedPresentationName,systemImage:"leaf.fill").font(.subheadline.bold())
                        Text(DailyMealReviewFactory.role(highlight.nutrient)).font(.body)
                    }
                }
                if highlights.isEmpty {Text("현재 알레르기와 확인 가능한 정보를 고려해 추천 메뉴를 표시하지 않아요.").font(.footnote).foregroundStyle(.secondary)}
                if highlights.count<record.response.highlights.count {Text("현재 등록 알레르기와 관련된 메뉴의 추천은 숨겼어요. 보호자·선생님에게 확인해 주세요.").font(.footnote).foregroundStyle(.red)}
            }
            section("남겼다면 이렇게 보완해요",body:record.response.tip)
            Text(record.response.caution).font(.footnote).foregroundStyle(.secondary)
            if controller.record != nil {Label("기기에 저장됨 · 다시 보기는 횟수 제한 없어요",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(RebuildDesignTokens.forest700)}
        }.fixedSize(horizontal:false,vertical:true)
    }
    private func section(_ title:String,body:String) -> some View {
        VStack(alignment:.leading,spacing:7) {Text(title).font(.subheadline.bold());Text(body).font(.body)}
    }
    private func sourceNutrition(_ meal:RebuildMealDay) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text("급식 제공 영양정보 · 식단 전체").font(.subheadline.bold())
            if !meal.calorie.isEmpty {Text(meal.calorie).font(.footnote)}
            let values=MealCoachRequest.wholeMealValues(meal)
            ForEach(["protein","carbs","fat"],id:\.self) {key in
                if let value=values[key] {Text("\(["protein":"단백질","carbs":"탄수화물","fat":"지방"][key] ?? key) \(value,specifier:"%.1f") g").font(.footnote)}
            }
            if values.isEmpty && meal.calorie.isEmpty {Text("제공된 수량 정보가 없어요.").font(.footnote).foregroundStyle(.secondary)}
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(RebuildDesignTokens.cream50,in:RoundedRectangle(cornerRadius:16))
    }
}
