import PhotosUI
import SwiftUI
import UIKit

struct TodayMealView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedItem: MealItem?
    @State private var recordingItem: MealItem?
    @State private var challengeOutcome: ChallengeOutcome?
    @State private var recordNotice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if appState.isLoadingMeals {
                        ProgressView("급식 정보를 불러오는 중")
                            .frame(maxWidth: .infinity)
                    }

                    if let message = appState.mealMessage {
                        mealStatusBanner(status: appState.mealStatus, message: message)
                    }

                    if let recordNotice {
                        recordBanner(recordNotice)
                    }

                    if let meal = appState.todayMeal {
                        nutritionSummary(meal)

                        ForEach(meal.menuItems) { item in
                            MealCard(item: item, isAllergyRisk: appState.isAllergyRisk(item)) {
                                recordNotice = nil
                                appState.recordSkipped(item, date: meal.date)
                                selectedItem = item
                            } onChallenge: {
                                recordNotice = nil
                                guard !appState.isAllergyRisk(item) else {
                                    recordNotice = "선택한 알레르기와 관련된 메뉴예요. 보호자와 학교 안내를 꼭 확인해 주세요."
                                    return
                                }
                                challengeOutcome = appState.recordMealInteraction(item: item, date: meal.date, status: .oneBite)
                            } onAlreadyEats: {
                                challengeOutcome = appState.recordAlreadyEats(item, date: meal.date)
                                recordNotice = "\(item.name)은 잘 먹는 메뉴로 기록했어요."
                            } onRecord: {
                                recordingItem = item
                            }
                        }
                    } else {
                        emptyState
                    }

                    cautionCard
                }
                .padding(20)
            }
            .navigationTitle("오늘 급식")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .refreshable {
                await appState.loadMeals()
            }
            .sheet(item: $selectedItem) { item in
                MealLossDetailView(item: item, isChallengeLocked: appState.isAllergyRisk(item)) {
                    selectedItem = nil
                    guard !appState.isAllergyRisk(item) else {
                        recordNotice = "선택한 알레르기와 관련된 메뉴예요. 한 입 도전보다 안전 확인이 먼저예요."
                        return
                    }
                    challengeOutcome = appState.recordMealInteraction(item: item, date: appState.todayMeal?.date ?? DateUtils.apiString(from: Date()), status: .oneBite)
                }
            }
            .sheet(item: $recordingItem) { item in
                MealRecordSheet(item: item, date: appState.todayMeal?.date ?? DateUtils.apiString(from: Date())) { outcome, notice in
                    challengeOutcome = outcome
                    recordNotice = notice
                }
                .environmentObject(appState)
            }
            .sheet(item: $challengeOutcome) { outcome in
                LevelUpResultView(outcome: outcome)
            }
        }
    }

    private var header: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    CharacterAvatar(skin: appState.progress.currentSkin, size: 70)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateUtils.displayDateFormatter.string(from: Date()))
                            .font(AppTypography.headline)
                        Text(appState.profile?.schoolName ?? "학교 선택 전")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                Text("안 먹고 싶은 반찬을 누르면 놓칠 수 있는 영양소를 쉽게 알려줘요.")
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nutritionSummary(_ meal: MealDay) -> some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("전체 영양 정보")
                        .font(AppTypography.headline)
                    Spacer()
                    Text(meal.calorie)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.orange)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                    ForEach(meal.nutrition.summaryRows, id: \.0) { row in
                        VStack(spacing: 4) {
                            Text(row.0)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.graySecondary)
                            Text(row.1)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.textDark)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppColors.primaryGreen.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func mealStatusBanner(status: MealDataState, message: String) -> some View {
        let config = statusBannerConfig(for: status)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: config.icon)
                .foregroundStyle(config.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(config.title)
                    .font(.caption.weight(.bold))
                Text(message)
                    .font(AppTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(config.color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func recordBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.primaryGreen)
            Text(message)
                .font(AppTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(AppColors.primaryGreen.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyState: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(emptyStateTitle)
                    .font(AppTypography.headline)
                Text(emptyStateMessage)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton("다시 불러오기", systemImage: "arrow.clockwise") {
                    Task { await appState.loadMeals() }
                }
            }
        }
    }

    private func statusBannerConfig(for status: MealDataState) -> (title: String, icon: String, color: Color) {
        switch status {
        case .live:
            return ("실제 급식 정보", "checkmark.circle.fill", AppColors.primaryGreen)
        case .missingAPIKey:
            return ("API 키 없음", "key.fill", AppColors.orange)
        case .error:
            return ("API 연결 실패", "wifi.exclamationmark", AppColors.orange)
        case .noMeal:
            return ("급식 데이터 없음", "calendar.badge.exclamationmark", AppColors.graySecondary)
        case .sampleSchool:
            return ("샘플 학교 선택됨", "building.columns.fill", AppColors.orange)
        case .demo:
            return ("체험 모드", "tray.fill", AppColors.orange)
        }
    }

    private var emptyStateTitle: String {
        switch appState.mealStatus {
        case .error:
            return "급식 정보를 불러오지 못했어요"
        case .missingAPIKey:
            return "API 키가 필요해요"
        case .sampleSchool:
            return "실제 학교를 선택해 주세요"
        case .noMeal:
            return "오늘 급식 데이터가 없어요"
        case .live, .demo:
            return "급식 정보가 아직 없어요"
        }
    }

    private var emptyStateMessage: String {
        if let message = appState.mealMessage {
            return message
        }
        return "잠시 후 다시 시도하거나 설정에서 학교 선택이 맞는지 확인해 주세요."
    }

    private var cautionCard: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("안내")
                    .font(AppTypography.headline)
                Text("영양소 안내는 의학 진단이 아니라 교육용 참고 안내예요.\n알레르기 정보는 반드시 보호자와 학교 안내를 함께 확인해 주세요.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MealRecordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var item: MealItem
    var date: String
    var onComplete: (ChallengeOutcome?, String) -> Void

    @State private var status: EatingStatus
    @State private var selectedReasons: Set<DifficultyReason> = []
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var localPhotos: [MealPhotoRecord] = []
    @State private var shareWithParent = false
    @State private var photoMessage: String?
    @State private var showingCamera = false

    init(item: MealItem, date: String, onComplete: @escaping (ChallengeOutcome?, String) -> Void) {
        self.item = item
        self.date = date
        self.onComplete = onComplete
        _status = State(initialValue: .oneBite)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("먹은 정도") {
                    Picker("먹은 정도", selection: $status) {
                        ForEach(availableStatuses) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if status == .difficultToday || status == .smelledOnly || status == .allergyAvoided {
                    Section("어려운 이유") {
                        ForEach(DifficultyReason.allCases) { reason in
                            Toggle(reason.title, isOn: reasonBinding(reason))
                        }
                    }
                }

                if appState.isAllergyRisk(item) {
                    Section("알레르기 주의") {
                        Text("선택한 알레르기와 관련된 메뉴예요. 보호자와 학교 안내를 꼭 확인해 주세요.")
                        Text("안전하게 피한 기록은 안전 XP로 인정되고, 한 입 도전은 잠겨요.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                        Text("이 앱은 알레르기 안전을 보장하지 않으며, 학교 안내를 우선해야 합니다.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                } else if !item.allergyCodes.isEmpty {
                    Section("알레르기 정보") {
                        Text("급식 원문에 알레르기 번호가 표시된 메뉴예요. 선택한 알레르기와 직접 겹치지는 않지만 학교 안내를 함께 확인해 주세요.")
                        Text("이 앱은 알레르기 안전을 보장하지 않으며, 학교 안내를 우선해야 합니다.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                }

                Section("급식판 사진") {
                    Text("급식판만 찍어주세요. 친구 얼굴, 이름표, 반/번호가 나오지 않게 조심해 주세요.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("사진 선택", systemImage: "photo")
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("사진 찍기", systemImage: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    Toggle("부모에게 이 사진 공유", isOn: $shareWithParent)
                    if let photoMessage {
                        Text(photoMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                    ForEach(localPhotos) { photo in
                        HStack {
                            Label(photo.fileName, systemImage: photo.isSharedWithParent ? "person.2.fill" : "iphone")
                                .font(AppTypography.caption)
                            Spacer()
                            Button(role: .destructive) {
                                appState.deleteMealPhoto(photo)
                                localPhotos.removeAll { $0.id == photo.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }

                Section("저장") {
                    Button {
                        save()
                    } label: {
                        Label("기록 저장", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                Task { await importPhoto(newItem) }
            }
            .onAppear {
                if appState.isAllergyRisk(item), status == .oneBite {
                    status = .allergyAvoided
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { data in
                    savePhotoData(data)
                }
            }
        }
    }

    private var availableStatuses: [EatingStatus] {
        if appState.isAllergyRisk(item) {
            return EatingStatus.allCases.filter { $0 != .oneBite }
        }
        return EatingStatus.allCases
    }

    private func reasonBinding(_ reason: DifficultyReason) -> Binding<Bool> {
        Binding {
            selectedReasons.contains(reason)
        } set: { isSelected in
            if isSelected {
                selectedReasons.insert(reason)
            } else {
                selectedReasons.remove(reason)
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoMessage = "사진 데이터를 읽지 못했어요."
                return
            }
            savePhotoData(data)
        } catch {
            photoMessage = "사진을 가져오지 못했어요."
        }
    }

    private func savePhotoData(_ data: Data) {
        do {
            let record = try appState.saveMealPhotoData(data, sharedWithParent: shareWithParent)
            localPhotos.insert(record, at: 0)
            photoMessage = shareWithParent ? "사진을 저장했고 부모 공유가 켜져 있어요." : "사진을 내 기기에 저장했어요."
        } catch {
            photoMessage = "사진 저장에 실패했어요."
        }
    }

    private func save() {
        let finalStatus = appState.isAllergyRisk(item) && status == .oneBite ? EatingStatus.allergyAvoided : status
        let outcome = appState.recordMealInteraction(
            item: item,
            date: date,
            status: finalStatus,
            reasons: Array(selectedReasons).sorted { $0.rawValue < $1.rawValue },
            photoIds: localPhotos.map(\.id),
            shareWithParent: shareWithParent
        )
        let xpText = outcome.map { " · +\($0.gainedExp) XP" } ?? ""
        onComplete(outcome, "\(item.name)을 '\(finalStatus.title)'로 기록했어요\(xpText).")
        dismiss()
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onCapture: (Data) -> Void
        var dismiss: DismissAction

        init(onCapture: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.82) {
                onCapture(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
