import SwiftUI
import UIKit

struct ParentSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingInviteSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("부모 연동 구조")
                                .font(AppTypography.headline)
                            Text("1.0은 서버 없이 iCloud 기반 부모-자녀 연결 구조를 사용합니다. 아이 폰에서 만든 초대 코드를 부모 모드에 입력하면 공유가 켜진 먹은 정도, 한 입 도전 기록, 알레르기 주의, 선택 사진만 불러옵니다.")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("보호자 요약")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .task {
                await appState.refreshParentSharedData()
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
                        Text("아이별 식습관 기록과 알레르기 주의, 공유된 사진만 확인해요.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                    Spacer()
                    Button {
                        showingInviteSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(hex: appState.currentTheme.primaryColorHex))
                    }
                    .accessibilityLabel("아이 추가")
                }
                Button {
                    Task { await appState.refreshParentSharedData() }
                } label: {
                    Label(appState.isParentSyncing ? "불러오는 중" : "아이 기록 새로고침", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .disabled(appState.isParentSyncing || appState.parentProfile.childLinks.isEmpty)

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
                        HStack(spacing: 8) {
                            summaryPill(title: "오늘 도전", value: "\(child.todayChallengeCount)회", color: AppColors.primaryGreen)
                            summaryPill(title: "주의 메뉴", value: "\(child.allergyWarningMenus.count)개", color: AppColors.orange)
                            summaryPill(title: "사진", value: "\(child.recentPhotoIds.count)장", color: Color.blue)
                        }
                        if !child.allergyWarningMenus.isEmpty {
                            Text("알레르기 주의: \(child.allergyWarningMenus.joined(separator: ", "))")
                                .font(AppTypography.caption)
                                .foregroundStyle(Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        sharedPhotoStrip(for: child)
                    }
                }
            }
        }
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

    private var normalizedInviteCode: String {
        CloudKitParentLinkService().normalizeInviteCode(inviteCode)
    }

    private var canSave: Bool {
        normalizedInviteCode.hasPrefix("NYAM-") && normalizedInviteCode.count >= 17
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("초대 코드") {
                    TextField("예: NYAM-ABCD-EFGH-IJKL", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Text("아이 폰의 설정 > 보호자 연결 화면에서 만든 초대 코드를 입력해요.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                }

                Section("공유 범위") {
                    Label("먹은 정도, 한 입 도전, 알레르기 주의, 선택 사진만 연결 대상입니다.", systemImage: "lock.shield")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                    if let message {
                        Text(message)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                }
            }
            .navigationTitle("아이 추가")
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
