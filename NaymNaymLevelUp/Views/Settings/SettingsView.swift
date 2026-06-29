import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var nickname = ""
    @State private var showingSchoolSearch = false
    @State private var showingAllergies = false
    @State private var showingPrivacy = false
    @State private var showingSupport = false
    @State private var showingSources = false
    @State private var showingNicknameEditor = false
    @State private var showingParentConnection = false

    var body: some View {
        NavigationStack {
            List {
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
                        Label("학교 다시 선택", systemImage: "building.columns")
                    }
                    Button {
                        appState.draftAllergyCodes = Set(appState.profile?.selectedAllergyCodes ?? [])
                        showingAllergies = true
                    } label: {
                        Label("알레르기 정보 수정", systemImage: "checklist")
                    }
                    Button {
                        showingParentConnection = true
                    } label: {
                        Label("보호자 연결", systemImage: "person.2.fill")
                    }
                    NavigationLink {
                        ParentConnectionDiagnosticsView()
                    } label: {
                        Label("보호자 연동 상태 확인", systemImage: "stethoscope")
                    }
                }

                Section("관리") {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("데이터 관리", systemImage: "internaldrive")
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
            .background(ThemeBackdrop(theme: appState.currentTheme).ignoresSafeArea())
            .navigationTitle("설정")
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
                        appState.updateAllergies(appState.draftAllergyCodes)
                        showingAllergies = false
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
}

private struct ParentConnectionGuideView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var shareEating = true
    @State private var shareChallenge = true
    @State private var shareAllergy = true
    @State private var sharePhotos = false
    @State private var didCopyInviteCode = false

    private let service = CloudKitParentLinkService()

    private var permissions: SharingPermission {
        SharingPermission(
            shareEatingRecords: shareEating,
            shareChallengeRecords: shareChallenge,
            shareAllergyWarnings: shareAllergy,
            sharePhotos: sharePhotos
        )
    }

    private var inviteCodeText: String {
        appState.childShareLink?.inviteCode ?? "아직 생성되지 않았어요"
    }

    private var hasInviteCode: Bool {
        appState.childShareLink?.inviteCode.isEmpty == false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("보호자 초대 코드", systemImage: "qrcode")
                                .font(AppTypography.headline)
                            Text(inviteCodeText)
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .minimumScaleFactor(0.55)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(AppColors.lavender.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            if hasInviteCode {
                                HStack(spacing: 10) {
                                    SecondaryButton(didCopyInviteCode ? "복사 완료" : "복사", systemImage: didCopyInviteCode ? "checkmark" : "doc.on.doc") {
                                        UIPasteboard.general.string = inviteCodeText
                                        didCopyInviteCode = true
                                    }
                                    ShareLink(item: inviteCodeText) {
                                        Label("공유", systemImage: "square.and.arrow.up")
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
                                }
                            }
                            Text("공유 설정을 저장하면 이 코드가 iCloud에 등록됩니다. 부모 모드에서 아이 추가를 누르고 같은 코드를 입력해요.")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            PrimaryButton(
                                appState.childShareLink == nil ? "초대 코드 생성" : "공유 설정 저장",
                                systemImage: "icloud.and.arrow.up",
                                isDisabled: appState.isParentSyncing
                            ) {
                                Task { await appState.activateParentSharing(permissions: permissions) }
                            }
                            if let message = appState.parentSyncMessage {
                                Text(message)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.graySecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("공유할 항목")
                                .font(AppTypography.headline)
                            Toggle("먹은 정도 기록", isOn: $shareEating)
                            Toggle("한 입 도전 기록", isOn: $shareChallenge)
                            Toggle("알레르기 주의", isOn: $shareAllergy)
                            Toggle("선택한 급식판 사진", isOn: $sharePhotos)
                            Text("사진은 기본적으로 내 기기에만 저장되고, 공유를 켠 사진만 부모에게 보여주는 구조입니다.")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CloudKit 준비 항목")
                                .font(AppTypography.headline)
                            ForEach(service.setupChecklist, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle.fill")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textDark)
                            }
                            Text("Record types: \(service.recordTypes.joined(separator: ", "))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .pageBackground()
            .onAppear {
                if let permissions = appState.childShareLink?.permissions {
                    shareEating = permissions.shareEatingRecords
                    shareChallenge = permissions.shareChallengeRecords
                    shareAllergy = permissions.shareAllergyWarnings
                    sharePhotos = permissions.sharePhotos
                }
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
                    title: "childShareLink",
                    value: diagnostics.hasChildShareLink ? "있음" : "없음",
                    systemImage: diagnostics.hasChildShareLink ? "checkmark.circle.fill" : "xmark.circle"
                )
                diagnosticsRow(title: "inviteCode", value: diagnostics.inviteCode, systemImage: "number")
                diagnosticsRow(title: "공유 권한", value: diagnostics.permissionSummary, systemImage: "slider.horizontal.3")
                diagnosticsRow(title: "공유된 기록", value: "\(diagnostics.sharedRecordCount)개", systemImage: "list.bullet.clipboard")
                diagnosticsRow(title: "공유된 사진", value: "\(diagnostics.sharedPhotoCount)장", systemImage: "photo")
            }

            Section("부모 모드 연결 상태") {
                diagnosticsRow(title: "연결된 아이", value: "\(diagnostics.parentChildLinkCount)명", systemImage: "person.2.fill")
                diagnosticsRow(title: "iCloud 설정", value: diagnostics.iCloudCapabilityMessage, systemImage: "icloud")
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
                            privacy("냠냠레벨업은 회원가입을 요구하지 않습니다.")
                            privacy("이름, 이메일, 전화번호, 위치정보, 연락처, 광고 식별자를 수집하지 않습니다.")
                            privacy("광고와 인앱결제가 없습니다.")
                            privacy("별명, 학교 선택, 먹은 정도 기록, 알레르기 선택값은 기본적으로 사용자의 기기 내부에 저장됩니다.")
                            privacy("급식판 사진은 기본적으로 기기 내부에 저장되고, 부모 공유를 켠 사진만 보호자에게 공유됩니다.")
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("공공데이터와 부모 공유")
                                .font(AppTypography.headline)
                            privacy("급식 조회를 위해 선택한 학교 코드와 날짜가 NEIS 공공데이터 API 요청에 사용될 수 있습니다.")
                            privacy("부모 연동 시 선택한 기록과 선택한 사진만 공유 대상이며 공개 피드나 친구 공유는 없습니다.")
                            privacy("CloudKit 부모 연결은 자체 서버 없이 iCloud 기반으로 구성합니다.")
                            privacy("사진은 급식판만 찍는 용도이며 친구 얼굴, 이름표, 반/번호 촬영을 권장하지 않습니다.")
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
                    Text("부모 공유를 켠 사진만 부모 모드 공유 대상입니다.")
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
                    Text("실제 학교 선택 상태에서 API 키 없음, 네트워크 오류, 급식 없음은 정확한 안내 화면으로 표시됩니다.")
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
    static let privacyPolicy = URL(string: "https://h19h29-design.github.io/naymnaym/privacy.html")!
    static let support = URL(string: "https://h19h29-design.github.io/naymnaym/support.html")!
    static let dataSafety = URL(string: "https://h19h29-design.github.io/naymnaym/data-safety.html")!
}

private struct AppInfoView: View {
    var body: some View {
        List {
            Section("냠냠레벨업") {
                Text("무료 급식 영양교육 iPhone 앱")
                Text("광고 없음")
                Text("인앱결제 없음")
                Text("회원가입 없음")
                Text("기본 로컬 저장")
                Text("부모 공유 시 iCloud 사용")
            }
            Section("주의사항") {
                Text("영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.")
                Text("알레르기 정보는 반드시 보호자와 학교 안내를 함께 확인해야 합니다.")
            }
        }
        .navigationTitle("앱 정보")
    }
}
