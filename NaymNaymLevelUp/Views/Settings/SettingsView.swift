import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var nickname = ""
    @State private var showingSchoolSearch = false
    @State private var showingAllergies = false
    @State private var savingAllergies = false
    @State private var allergySaveFailed = false
    @State private var showingPrivacy = false
    @State private var showingSupport = false
    @State private var showingSources = false
    @State private var showingNicknameEditor = false
    @State private var showingParentConnection = false
    @Environment(\.dailyReviewContainer) private var dailyReviewContainer
    @State private var showingReviewDelete = false
    @State private var reviewDeleteMessage: String?

    private func settingsLabel(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            Text(title).foregroundStyle(RebuildDesignTokens.ink900)
        }
        .padding(.vertical, 3)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CompanionSectionBanner(
                        title: "나의 작은 숲",
                        subtitle: "\(appState.profile?.nickname ?? "친구")의 급식 모험\n학교와 알레르기를 챙겨요.",
                        symbol: "person.crop.circle.fill",
                        accent: RebuildDesignTokens.forest700
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section("프로필") {
                    Picker("사용자 모드", selection: Binding(
                        get: { appState.currentMode },
                        set: { appState.updateUserMode($0) }
                    )) {
                        ForEach(UserMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    Picker("테마", selection: Binding(
                        get: { appState.currentTheme.id },
                        set: { id in
                            if let theme = ThemeProfile.all.first(where: { $0.id == id }) {
                                appState.updateTheme(theme)
                            }
                        }
                    )) {
                        ForEach(ThemeProfile.all) { theme in
                            Text(theme.name)
                                .tag(theme.id)
                        }
                    }
                    Button {
                        nickname = appState.profile?.nickname ?? ""
                        showingNicknameEditor = true
                    } label: {
                        profileRow(
                            title: "별명",
                            value: appState.profile?.nickname ?? "별명 없음",
                            systemImage: "person.crop.circle"
                        )
                    }
                    Button {
                        showingSchoolSearch = true
                    } label: {
                        settingsLabel("학교 다시 선택", symbol: "building.columns.fill", color: Color(red: 0.2, green: 0.55, blue: 0.65))
                    }
                    Button {
                        appState.draftAllergyCodes = Set(appState.profile?.selectedAllergyCodes ?? [])
                        showingAllergies = true
                    } label: {
                        settingsLabel("알레르기 정보 수정", symbol: "shield.lefthalf.filled", color: Color(red: 0.81, green: 0.4, blue: 0.3))
                    }
                }

                if DailyMealReviewAvailability.isEnabled {
                    Section("AI 식단 평가 기록") {
                        Text("평가는 이 기기에 보관돼요. 기록을 삭제해도 오늘 AI 사용 횟수는 초기화되지 않아요.").font(.footnote).foregroundStyle(.secondary)
                        Button(role:.destructive) {showingReviewDelete=true} label: {Label("AI 평가 기록만 삭제",systemImage:"trash")}
                            .disabled(dailyReviewContainer==nil).accessibilityIdentifier("daily_review_delete")
                        if let reviewDeleteMessage {Text(reviewDeleteMessage).font(.footnote).foregroundStyle(.secondary)}
                    }
                }
                Section("연결 상태") {
                    if appState.currentMode == .parent {
                        NavigationLink {
                            ParentSummaryView()
                        } label: {
                            connectionRow
                        }
                    } else {
                        Button {
                            showingParentConnection = true
                        } label: {
                            connectionRow
                        }
                    }
                    NavigationLink {
                        ParentConnectionDiagnosticsView()
                    } label: {
                        settingsLabel("연결 상태 자세히 보기", symbol: "checkmark.shield.fill", color: RebuildDesignTokens.forest500)
                    }
                }

                Section("관리") {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        settingsLabel("데이터 관리", symbol: "internaldrive.fill", color: Color(red: 0.56, green: 0.41, blue: 0.68))
                    }
                }

                Section("안내") {
                    Button {
                        showingPrivacy = true
                    } label: {
                        Label("개인정보 처리방침 보기", systemImage: "lock.shield")
                    }
                    Link(destination: AppExternalLinks.privacyPolicy) {
                        Label("웹 개인정보 처리방침 열기", systemImage: "safari")
                    }
                    Button {
                        showingSupport = true
                    } label: {
                        Label("지원 안내 보기", systemImage: "questionmark.circle")
                    }
                    Link(destination: AppExternalLinks.support) {
                        Label("웹 지원 안내 열기", systemImage: "safari")
                    }
                    Button {
                        showingSources = true
                    } label: {
                        Label("데이터 출처 보기", systemImage: "doc.text.magnifyingglass")
                    }
                    Link(destination: AppExternalLinks.dataSafety) {
                        Label("데이터 안전 안내 열기", systemImage: "shield.lefthalf.filled")
                    }
                    NavigationLink {
                        AppInfoView()
                    } label: {
                        Label("앱 정보 보기", systemImage: "info.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CompanionPageBackdrop())
            .tint(RebuildDesignTokens.forest700)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("AI 평가 기록만 삭제할까요?", isPresented: $showingReviewDelete, titleVisibility: .visible) {
                Button("평가 기록 삭제", role: .destructive) {
                    guard let dailyReviewContainer else { return }
                    do {
                        try DailyMealReviewStore(context: dailyReviewContainer.newBackgroundContext()).deleteAll()
                        reviewDeleteMessage = "AI 평가 기록을 삭제했어요. 급식·성장 기록은 그대로예요."
                    } catch {
                        reviewDeleteMessage = "평가 기록을 삭제하지 못했어요. 기존 기록은 보존했어요."
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 기기의 AI 평가 기록만 삭제하며 되돌릴 수 없어요. 급식 기록과 경험치는 유지해요.")
            }
            .onAppear {
                nickname = appState.profile?.nickname ?? ""
            }
            .sheet(isPresented: $showingSchoolSearch) {
                NavigationStack {
                    SchoolSearchView(mode: .settings) { school in
                        appState.updateSchool(school)
                        showingSchoolSearch = false
                        Task { await appState.loadMeals() }
                    }
                    .navigationTitle("학교 변경")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $showingAllergies) {
                NavigationStack {
                    AllergySelectionView(selectedCodes: $appState.draftAllergyCodes) {
                        guard !savingAllergies else { return }
                        savingAllergies = true
                        Task {
                            defer { savingAllergies = false }
                            do {
                                try await appState.updateAllergies(appState.draftAllergyCodes)
                                showingAllergies = false
                            } catch {
                                allergySaveFailed = true
                            }
                        }
                    }
                    .disabled(savingAllergies)
                    .interactiveDismissDisabled(savingAllergies)
                    .alert("알레르기 정보를 저장하지 못했어요", isPresented: $allergySaveFailed) {
                        Button("확인", role: .cancel) {}
                    } message: {
                        Text("기존 설정은 유지됩니다. 잠시 후 다시 시도해 주세요.")
                    }
                    .navigationTitle("알레르기 수정")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacyPolicyGuideView()
            }
            .sheet(isPresented: $showingSupport) {
                SupportGuideView()
            }
            .sheet(isPresented: $showingSources) {
                DataSourcesView()
            }
            .sheet(isPresented: $showingNicknameEditor) {
                NicknameEditView(nickname: nickname) { newNickname in
                    appState.updateNickname(newNickname)
                    nickname = newNickname
                    showingNicknameEditor = false
                }
            }
            .sheet(isPresented: $showingParentConnection) {
                ParentConnectionGuideView()
            }
        }
    }

    private func profileRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.primaryGreen)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                Text(value)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColors.textDark)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.graySecondary)
        }
    }

    private var connectionRow: some View {
        let overview = appState.connectionOverview
        return HStack(spacing: 12) {
            Image(systemName: overview.isConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                .font(.title3)
                .foregroundStyle(overview.isConnected ? AppColors.successGreen : AppColors.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(overview.title)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColors.textDark)
                    .fixedSize(horizontal: false, vertical: true)
                Text(overview.countText)
                    .font(AppTypography.caption.weight(.bold))
                    .foregroundStyle(overview.isConnected ? AppColors.successGreen : AppColors.graySecondary)
            }
        }
    }
}

struct ParentConnectionGuideView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var shareEating = true
    @State private var shareChallenge = true
    @State private var shareAllergy = true
    @State private var didCopyInviteCode = false
    @State private var inviteShareItem: AppInviteShareItem?

    private let service = CloudKitParentLinkService()

    private var permissions: SharingPermission {
        SharingPermission(
            shareEatingRecords: shareEating,
            shareChallengeRecords: shareChallenge,
            shareAllergyWarnings: shareAllergy,
            sharePhotos: false
        )
    }

    private var inviteCodeText: String {
        appState.childShareLink?.inviteCode ?? "아직 생성되지 않았어요"
    }

    private var hasInviteCode: Bool {
        appState.childShareLink?.inviteCode.isEmpty == false
    }

    private var isInviteReady: Bool {
        appState.childShareLink?.isCloudRegistered == true
    }

    private var isActuallyConnected: Bool {
        appState.childShareLink?.parentConnectedAt != nil
    }

    private var inviteStatusColor: Color {
        if appState.isParentSyncing { return AppColors.infoBlue }
        if isInviteReady { return AppColors.successGreen }
        if appState.childShareLink?.registrationErrorMessage != nil || appState.parentSyncError != nil { return AppColors.warningRed }
        return AppColors.graySecondary
    }

    private var inviteStatusText: String {
        if appState.isParentSyncing {
            return "초대 링크를 준비하는 중이에요."
        }
        if isInviteReady {
            return "초대 링크 준비 완료"
        }
        if hasInviteCode {
            return "아직 부모가 연결할 수 없는 코드예요. 링크 준비를 완료해 주세요."
        }
        return "초대 코드를 만들면 부모가 이 아이를 연결할 수 있어요."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if isActuallyConnected {
                        RoundedCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 34))
                                        .foregroundStyle(AppColors.successGreen)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("보호자와 연결되었습니다")
                                            .font(AppTypography.title)
                                            .foregroundStyle(AppColors.textDark)
                                        Text("연결된 보호자 1명")
                                            .font(AppTypography.body.weight(.bold))
                                            .foregroundStyle(AppColors.successGreen)
                                    }
                                }
                                Text("급식 결과와 도전 기록을 보호자와 함께 확인할 수 있어요.")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.graySecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                SecondaryButton("연결 상태 새로고침", systemImage: "arrow.clockwise") {
                                    Task { await appState.refreshChildConnectionStatus() }
                                }
                            }
                        }
                        sharingPermissionsCard
                        PrimaryButton(
                            "공유 설정 저장",
                            systemImage: "checkmark.shield",
                            isDisabled: appState.isParentSyncing
                        ) {
                            Task {
                                await appState.updateParentSharingPermissions(permissions)
                                loadConfirmedPermissions()
                            }
                        }
                        if let error = appState.parentSyncError {
                            Text(error)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.warningRed)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("보호자 초대 코드", systemImage: "qrcode")
                                .font(AppTypography.headline)
                            Text(inviteCodeText)
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .minimumScaleFactor(AppReadabilityPolicy.minimumTextScale)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(AppColors.lavender.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            if isInviteReady {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("초대 링크 준비 완료")
                                            .font(AppTypography.headline)
                                        Text("부모에게 링크를 보내면 앱에서 바로 연결할 수 있어요.")
                                            .font(AppTypography.caption)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                }
                                .foregroundStyle(AppColors.successGreen)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.successGreen.opacity(0.11))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                Label(inviteStatusText, systemImage: "exclamationmark.triangle.fill")
                                    .font(AppTypography.caption.weight(.semibold))
                                    .foregroundStyle(inviteStatusColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let link = appState.childShareLink, isInviteReady {
                                HStack(spacing: 10) {
                                    SecondaryButton(didCopyInviteCode ? "링크 복사 완료" : "링크 복사", systemImage: didCopyInviteCode ? "checkmark" : "link") {
                                        UIPasteboard.general.string = AppInviteLink.parentConnectionURLString(inviteCode: link.inviteCode)
                                        didCopyInviteCode = true
                                    }
                                    Button {
                                        inviteShareItem = AppInviteShareItem(message: link.parentInviteShareMessage)
                                    } label: {
                                        Label("링크 공유", systemImage: "square.and.arrow.up")
                                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: 46)
                                            .foregroundStyle(AppColors.indigo)
                                            .background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(AppColors.indigo.opacity(0.22), lineWidth: 1)
                                            )
                                    }
                                    .accessibilityLabel("초대 링크 공유하기")
                                }
                            }
                            Text("준비 완료 전에는 부모 기기에서 이 코드를 찾을 수 없어요. 준비가 끝난 뒤 링크를 공유하면 부모 기기에서 앱이 열리고 자동 연결됩니다.")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            PrimaryButton(
                                appState.childShareLink == nil ? "초대 링크 만들기" : "초대 링크 준비하기",
                                systemImage: "link.badge.plus",
                                isDisabled: appState.isParentSyncing
                            ) {
                                Task { await appState.activateParentSharing(permissions: permissions) }
                            }
                            if hasInviteCode {
                                SecondaryButton("준비 상태 확인", systemImage: "checkmark.shield") {
                                    Task { await appState.verifyParentInviteRegistration() }
                                }
                            }
                            if let message = appState.parentSyncMessage {
                                Text(message)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(appState.parentSyncError == nil ? AppColors.graySecondary : AppColors.warningRed)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    sharingPermissionsCard

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("부모에게 이렇게 안내돼요")
                                .font(AppTypography.headline)
                            Label("부모가 초대 링크를 누르면 앱이 열려요.", systemImage: "1.circle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textDark)
                            Label("링크가 열리지 않으면 메시지의 코드를 붙여넣어요.", systemImage: "2.circle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textDark)
                            Label("먹은 정도, 한 입 도전, 알레르기 주의만 보여요.", systemImage: "lock.shield.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textDark)
                            Label("초대 메시지에는 연결에 필요한 코드만 포함돼요.", systemImage: "lock.shield.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textDark)
                            Label("부모 알림은 부모 기기에서 허용한 경우에만 전송돼요.", systemImage: "bell.badge.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textDark)
                        }
                    }
                    }

                    NavigationLink {
                        ParentConnectionDiagnosticsView()
                    } label: {
                        RoundedCard {
                            HStack(spacing: 12) {
                                Image(systemName: "stethoscope")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(AppColors.indigo)
                                    .frame(width: 42, height: 42)
                                    .background(AppColors.lavender)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("보호자 연동 상태 확인")
                                        .font(AppTypography.headline)
                                        .foregroundStyle(AppColors.textDark)
                                    Text("초대 코드, 권한, 공유 기록 수, 최근 오류를 확인해요.")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.graySecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppColors.graySecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("보호자 연결")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $inviteShareItem) { item in
                ActivityView(activityItems: [item.message])
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .pageBackground()
            .onAppear {
                loadConfirmedPermissions()
            }
        }
    }

    private func loadConfirmedPermissions() {
        guard let permissions = appState.childShareLink?.permissions else { return }
        shareEating = permissions.shareEatingRecords
        shareChallenge = permissions.shareChallengeRecords
        shareAllergy = permissions.shareAllergyWarnings
    }

    private var sharingPermissionsCard: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("공유할 항목")
                    .font(AppTypography.headline)
                Toggle("먹은 정도 기록", isOn: $shareEating)
                Toggle("한 입 도전 기록", isOn: $shareChallenge)
                Toggle("알레르기 주의", isOn: $shareAllergy)
                Text("사진은 부모에게 공유하지 않고 이 기기 안에만 저장됩니다. 아이가 급식 결과를 올리면 부모에게 알림을 보낼 수 있어요.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ParentConnectionDiagnosticsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section("아이 기기 공유 상태") {
                diagnosticsRow(
                    title: "아이 공유 준비",
                    value: diagnostics.hasChildShareLink ? "있음" : "없음",
                    systemImage: diagnostics.hasChildShareLink ? "checkmark.circle.fill" : "xmark.circle"
                )
                diagnosticsRow(title: "초대 코드", value: diagnostics.inviteCode, systemImage: "number")
                diagnosticsRow(title: "공유 권한", value: diagnostics.permissionSummary, systemImage: "slider.horizontal.3")
                diagnosticsRow(title: "공유된 기록", value: "\(diagnostics.sharedRecordCount)개", systemImage: "list.bullet.clipboard")
            }

            Section("부모 모드 연결 상태") {
                diagnosticsRow(title: "연결된 아이", value: "\(diagnostics.parentChildLinkCount)명", systemImage: "person.2.fill")
            }

            Section("최근 동기화") {
                diagnosticsRow(title: "마지막 메시지", value: diagnostics.lastSyncMessage, systemImage: "message")
                diagnosticsRow(title: "마지막 오류", value: diagnostics.lastSyncError, systemImage: diagnostics.lastSyncError == "최근 오류 없음" ? "checkmark.shield" : "exclamationmark.triangle.fill")
            }
        }
        .navigationTitle("연동 상태")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var diagnostics: ParentConnectionDiagnostics {
        appState.parentConnectionDiagnostics
    }

    private func diagnosticsRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(value == "최근 오류 없음" || value == "있음" ? AppColors.successGreen : AppColors.indigo)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                Text(value)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColors.textDark)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NicknameEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String

    var onSave: (String) -> Void

    init(nickname: String, onSave: @escaping (String) -> Void) {
        _nickname = State(initialValue: nickname)
        self.onSave = onSave
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("별명") {
                    TextField("예: 냠냠이", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("별명 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        onSave(trimmedNickname)
                        dismiss()
                    }
                    .disabled(trimmedNickname.isEmpty)
                }
            }
        }
    }
}

