import SwiftUI

struct MealRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: TodayForestViewModel

    @State private var difficultItem: RebuildMealItem?
    @State private var selectedReasons: [RebuildDifficultyReason] = []
    @State private var guardianItem: RebuildMealItem?
    @State private var savedMenuNames = Set<String>()
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let difficultItem {
                    difficultyReasonStep(for: difficultItem)
                } else {
                    menuList
                }
            }
            .background(RebuildDesignTokens.cream50)
            .navigationTitle(difficultItem == nil ? "급식 기록" : "어려운 이유")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if difficultItem != nil {
                        Button("메뉴로") {
                            self.difficultItem = nil
                            selectedReasons = []
                        }
                        .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                        .accessibilityLabel("메뉴 기록 목록으로 돌아가기")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .frame(minHeight: RebuildDesignTokens.minimumActionSize)
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
                    "\(item.name)은 선택한 알레르기와 관련될 수 있어요. "
                        + "학교 알레르기 안내와 보호자의 판단을 우선해 주세요."
                )
            }
        }
    }

    private var menuList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                if let saveMessage {
                    Text(saveMessage)
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
                        .accessibilityIdentifier("meal_recording_feedback")
                }

                Text(
                    "사진은 선택 사항이에요. 이전에 저장한 급식판 사진 정보는 "
                        + "새 기록에도 그대로 유지돼요."
                )
                .font(.footnote)
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(Array((viewModel.meal?.menuItems ?? []).enumerated()), id: \.offset) {
                    index, item in
                    menuCard(item, index: index)
                }
            }
            .padding(RebuildDesignTokens.spacing[4])
        }
    }

    private func menuCard(
        _ item: RebuildMealItem,
        index: Int
    ) -> some View {
        let isRisk = viewModel.isAllergyRisk(item)
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
                Text(item.name)
                    .font(RebuildDesignTokens.titleFont.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if savedMenuNames.contains(item.name) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(RebuildDesignTokens.forest500)
                        .accessibilityLabel("기록 완료")
                }
            }

            if isRisk {
                allergySafetyActions(for: item)
            }

            Text("어떻게 만났나요?")
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(RebuildDesignTokens.ink900)

            LazyVGrid(
                columns: dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.flexible())]
                    : [GridItem(.adaptive(minimum: 132), spacing: 8)],
                spacing: 8
            ) {
                ForEach(TodayForestViewModel.activeStatuses, id: \.self) {
                    status in
                    statusButton(status, item: item)
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
        .accessibilityIdentifier("meal_item_\(index)")
    }

    private func allergySafetyActions(
        for item: RebuildMealItem
    ) -> some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
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
                title: "안전하게 피했어요",
                foreground: .white,
                background: RebuildDesignTokens.danger700,
                enabled: !isSaving,
                accessibilityHint: "알레르기 회피로 안전하게 기록합니다"
            ) {
                save(item: item, status: .allergyAvoided)
            }
            actionButton(
                title: "보호자와 확인하기",
                foreground: RebuildDesignTokens.danger700,
                background: RebuildDesignTokens.danger700.opacity(0.10),
                enabled: true,
                accessibilityHint: "보호자 확인 안내를 엽니다"
            ) {
                guardianItem = item
            }
        }
        .padding(RebuildDesignTokens.spacing[3])
        .background(RebuildDesignTokens.danger700.opacity(0.08))
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
        )
    }

    private func statusButton(
        _ status: RebuildEatingStatus,
        item: RebuildMealItem
    ) -> some View {
        let enabled = viewModel.isStatusEnabled(status, for: item) && !isSaving
        return actionButton(
            title: status.childTitle,
            foreground: enabled
                ? RebuildDesignTokens.ink900
                : RebuildDesignTokens.muted600,
            background: enabled
                ? RebuildDesignTokens.leaf300.opacity(0.34)
                : RebuildDesignTokens.cream100,
            enabled: enabled,
            accessibilityHint: enabled
                ? "\(item.name)을 \(status.childTitle) 상태로 기록합니다"
                : "알레르기 주의 메뉴에서는 한입도전할 수 없습니다"
        ) {
            if status == .difficultToday {
                difficultItem = item
                selectedReasons = []
            } else {
                save(item: item, status: status)
            }
        }
        .accessibilityIdentifier("status_\(status.rawValue)")
    }

    private func difficultyReasonStep(
        for item: RebuildMealItem
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                Text(item.name)
                    .font(RebuildDesignTokens.titleFont.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

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
                    title: "이대로 기록하기",
                    foreground: .white,
                    background: RebuildDesignTokens.forest700,
                    enabled: !isSaving,
                    accessibilityHint: "선택한 이유와 함께 오늘은 어려워요로 기록합니다"
                ) {
                    save(
                        item: item,
                        status: .difficultToday,
                        reasons: selectedReasons
                    )
                }
            }
            .padding(RebuildDesignTokens.spacing[4])
        }
    }

    private func actionButton(
        title: String,
        foreground: Color,
        background: Color,
        enabled: Bool,
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
        .accessibilityLabel(title)
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

    private func save(
        item: RebuildMealItem,
        status: RebuildEatingStatus,
        reasons: [RebuildDifficultyReason] = []
    ) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                let result = try await viewModel.record(
                    item: item,
                    status: status,
                    difficultyReasons: reasons
                )
                savedMenuNames.insert(item.name)
                saveMessage = result.xpGranted > 0
                    ? "\(item.name) 기록 완료 · \(result.xpGranted) XP"
                    : "\(item.name) 기록을 저장했어요."
                difficultItem = nil
                selectedReasons = []
            } catch {
                saveMessage = "기록을 저장하지 못했어요. 다시 시도해 주세요."
            }
            isSaving = false
        }
    }
}

private extension RebuildEatingStatus {
    var childTitle: String {
        switch self {
        case .finished: return "다 먹었어요"
        case .oneBite: return "한입도전"
        case .half: return "절반 먹었어요"
        case .smelledOnly: return "냄새만 맡아봤어요"
        case .difficultToday: return "오늘은 어려워요"
        case .allergyAvoided: return "안전하게 피했어요"
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
