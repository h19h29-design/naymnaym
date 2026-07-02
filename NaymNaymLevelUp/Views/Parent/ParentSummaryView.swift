import SwiftUI
import UIKit

struct ParentSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingInviteSheet = false
    @State private var showingChildInviteSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if appState.currentMode == .parent {
                        parentHeader
                        childCards
                        praiseCards
                        RoundedCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("이번 주 요약")
                                    .font(AppTypography.title)
                                Text(NutritionEstimator.makeParentSummary(records: recentRecords))
                                    .font(AppTypography.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        RoundedCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("가정에서 이렇게 도와주세요")
                                    .font(AppTypography.headline)
                                helperRow("과일을 함께 먹어요")
                                helperRow("김밥 속 채소를 늘려요")
                                helperRow("나물 반찬을 조금씩 도전해요")
                            }
                        }
                    } else {
                        childInviteHeader
                        childInviteSteps
                        parentPrivacyCard
                    }
                }
                .padding(20)
            }
            .navigationTitle(appState.currentMode == .parent ? "보호자 요약" : "보호자 초대")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground(theme: appState.currentTheme)
            .task {
                if appState.currentMode == .parent {
                    await appState.refreshParentSharedData()
                }
            }
        }
    }

    private var childInviteHeader: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("보호자 초대하기", systemImage: "person.crop.circle.badge.plus")
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.indigo)
                Text(childInviteDescription)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textDark)
                    .fixedSize(horizontal: false, vertical: true)
                inviteStatusBadge
                PrimaryButton(childInviteButtonTitle, systemImage: "paperplane.fill") {
                    showingChildInviteSheet = true
                }
                if let message = appState.parentSyncMessage {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(appState.parentSyncError == nil ? AppColors.graySecondary : AppColors.warningRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $showingChildInviteSheet) {
            ParentConnectionGuideView()
        }
    }

    private var childInviteDescription: String {
        if appState.childShareLink?.isCloudRegistered == true {
            return "초대 코드가 준비됐어요. 부모에게 보내면 부모 모드에서 바로 연결할 수 있어요."
        }
        return "부모가 아이의 먹은 정도, 한 입 도전 기록, 알레르기 주의, 선택 사진만 볼 수 있게 초대할 수 있어요."
    }

    private var childInviteButtonTitle: String {
        appState.childShareLink?.isCloudRegistered == true ? "초대 코드 보내기" : "초대 코드 만들기"
    }

    private var inviteStatusBadge: some View {
        let isReady = appState.childShareLink?.isCloudRegistered == true
        return Label(isReady ? "등록 완료" : "등록 필요", systemImage: isReady ? "checkmark.shield.fill" : "network")
            .font(AppTypography.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isReady ? AppColors.successGreen : AppColors.warningRed)
            .background((isReady ? AppColors.successGreen : AppColors.warningRed).opacity(0.10))
            .clipShape(Capsule())
    }

    private var childInviteSteps: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("초대 방법")
                    .font(AppTypography.headline)
                helperRow("아이 기기에서 초대 코드를 등록해요")
                helperRow("공유 버튼으로 부모에게 코드를 보내요")
                helperRow("부모는 아이 연결하기에서 붙여넣기만 하면 돼요")
            }
        }
    }

    private var parentPrivacyCard: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("공유되는 정보")
                    .font(AppTypography.headline)
                helperRow("먹은 정도와 한 입 도전 기록")
                helperRow("알레르기 주의 표시")
                helperRow("부모 공유를 켠 사진만")
                Text("반/번호, 개인 알레르기 메모, 전체 식사 기록은 공유 카드에 넣지 않아요.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var parentHeader: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("우리 아이들")
                            .font(AppTypography.title)
                        Text("아이 연결하기로 초대 코드를 붙여넣으면 공유된 기록만 확인할 수 있어요.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                    Spacer()
                    Button {
                        showingInviteSheet = true
                    } label: {
                        Label("아이 연결", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(hex: appState.currentTheme.primaryColorHex))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(hex: appState.currentTheme.primaryColorHex).opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("아이 연결하기")
                }
                Button {
                    Task { await appState.refreshParentSharedData() }
                } label: {
                    Label(appState.isParentSyncing ? "불러오는 중" : "아이 기록 새로고침", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .disabled(appState.isParentSyncing || appState.parentProfile.childLinks.isEmpty)

#if DEBUG
                Button {
                    appState.addLocalChildLink()
                    appState.parentSyncMessage = "이 기기에서만 보이는 테스트 연결을 추가했어요. 실제 보호자 기기 연동이 아닙니다."
                } label: {
                    Label("테스트 아이 추가", systemImage: "person.crop.circle.badge.plus")
                        .font(.caption.weight(.semibold))
                }
#endif

                if let message = appState.parentSyncMessage {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            ParentInviteCodeSheet()
        }
    }

    private var childCards: some View {
        VStack(spacing: 12) {
            if appState.childSummaries.isEmpty {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("연결된 아이가 아직 없어요", systemImage: "person.badge.plus")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.indigo)
                        Text("아이 기기에서 보호자 초대하기를 누른 뒤, 받은 코드를 여기에 붙여넣으면 됩니다.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryButton("아이 연결하기", systemImage: "link") {
                            showingInviteSheet = true
                        }
                    }
                }
            } else {
                ForEach(appState.childSummaries) { child in
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(child.childNickname, systemImage: child.mode.systemImage)
                                    .font(AppTypography.headline)
                                Spacer()
                                Text(child.mode.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color(hex: ThemeProfile.profile(id: nil, mode: child.mode).primaryColorHex))
                            }
                            Text(child.schoolName)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                            parentMealPreview(for: child)
                            HStack(spacing: 8) {
                                summaryPill(title: "오늘 도전", value: "\(child.todayChallengeCount)회", color: AppColors.successGreen)
                                summaryPill(title: "주의 메뉴", value: "\(child.allergyWarningMenus.count)개", color: AppColors.orange)
                                summaryPill(title: "사진", value: "\(child.recentPhotoIds.count)장", color: AppColors.infoBlue)
                            }
                            if !child.allergyWarningMenus.isEmpty {
                                Text("알레르기 주의: \(child.allergyWarningMenus.joined(separator: ", "))")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.warningRed)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("변화 요약")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppColors.textDark)
                                Text(NutritionEstimator.makeParentSummary(records: child.weeklyChallengeRecords))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.graySecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            sharedPhotoStrip(for: child)
                        }
                    }
                }
            }
        }
    }

    private func parentMealPreview(for child: ChildSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("오늘 급식", systemImage: "fork.knife.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.successGreen)
            if let meal = appState.parentChildMeals[child.id] {
                Text(meal.representativeMenu.isEmpty ? "메뉴 이름을 읽지 못했어요." : meal.representativeMenu)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textDark)
                    .fixedSize(horizontal: false, vertical: true)
                Text("NEIS 공공데이터로 조회한 실제 급식 메뉴예요.")
                    .font(.caption2)
                    .foregroundStyle(AppColors.graySecondary)
            } else {
                Text(appState.parentChildMealMessages[child.id] ?? "급식 메뉴를 불러오는 중이에요.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppColors.successGreen.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var praiseCards: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("칭찬 카드")
                    .font(AppTypography.headline)
                ForEach(PraiseCard.templates, id: \.self) { message in
                    Label(message, systemImage: "heart.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("자유 채팅 없이 정해진 칭찬 카드만 사용합니다.")
                    .font(.caption2)
                    .foregroundStyle(AppColors.graySecondary)
            }
        }
    }

    private var recentRecords: [ChallengeRecord] {
        let sharedChildRecords = appState.childSummaries.flatMap(\.weeklyChallengeRecords)
        if !sharedChildRecords.isEmpty {
            return sharedChildRecords
        }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return appState.records.filter { $0.createdAt >= weekAgo }
    }

    private func helperRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "leaf.circle.fill")
                .foregroundStyle(AppColors.primaryGreen)
            Text(text)
                .font(AppTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.graySecondary)
            Text(value)
                .font(.caption.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sharedPhotoStrip(for child: ChildSummary) -> some View {
        let photos = sharedPhotoRecords(for: child)
        return VStack(alignment: .leading, spacing: 8) {
            Text("공유된 급식판 사진")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.textDark)
            if photos.isEmpty {
                Label("아직 공유된 사진이 없어요.", systemImage: "photo")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        SharedMealPhotoThumbnail(url: appState.photoURL(for: photo))
                    }
                }
            }
        }
    }

    private func sharedPhotoRecords(for child: ChildSummary) -> [MealPhotoRecord] {
        child.recentPhotoIds.compactMap { photoId in
            appState.mealPhotos.first {
                $0.id == photoId && $0.isSharedWithParent && ($0.childLinkId == nil || $0.childLinkId == child.id)
            }
        }
    }
}

