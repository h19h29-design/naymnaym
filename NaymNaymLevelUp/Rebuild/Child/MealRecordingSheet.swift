import SwiftUI

struct MealRecordingReviewDraft: Equatable, Sendable {
    let item: RebuildMealItem
    let preparedRecord: PreparedMealRecord
}

struct MealRecordingReviewState: Equatable, Sendable {
    private(set) var draft: MealRecordingReviewDraft?

    mutating func present(_ draft: MealRecordingReviewDraft) {
        self.draft = draft
    }

    mutating func cancel() {
        draft = nil
    }
}

@MainActor
enum MealRecordingActionLayout {
    struct Descriptor: Equatable {
        let columnCount: Int
        let minimumHitDimension: CGFloat
        let statuses: [RebuildEatingStatus]
        let statusIdentifiers: [String]
    }

    static func gridStatuses(
        isAllergyRisk: Bool
    ) -> [RebuildEatingStatus] {
        guard isAllergyRisk else {
            return TodayForestViewModel.activeStatuses
        }
        return TodayForestViewModel.activeStatuses.filter {
            $0 != .allergyAvoided
        }
    }

    static func recommendedStatuses(
        isAllergyRisk: Bool
    ) -> [RebuildEatingStatus] {
        isAllergyRisk ? [.allergyAvoided] : []
    }

    static func descriptor(
        isAccessibilitySize: Bool,
        isAllergyRisk: Bool,
        menuIndex: Int,
        item: RebuildMealItem
    ) -> Descriptor {
        let statuses = gridStatuses(isAllergyRisk: isAllergyRisk)
        return Descriptor(
            columnCount: isAccessibilitySize ? 1 : 2,
            minimumHitDimension: RebuildDesignTokens.minimumActionSize,
            statuses: statuses,
            statusIdentifiers: statuses.map {
                MealRecordingAccessibilityID.status(
                    menuIndex: menuIndex,
                    item: item,
                    status: $0
                )
            }
        )
    }
}

enum MealRecordingAccessibilityID {
    static let nutritionReview = "meal_recording_nutrition_review"
    static let confirm = "meal_recording_confirm"
    static let cancel = "meal_recording_cancel"

    static func status(
        menuIndex: Int,
        item: RebuildMealItem,
        status: RebuildEatingStatus
    ) -> String {
        "meal_recording_status_\(menuToken(index: menuIndex, item: item))_\(status.rawValue)"
    }

    static func allergyAvoidance(
        menuIndex: Int,
        item: RebuildMealItem
    ) -> String {
        "meal_allergy_safe_choice_\(menuToken(index: menuIndex, item: item))"
    }

    static func guardianCheck(
        menuIndex: Int,
        item: RebuildMealItem
    ) -> String {
        "meal_guardian_check_\(menuToken(index: menuIndex, item: item))"
    }

    private static func menuToken(
        index: Int,
        item: RebuildMealItem
    ) -> String {
        let identity = MealRecordIdentityNormalizer.normalizedMenuName(
            item.name
        )
        let safeIdentity = identity.map { character in
            character.isLetter || character.isNumber
                ? String(character)
                : "_"
        }.joined()
        return "\(index)_\(safeIdentity)"
    }
}