private struct DataManagementView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pendingReset: ResetKind?

    var body: some View {
        List {
            Section("삭제 전 확인") {
                Text("삭제한 데이터는 되돌릴 수 없어요. 필요할 때만 아래 항목으로 들어와 삭제해 주세요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("데이터 삭제") {
                resetButton("도전 기록 삭제", kind: .records)
                resetButton("프로필 삭제", kind: .profile)
                resetButton("전체 데이터 삭제", kind: .all)
            }
        }
        .navigationTitle("데이터 관리")
        .alert(item: $pendingReset) { kind in
            Alert(
                title: Text(kind.title),
                message: Text("되돌릴 수 없어요. 계속할까요?"),
                primaryButton: .destructive(Text("삭제")) {
                    applyReset(kind)
                },
                secondaryButton: .cancel(Text("취소"))
            )
        }
    }

    private func resetButton(_ title: String, kind: ResetKind) -> some View {
        Button(role: .destructive) {
            pendingReset = kind
        } label: {
            Label(title, systemImage: "trash")
        }
    }

    private func applyReset(_ kind: ResetKind) {
        switch kind {
        case .records:
            appState.resetChallengeRecords()
        case .profile:
            appState.resetProfile()
        case .all:
            appState.resetAllData()
        }
    }
}

private enum ResetKind: String, Identifiable {
    case records
    case profile
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .records: return "도전 기록 삭제"
        case .profile: return "프로필 삭제"
        case .all: return "전체 데이터 삭제"
        }
    }
}