private struct SharedMealPhotoThumbnail: View {
    var url: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(AppColors.graySecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.08))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardStroke))
        .accessibilityLabel("공유된 급식판 사진")
    }
}

private struct ParentInviteCodeSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var message: String?
    private let service = CloudKitParentLinkService()

    private var normalizedInviteCode: String {
        service.normalizeInviteCode(inviteCode)
    }

    private var canSave: Bool {
        service.isValidInviteCode(inviteCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("아이 연결 코드") {
                    TextField("예: NYAM-8K3P-7M2A-C9YD", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: inviteCode) { newValue in
                            let normalized = service.normalizeInviteCode(newValue)
                            if normalized != newValue {
                                inviteCode = normalized
                            }
                        }
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            inviteCode = service.normalizeInviteCode(pasted)
                        }
                    } label: {
                        Label("클립보드에서 붙여넣기", systemImage: "doc.on.clipboard")
                    }
                    Text("아이 기기에서 받은 보호자 연결 코드를 붙여넣어요. 공유 메시지 전체를 붙여넣어도 코드만 자동 정리됩니다.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                    if let validationMessage = service.inviteCodeValidationMessage(inviteCode),
                       !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.warningRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("공유 범위") {
                    Label("먹은 정도, 한 입 도전, 알레르기 주의, 선택 사진만 연결 대상입니다.", systemImage: "lock.shield")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                    Label("코드가 아이 기기에서 서버 등록 완료된 상태여야 연결됩니다.", systemImage: "checkmark.shield")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                    if let message {
                        Text(message)
                            .font(AppTypography.caption)
                            .foregroundStyle(appState.parentSyncError == nil ? AppColors.graySecondary : AppColors.warningRed)
                    }
                }
            }
            .navigationTitle("아이 연결하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appState.isParentSyncing ? "연결 중" : "연결") {
                        Task {
                            let didConnect = await appState.connectChild(inviteCode: normalizedInviteCode)
                            if didConnect {
                                dismiss()
                            } else {
                                message = appState.parentSyncMessage
                            }
                        }
                    }
                    .disabled(!canSave || appState.isParentSyncing)
                }
            }
        }
    }
}