struct MealRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: TodayForestViewModel

    @State private var difficultItem: RebuildMealItem?
    @State private var selectedReasons: [RebuildDifficultyReason] = []
    @State private var guardianItem: RebuildMealItem?
    @State private var reviewState = MealRecordingReviewState()
    @State private var savedMenuNames = Set<String>()
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var savedNutritionGuidance: NutrientImpactGuidance?

    private var reviewDraft: MealRecordingReviewDraft? {
        reviewState.draft
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let saveMessage {
                    recordingFeedback(saveMessage)
                }
                Group {
                    if let reviewDraft {
                        nutritionReviewStep(reviewDraft)
                    } else if let difficultItem {
                        difficultyReasonStep(for: difficultItem)
                    } else {
                        menuList
                    }
                }
            }
            .background(RebuildDesignTokens.cream50)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if reviewDraft != nil {
                        Button("선택으로") {
                            cancelNutritionReview()
                        }
                        .frame(
                            minWidth: RebuildDesignTokens.minimumActionSize,
                            minHeight: RebuildDesignTokens.minimumActionSize
                        )
                        .accessibilityLabel("영양 확인을 취소하고 메뉴로 돌아가기")
                    } else if difficultItem != nil {
                        Button("메뉴로") {
                            self.difficultItem = nil
                            selectedReasons = []
                        }
                        .frame(
                            minWidth: RebuildDesignTokens.minimumActionSize,
                            minHeight: RebuildDesignTokens.minimumActionSize
                        )
                        .accessibilityLabel("메뉴 기록 목록으로 돌아가기")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .frame(
                            minWidth: RebuildDesignTokens.minimumActionSize,
                            minHeight: RebuildDesignTokens.minimumActionSize
                        )
                        .accessibilityLabel("급식 기록 닫기")
                }
            }
            .alert(
                "보호자와 먼저 확인해 주세요",
                isPresented: Binding(
                    get: { guardianItem != nil },
                    set: { if !$0 { guardianItem = nil } }
                ),
                presenting: guardianItem
            ) { _ in
                Button("확인했어요", role: .cancel) {
                    guardianItem = nil
                }
            } message: { item in
                Text(
                    "‘\(item.name)’ 메뉴가 선택한 알레르기와 관련될 수 있어요. "
                        + "학교 알레르기 안내와 보호자의 판단을 우선해 주세요."
                )
            }
        }
    }

    private var navigationTitle: String {
        if reviewDraft != nil {
            return "영양 확인"
        }
        return difficultItem == nil ? "급식 기록" : "어려운 이유"
    }

    private var menuList: some View {
        let menuItems = Array((viewModel.meal?.menuItems ?? []).enumerated())
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                if let savedNutritionGuidance {
                    savedGuidanceCard(savedNutritionGuidance)
                }

                Text(
                    "사진은 선택 사항이에요. 이전에 저장한 급식판 사진 정보는 "
                        + "새 기록에도 그대로 유지돼요."
                )
                .font(.footnote)
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(menuItems, id: \.offset) { index, item in
                    VStack(spacing: RebuildDesignTokens.spacing[3]) {
                        menuOverview(item, index: index)
                        menuActions(item, index: index)
                    }
                }

                if let meal = viewModel.meal {
                    let totals = MealWholeMealTotals(meal: meal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(totals.sourceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RebuildDesignTokens.forest700)
                        Text(totals.calorie)
                            .font(.footnote)
                            .foregroundStyle(RebuildDesignTokens.muted600)
                        Text(totals.nutritionSummary)
                            .font(.caption2)
                            .foregroundStyle(RebuildDesignTokens.muted600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(RebuildDesignTokens.spacing[3])
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RebuildDesignTokens.cream50.opacity(0.72))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: RebuildDesignTokens.radii[0],
                            style: .continuous
                        )
                    )
                    .accessibilityElement(children: .combine)
                }

            }
            .padding(RebuildDesignTokens.spacing[4])
        }
    }

    private func menuOverview(
        _ item: RebuildMealItem,
        index: Int
    ) -> some View {
        let isRisk = viewModel.isAllergyRisk(item)
        let visual = MealVisualResolver.resolve(item: item)
        let allergyStyle = MealAllergyVisualStyle.resolve(for: item)
        let accessibility = MealAccessibilityDescriptor(
            item: item,
            visual: visual,
            currentState: savedMenuNames.contains(item.name)
                ? "기록 완료"
                : "기록하지 않음"
        )
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
                MealVisualIcon(iconKey: visual.iconKey)
                    .font(.title2)
                    .foregroundStyle(
                        isRisk
                            ? RebuildDesignTokens.danger700
                            : RebuildDesignTokens.forest700
                    )
                    .frame(width: 56, height: 56)
                    .background(
                        RebuildDesignTokens.semanticPalette(.appetite).surface
                    )
                    .clipShape(Circle())

                Text(item.name)
                    .font(RebuildDesignTokens.titleFont.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if savedMenuNames.contains(item.name) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(RebuildDesignTokens.forest500)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 6) {
                Text(visual.categoryLabel)
                Text(visual.confidenceLabel)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(RebuildDesignTokens.forest700)

            MealNutrientChips(
                nutrientIDs: visual.representativeNutrientIDs
            )

            Text(visual.representativeCopy)
                .font(.caption)
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)

            if !item.allergyLabels.isEmpty {
                Label(
                    allergyStyle.title,
                    systemImage: allergyStyle.systemImage
                )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.danger700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility.spokenLabel)
        .padding(RebuildDesignTokens.spacing[3])
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
            .stroke(
                isRisk
                    ? RebuildDesignTokens.danger700.opacity(0.45)
                    : RebuildDesignTokens.cream100,
                lineWidth: isRisk ? 2 : 1
            )
        }
        .accessibilityIdentifier("meal_item_\(index)")
    }

    private func menuActions(
        _ item: RebuildMealItem,
        index: Int
    ) -> some View {
        let isRisk = viewModel.isAllergyRisk(item)
        let actionDescriptor = MealRecordingActionDescriptor(menuName: item.name)
        let layout = MealRecordingActionLayout.descriptor(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isAllergyRisk: isRisk,
            menuIndex: index,
            item: item
        )
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            Text(actionDescriptor.prompt)
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(RebuildDesignTokens.ink900)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("meal_action_prompt_\(index)")

            if isRisk {
                allergySafetyActions(for: item, index: index)
            }

            LazyVGrid(
                columns: layout.columnCount == 1
                    ? [GridItem(.flexible())]
                    : [GridItem(.adaptive(minimum: 132), spacing: 8)],
                spacing: 8
            ) {
                ForEach(layout.statuses, id: \.self) {
                    status in
                    statusButton(
                        status,
                        item: item,
                        index: index,
                        minimumHitDimension: layout.minimumHitDimension
                    )
                }
            }
        }
        .padding(RebuildDesignTokens.spacing[3])
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
            .stroke(
                isRisk
                    ? RebuildDesignTokens.danger700.opacity(0.45)
                    : RebuildDesignTokens.cream100,
                lineWidth: isRisk ? 2 : 1
            )
        }
        .accessibilityIdentifier("meal_item_actions_\(index)")
    }

    private func allergySafetyActions(
        for item: RebuildMealItem,
        index: Int
    ) -> some View {
        let actionDescriptor = MealRecordingActionDescriptor(menuName: item.name)
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            Label(
                "알레르기 안전을 먼저 확인해 주세요",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(RebuildDesignTokens.headlineFont)
            .foregroundStyle(RebuildDesignTokens.danger700)
            .fixedSize(horizontal: false, vertical: true)

            Text("먹기 권유보다 학교 안내와 보호자의 판단이 먼저예요.")
                .font(RebuildDesignTokens.bodyFont)
                .foregroundStyle(RebuildDesignTokens.ink900)
                .fixedSize(horizontal: false, vertical: true)

            actionButton(
                title: RebuildEatingStatus.allergyAvoided.childTitle,
                foreground: .white,
                background: RebuildDesignTokens.danger700,
                enabled: !isSaving,
                accessibilityLabel: actionDescriptor.allergyAvoidanceLabel,
                accessibilityHint: actionDescriptor.allergyAvoidanceHint
            ) {
                prepare(item: item, status: .allergyAvoided)
            }
            .accessibilityIdentifier(
                MealRecordingAccessibilityID.allergyAvoidance(
                    menuIndex: index,
                    item: item
                )
            )
            actionButton(
                title: "보호자와 확인하기",
                foreground: RebuildDesignTokens.danger700,
                background: RebuildDesignTokens.danger700.opacity(0.10),
                enabled: true,
                accessibilityLabel: actionDescriptor.guardianConfirmationLabel,
                accessibilityHint: actionDescriptor.guardianConfirmationHint
            ) {
                guardianItem = item
            }
            .accessibilityIdentifier(
                MealRecordingAccessibilityID.guardianCheck(
                    menuIndex: index,
                    item: item
                )
            )
        }
        .padding(RebuildDesignTokens.spacing[3])
        .background(RebuildDesignTokens.danger700.opacity(0.08))
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
            .stroke(RebuildDesignTokens.danger700, lineWidth: 2)
        }
    }

    private func statusButton(
        _ status: RebuildEatingStatus,
        item: RebuildMealItem,
        index: Int,
        minimumHitDimension: CGFloat
    ) -> some View {
        let enabled = viewModel.isStatusEnabled(status, for: item) && !isSaving
        let actionDescriptor = MealRecordingActionDescriptor(menuName: item.name)
        return actionButton(
            title: status.childTitle,
            foreground: enabled
                ? RebuildDesignTokens.ink900
                : RebuildDesignTokens.muted600,
            background: enabled
                ? RebuildDesignTokens.leaf300.opacity(0.34)
                : RebuildDesignTokens.cream100,
            enabled: enabled,
            accessibilityLabel: actionDescriptor.controlLabel(
                for: status.childTitle
            ),
            accessibilityHint: actionDescriptor.statusHint(
                for: status,
                enabled: enabled
            )
        ) {
            if status == .difficultToday {
                difficultItem = item
                selectedReasons = []
            } else {
                prepare(item: item, status: status)
            }
        }
        .frame(minHeight: minimumHitDimension)
        .accessibilityIdentifier(
            MealRecordingAccessibilityID.status(
                menuIndex: index,
                item: item,
                status: status
            )
        )
    }

    private func savedGuidanceCard(
        _ guidance: NutrientImpactGuidance
    ) -> some View {
        let snapshot = guidance.snapshot
        return VStack(
            alignment: .leading,
            spacing: RebuildDesignTokens.spacing[2]
        ) {
            Text(guidance.source.childLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RebuildDesignTokens.forest700)
            Text(snapshot.headline)
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(RebuildDesignTokens.ink900)
                .fixedSize(horizontal: false, vertical: true)
            MealNutrientChips(nutrientIDs: snapshot.nutrients)
            Text(snapshot.explanation)
                .font(RebuildDesignTokens.bodyFont)
                .foregroundStyle(RebuildDesignTokens.ink900)
                .fixedSize(horizontal: false, vertical: true)
            Text(snapshot.disclaimer)
                .font(.footnote)
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meal_recording_saved_nutrition_guidance")
    }

    private func difficultyReasonStep(
        for item: RebuildMealItem
    ) -> some View {
        let visual = MealVisualResolver.resolve(item: item)
        let accessibility = MealAccessibilityDescriptor(
            item: item,
            visual: visual,
            currentState: "기록 이유 선택 중"
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
                    HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
                        MealVisualIcon(iconKey: visual.iconKey)
                            .font(.headline)
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(RebuildDesignTokens.titleFont.bold())
                                .foregroundStyle(RebuildDesignTokens.ink900)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            HStack(spacing: 6) {
                                Text(visual.categoryLabel)
                                Text(visual.confidenceLabel)
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RebuildDesignTokens.forest700)
                        }
                    }

                    MealNutrientChips(
                        nutrientIDs: visual.representativeNutrientIDs
                    )

                    Text(visual.representativeCopy)
                        .font(.caption)
                        .foregroundStyle(RebuildDesignTokens.muted600)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.allergyLabels.isEmpty {
                        let allergyStyle = MealAllergyVisualStyle.resolve(for: item)
                        Label(
                            allergyStyle.title,
                            systemImage: allergyStyle.systemImage
                        )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RebuildDesignTokens.danger700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibility.spokenLabel)

                Text("어떤 점이 어려웠나요?")
                    .font(RebuildDesignTokens.headlineFont)
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(
                    TodayForestViewModel.difficultyReasonOrder,
                    id: \.self
                ) { reason in
                    Button {
                        toggle(reason)
                    } label: {
                        HStack(alignment: .center, spacing: RebuildDesignTokens.spacing[2]) {
                            Image(
                                systemName: selectedReasons.contains(reason)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            Text(reason.childTitle)
                                .font(RebuildDesignTokens.bodyFont)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: RebuildDesignTokens.minimumActionSize,
                            alignment: .leading
                        )
                        .padding(.horizontal, RebuildDesignTokens.spacing[3])
                    }
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .background(RebuildDesignTokens.leaf300.opacity(0.24))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: RebuildDesignTokens.radii[0]
                        )
                    )
                    .accessibilityLabel(
                        "\(reason.childTitle), "
                            + (selectedReasons.contains(reason) ? "선택됨" : "선택 안 됨")
                    )
                }

                actionButton(
                    title: "영양 안내 확인하기",
                    foreground: .white,
                    background: RebuildDesignTokens.forest700,
                    enabled: !isSaving,
                    accessibilityHint: "선택한 이유를 유지하고 저장 전 영양 안내를 확인합니다"
                ) {
                    prepare(
                        item: item,
                        status: .difficultToday,
                        reasons: selectedReasons
                    )
                }
            }
            .padding(RebuildDesignTokens.spacing[4])
        }
    }

    private func nutritionReviewStep(
        _ draft: MealRecordingReviewDraft
    ) -> some View {
        let snapshot = draft.preparedRecord.nutritionSnapshot
        let status = draft.preparedRecord.command.status
        let isRisk = viewModel.isAllergyRisk(draft.item)
        return ScrollView {
            VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
                    Text(draft.item.name)
                        .font(RebuildDesignTokens.titleFont.bold())
                        .foregroundStyle(RebuildDesignTokens.ink900)
                        .accessibilityAddTraits(.isHeader)
                    Label(
                        status.childTitle,
                        systemImage: status == .allergyAvoided
                            ? "checkmark.shield.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(
                        status == .allergyAvoided
                            ? RebuildDesignTokens.danger700
                            : RebuildDesignTokens.forest700
                    )
                }

                if isRisk {
                    Label(
                        "알레르기 안전 선택을 확인했어요",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .font(RebuildDesignTokens.headlineFont)
                    .foregroundStyle(RebuildDesignTokens.danger700)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
                    Text(snapshot.headline)
                        .font(RebuildDesignTokens.headlineFont)
                        .foregroundStyle(RebuildDesignTokens.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                    MealNutrientChips(nutrientIDs: snapshot.nutrients)
                    Text(snapshot.explanation)
                        .font(RebuildDesignTokens.bodyFont)
                        .foregroundStyle(RebuildDesignTokens.ink900)
                        .fixedSize(horizontal: false, vertical: true)

                    if !snapshot.alternatives.isEmpty {
                        Text("같은 급식에서 함께 살펴볼 메뉴")
                            .font(RebuildDesignTokens.headlineFont)
                            .foregroundStyle(RebuildDesignTokens.forest700)
                        ForEach(snapshot.alternatives, id: \.self) { alternative in
                            Label(alternative, systemImage: "fork.knife")
                                .font(RebuildDesignTokens.bodyFont)
                                .foregroundStyle(RebuildDesignTokens.ink900)
                        }
                        Text("먹는 양이나 같은 영양을 보장하는 뜻은 아니에요.")
                            .font(.footnote)
                            .foregroundStyle(RebuildDesignTokens.muted600)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(snapshot.disclaimer)
                        .font(.footnote)
                        .foregroundStyle(RebuildDesignTokens.muted600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(RebuildDesignTokens.spacing[3])
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: RebuildDesignTokens.radii[1],
                        style: .continuous
                    )
                )

                actionButton(
                    title: "확인하고 저장하기",
                    foreground: .white,
                    background: RebuildDesignTokens.forest700,
                    enabled: !isSaving,
                    accessibilityHint: "검토한 상태와 영양 안내를 최종 저장합니다"
                ) {
                    confirm(draft)
                }
                .accessibilityIdentifier(MealRecordingAccessibilityID.confirm)

                actionButton(
                    title: "취소",
                    foreground: RebuildDesignTokens.forest700,
                    background: RebuildDesignTokens.cream100,
                    enabled: !isSaving,
                    accessibilityHint: "아무 것도 저장하지 않고 메뉴 선택으로 돌아갑니다"
                ) {
                    cancelNutritionReview()
                }
                .accessibilityIdentifier(MealRecordingAccessibilityID.cancel)
            }
            .padding(RebuildDesignTokens.spacing[4])
        }
        .accessibilityIdentifier(MealRecordingAccessibilityID.nutritionReview)
    }

    private func recordingFeedback(_ message: String) -> some View {
        Text(message)
            .font(RebuildDesignTokens.bodyFont)
            .foregroundStyle(RebuildDesignTokens.forest700)
            .fixedSize(horizontal: false, vertical: true)
            .padding(RebuildDesignTokens.spacing[3])
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RebuildDesignTokens.leaf300.opacity(0.28))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[0]
                )
            )
            .padding(.horizontal, RebuildDesignTokens.spacing[4])
            .padding(.top, RebuildDesignTokens.spacing[2])
            .accessibilityLabel("기록 안내: \(message)")
            .accessibilityIdentifier("meal_recording_feedback")
    }

    private func actionButton(
        title: String,
        foreground: Color,
        background: Color,
        enabled: Bool,
        accessibilityLabel: String? = nil,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(RebuildDesignTokens.headlineFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: RebuildDesignTokens.minimumActionSize
                )
                .padding(.horizontal, RebuildDesignTokens.spacing[2])
        }
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
        )
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(accessibilityHint)
    }

    private func toggle(_ reason: RebuildDifficultyReason) {
        if let index = selectedReasons.firstIndex(of: reason) {
            selectedReasons.remove(at: index)
        } else {
            selectedReasons.append(reason)
        }
        selectedReasons = TodayForestViewModel.orderedDifficultyReasons(
            selectedReasons
        )
    }

    private func prepare(
        item: RebuildMealItem,
        status: RebuildEatingStatus,
        reasons: [RebuildDifficultyReason] = []
    ) {
        guard !isSaving else { return }
        saveMessage = nil
        isSaving = true
        Task {
            do {
                let preparedRecord = try await viewModel.prepareRecord(
                    item: item,
                    status: status,
                    difficultyReasons: reasons
                )
                reviewState.present(
                    MealRecordingReviewDraft(
                        item: item,
                        preparedRecord: preparedRecord
                    )
                )
                difficultItem = nil
                selectedReasons = []
            } catch {
                saveMessage = "영양 안내를 준비하지 못했어요. 다시 시도해 주세요."
            }
            isSaving = false
        }
    }

    private func confirm(_ draft: MealRecordingReviewDraft) {
        guard !isSaving, reviewDraft == draft else { return }
        saveMessage = nil
        isSaving = true
        Task {
            do {
                let result = try await viewModel.record(
                    prepared: draft.preparedRecord
                )
                savedMenuNames.insert(draft.item.name)
                saveMessage = result.xpGranted > 0
                    ? "\(draft.item.name) 기록 완료 · \(result.xpGranted) XP"
                    : "\(draft.item.name) 기록을 저장했어요."
                savedNutritionGuidance = result.nutritionGuidance
                reviewState.cancel()
            } catch {
                saveMessage = "기록을 저장하지 못했어요. 다시 시도해 주세요."
            }
            isSaving = false
        }
    }

    private func cancelNutritionReview() {
        guard !isSaving else { return }
        reviewState.cancel()
        difficultItem = nil
        selectedReasons = []
    }
}

extension RebuildEatingStatus {
    var childTitle: String {
        switch self {
        case .finished: return "다 먹었어요"
        case .half: return "반 정도 먹었어요"
        case .oneBite: return "한 입 도전"
        case .smelledOnly: return "냄새만 맡았어요"
        case .difficultToday: return "오늘은 안 먹어요"
        case .allergyAvoided: return "알레르기로 피했어요"
        }
    }
}

private extension RebuildDifficultyReason {
    var childTitle: String {
        switch self {
        case .smell: return "냄새"
        case .texture: return "식감"
        case .taste: return "맛"
        case .appearance: return "모양"
        case .other: return "기타"
        case .spicy: return "매운맛"
        case .color: return "색"
        case .newFood: return "처음 보는 음식"
        case .allergy: return "알레르기"
        }
    }
}