private struct PrivacyPolicyGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("개인정보 처리방침")
                                .font(AppTypography.title)
                            Text("시행일: 2026-06-20")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                            privacy("급식레벨업은 회원가입을 요구하지 않습니다.")
                            privacy("이름, 이메일, 전화번호, 위치정보, 연락처, 광고 식별자를 수집하지 않습니다.")
                            privacy("광고와 인앱결제가 없습니다.")
                            privacy("별명, 학교 선택, 먹은 정도 기록, 알레르기 선택값은 기본적으로 사용자의 기기 내부에 저장됩니다.")
                            privacy("급식판 사진은 기본적으로 기기 내부에만 저장되며 보호자에게 공유하지 않습니다.")
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("공공데이터와 부모 공유")
                                .font(AppTypography.headline)
                            privacy("급식 조회를 위해 선택한 학교 코드와 날짜가 NEIS 공공데이터 API 요청에 사용될 수 있습니다.")
                            privacy("부모 연동 시 선택한 기록만 공유 대상이며 공개 피드나 친구 공유는 없습니다.")
                            privacy("부모 연결은 초대 코드와 사용자가 선택한 공유 기록만 동기화합니다.")
                            privacy("부모가 알림을 허용하면 아이가 급식 결과를 올렸을 때 푸시 알림을 받을 수 있습니다.")
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("안전과 삭제")
                                .font(AppTypography.headline)
                            privacy("영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.")
                            privacy("알레르기 정보는 안전을 보장하지 않으며 학교 안내와 보호자 판단이 우선입니다.")
                            privacy("설정 > 데이터 관리에서 기록, 프로필, 전체 데이터를 삭제할 수 있습니다.")
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("공개 처리방침")
                                .font(AppTypography.headline)
                            Text("App Store 제출용 공개 페이지에서도 같은 내용을 확인할 수 있습니다.")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Link(destination: AppExternalLinks.privacyPolicy) {
                                Label("웹 개인정보 처리방침 열기", systemImage: "safari")
                                    .font(AppTypography.body.weight(.semibold))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("개인정보 처리방침")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .pageBackground()
        }
    }

    private func privacy(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.primaryGreen)
            Text(text)
                .font(AppTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SupportGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("급식 정보가 없을 때") {
                    Text("방학, 재량휴업일, 급식 미운영일이거나 NEIS에 아직 식단이 등록되지 않았을 수 있습니다.")
                    Text("실제 학교 선택 상태에서는 샘플 급식으로 대체하지 않습니다.")
                }
                Section("체험 모드") {
                    Text("샘플 급식은 사용자가 체험 모드를 직접 선택한 경우에만 표시됩니다.")
                }
                Section("알레르기") {
                    Text("앱은 알레르기 안전을 보장하지 않습니다.")
                    Text("선택한 알레르기와 관련된 메뉴는 한 입 도전보다 보호자와 학교 안내 확인이 먼저입니다.")
                }
                Section("사진") {
                    Text("급식판 사진은 기본적으로 기기 내부에 저장됩니다.")
                    Text("사진은 부모 모드로 공유하지 않습니다.")
                }
                Section("데이터 삭제") {
                    Text("설정 > 데이터 관리에서 기록, 프로필, 전체 데이터를 삭제할 수 있습니다.")
                    Text("삭제한 데이터는 되돌릴 수 없습니다.")
                }
                Section("공개 지원 페이지") {
                    Link(destination: AppExternalLinks.support) {
                        Label("웹 지원 안내 열기", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("지원 안내")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

private struct DataSourcesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("활용 데이터") {
                    Text("NEIS 학교기본정보 API")
                    Text("NEIS 급식식단정보 API")
                    Text("식품영양성분DB는 영양소 설명을 보완하는 참고 자료로 활용합니다.")
                }
                Section("현재 버전") {
                    Text("샘플 데이터는 사용자가 명시적으로 체험 모드를 선택한 경우에만 표시됩니다.")
                    Text("실제 학교 선택 상태에서 연동 설정, 네트워크 오류, 급식 없음은 각각 정확한 안내 화면으로 표시됩니다.")
                }
                Section("데이터 안전") {
                    Link(destination: AppExternalLinks.dataSafety) {
                        Label("웹 데이터 안전 안내 열기", systemImage: "shield.lefthalf.filled")
                    }
                }
            }
            .navigationTitle("데이터 출처")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

private enum AppExternalLinks {
    static let privacyPolicy = URL(string: "https://nyam.h19h19.com/privacy.html")!
    static let support = URL(string: "https://nyam.h19h19.com/support.html")!
    static let dataSafety = URL(string: "https://nyam.h19h19.com/data-safety.html")!
}

private struct AppInfoView: View {
    var body: some View {
        List {
            Section("급식레벨업") {
                Text("무료 급식 영양교육 iPhone 앱")
                Text("광고 없음")
                Text("인앱결제 없음")
                Text("회원가입 없음")
                Text("기본 로컬 저장")
                Text("부모 연결 후 선택한 기록만 공유")
            }
            Section("주의사항") {
                Text("영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.")
                Text("알레르기 정보는 반드시 보호자와 학교 안내를 함께 확인해야 합니다.")
            }
        }
        .navigationTitle("앱 정보")
    }
}
