import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var nickname = ""
    @State private var showingSchoolSearch = false
    @State private var showingAllergies = false
    @State private var showingPrivacy = false
    @State private var showingSources = false
    @State private var pendingReset: ResetKind?

    var body: some View {
        NavigationStack {
            List {
                Section("프로필") {
                    TextField("별명", text: $nickname)
                        .onSubmit {
                            appState.updateNickname(nickname)
                        }
                    Button {
                        appState.updateNickname(nickname)
                    } label: {
                        Label("별명 저장", systemImage: "square.and.arrow.down")
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
                }

                Section("기록 초기화") {
                    resetButton("도전 기록 초기화", kind: .records)
                    resetButton("프로필 초기화", kind: .profile)
                    resetButton("전체 데이터 초기화", kind: .all)
                }

                Section("안내") {
                    Button {
                        showingPrivacy = true
                    } label: {
                        Label("개인정보 안내 보기", systemImage: "lock.shield")
                    }
                    Button {
                        showingSources = true
                    } label: {
                        Label("데이터 출처 보기", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink {
                        AppInfoView()
                    } label: {
                        Label("앱 정보 보기", systemImage: "info.circle")
                    }
                }
            }
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
                PrivacyGuideView()
            }
            .sheet(isPresented: $showingSources) {
                DataSourcesView()
            }
            .alert(item: $pendingReset) { kind in
                Alert(
                    title: Text(kind.title),
                    message: Text("되돌릴 수 없어요. 계속할까요?"),
                    primaryButton: .destructive(Text("초기화")) {
                        applyReset(kind)
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            }
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
        case .records: return "도전 기록 초기화"
        case .profile: return "프로필 초기화"
        case .all: return "전체 데이터 초기화"
        }
    }
}

private struct PrivacyGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("개인정보 처리 원칙")
                            .font(AppTypography.title)
                        privacy("냠냠레벨업은 회원가입을 요구하지 않습니다.")
                        privacy("이름, 이메일, 전화번호, 위치정보를 수집하지 않습니다.")
                        privacy("별명, 학교 선택, 도전 기록, 알레르기 선택값은 사용자의 기기 내부에 저장됩니다.")
                        privacy("서버로 전송하지 않습니다.")
                        privacy("급식 조회를 위해 선택한 학교 코드와 날짜가 공공데이터 API 조회에 사용될 수 있습니다.")
                        privacy("영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.")
                    }
                }
                .padding(20)
            }
            .navigationTitle("개인정보 안내")
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

private struct DataSourcesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("활용 데이터") {
                    Text("NEIS 학교기본정보 API")
                    Text("NEIS 급식식단정보 API")
                    Text("식품영양성분DB는 영양소 추정 보조 자료로 추후 고도화 참고")
                }
                Section("현재 버전") {
                    Text("API 키가 없거나 실패하면 샘플 데이터로 전체 흐름을 체험합니다.")
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

private struct AppInfoView: View {
    var body: some View {
        List {
            Section("냠냠레벨업") {
                Text("무료 급식 영양교육 iPhone 앱")
                Text("광고 없음")
                Text("인앱결제 없음")
                Text("회원가입 없음")
                Text("서버 저장 없음")
            }
            Section("주의사항") {
                Text("영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.")
                Text("알레르기 정보는 반드시 보호자와 학교 안내를 함께 확인해야 합니다.")
            }
        }
        .navigationTitle("앱 정보")
    }
}

