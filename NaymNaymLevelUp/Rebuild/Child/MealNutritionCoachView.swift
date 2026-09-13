import SwiftUI

struct MealNutritionCoachView: View {
    let meal: RebuildMealDay
    let registeredAllergyCodes: [Int]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedIndex = -1
    @State private var consent = false
    @State private var configuration: MealCoachConfiguration?
    @State private var result: MealCoachAnswer?
    @State private var action: CoachAction?
    @State private var isLoading = false
    @State private var failed = false
    @State private var sessionID = UUID()

    private struct CoachAction: Identifiable { let id = UUID(); let question: MealCoachQuestion }
    private var nutrientIDs: [String] { MealCoachRequest.nutrientIDs(meal: meal, selectedIndex: selectedIndex) }
    private var localAllergyWarning: Bool {
        let items = meal.menuItems.indices.contains(selectedIndex) ? [meal.menuItems[selectedIndex]] : meal.menuItems
        return items.contains { !Set($0.allergyCodes).isDisjoint(with: registeredAllergyCodes) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CompanionAnimationView(clip: isLoading ? .thinking : (result == nil ? .idleBreathing : .encouraging), reduceMotion: reduceMotion, playbackRevision: isLoading ? 1 : 0, isActive: scenePhase == .active)
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("냠냠이의 영양 이야기").font(.headline)
                    Text(result?.source == "ai" ? "AI가 풀어주는 식단 설명" : "기본 영양 안내 · AI 연결 전")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Picker("살펴볼 메뉴", selection: $selectedIndex) {
                Text("식단 전체").tag(-1)
                ForEach(Array(meal.menuItems.enumerated()), id: \.offset) { index, item in
                    Text(item.normalizedPresentationName).tag(index)
                }
            }.pickerStyle(.menu)
                .accessibilityIdentifier("meal_coach_menu")
            Text("먹었을 때와 남겼을 때를 가정해 알아봐요. 식사 기록과 경험치는 바뀌지 않아요.")
                .font(.footnote).foregroundStyle(.secondary)
            if localAllergyWarning {
                Label("등록한 알레르기와 관련된 메뉴예요. 먹기 전에 보호자·선생님에게 확인해 주세요.", systemImage: "shield.lefthalf.filled")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.red)
            }
            if configuration != nil {
                Toggle("영양소와 선택 질문을 AI에 보내기", isOn: $consent)
                    .font(.subheadline)
                Text("AI 안내 · OpenCode Go로 대표 영양소, 선택한 질문 종류, 세션 식별자를 전송해요. 식단 전체를 고른 경우에만 전체 영양량도 전송해요. 이름·학교·메뉴명·개인 기록·등록 알레르기는 보내지 않아요. 보호자와 함께 사용해 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(MealCoachQuestion.allCases) { question in
                Button { action = CoachAction(question: question) } label: {
                    HStack {
                        Text(question == .overview && selectedIndex >= 0 ? "이 메뉴 어때?" : question.title).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 44)
                }.buttonStyle(.bordered).tint(RebuildDesignTokens.forest700)
                    .disabled(isLoading).accessibilityIdentifier("meal_coach_\(question.rawValue)")
            }
            if isLoading { ProgressView("식단 이야기를 준비하고 있어요") }
            if failed { Text("AI 설명을 받지 못했어요. 기본 영양 안내로 보여드려요. 잠시 후 다시 시도할 수 있어요.").font(.footnote).foregroundStyle(.secondary) }
            if let result {
                VStack(alignment: .leading, spacing: 10) {
                    Text(result.source == "ai" ? "AI 설명" : "기본 영양 안내").font(.subheadline.bold())
                    Text(result.summary)
                    Text(result.benefit)
                    Text(result.caution).foregroundStyle(.secondary)
                    Text(result.tip)
                }.font(.body).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("meal_coach_answer")
            }
            Text("영양 교육용 참고 안내이며, 의료 상담이나 음식의 안전 보장이 아니에요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .task { configuration = MealCoachConfiguration.development() }
        .task(id: action?.id) {
            guard let action else { return }
            defer {
                // Consume this click on completion/cancellation; reappearing
                // must not silently replay a billable request.
                if self.action?.id == action.id { self.action = nil; isLoading = false }
            }
            failed = false
            let ids = nutrientIDs
            let fallback = MealCoachAnswer.basic(question: action.question, nutrientIDs: ids)
            // Allergies stay entirely local and bypass AI. No generated praise
            // about eating a personally flagged menu can override this branch.
            guard let configuration, consent, !localAllergyWarning else { result = fallback; return }
            isLoading = true; result = nil
            do {
                let payload = MealCoachRequest(question: action.question, nutrientIDs: ids, wholeMeal: MealCoachRequest.wholeMealValues(meal, selectedIndex: selectedIndex), sessionID: sessionID)
                let answer = try await MealCoachClient.live(configuration: configuration).answer(payload)
                try Task.checkCancellation()
                result = answer; isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                result = fallback; failed = true; isLoading = false
            }
        }
        .onChange(of: selectedIndex) { _ in reset() }
        .onChange(of: meal) { _ in selectedIndex = -1; consent = false; sessionID = UUID(); reset() }
        .onChange(of: consent) { _ in reset() }
        .onChange(of: registeredAllergyCodes) { _ in reset() }
    }

    private func reset() { action = nil; result = nil; failed = false; isLoading = false }
}
