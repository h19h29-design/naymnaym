import SwiftUI

enum SchoolSearchMode {
    case onboarding
    case settings
}

struct SchoolSearchView: View {
    var mode: SchoolSearchMode
    var onSelect: (School) -> Void

    @State private var keyword = ""
    @State private var schools: [School] = SampleDataProvider().sampleSchools
    @State private var message: String? = "학교 이름을 입력하면 검색할 수 있어요."
    @State private var isLoading = false

    private let service = SchoolSearchService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(mode == .onboarding ? "학교를 찾아볼게요" : "학교 다시 선택")
                            .font(AppTypography.title)
                        Text("NEIS 학교기본정보 API를 사용하고, API 키가 없거나 실패하면 샘플 학교로 계속 진행해요.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            TextField("학교 이름", text: $keyword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardStroke))
                                .accessibilityIdentifier("schoolSearchField")
                            Button {
                                Task { await search() }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(.white)
                                    .background(AppColors.primaryGreen)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .accessibilityLabel("검색")
                        }
                    }
                }

                if isLoading {
                    ProgressView("검색 중")
                        .frame(maxWidth: .infinity)
                }

                if let message {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(schools) { school in
                    SchoolResultCard(school: school) {
                        onSelect(school)
                    }
                }
            }
            .padding(20)
        }
        .pageBackground()
    }

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        let result = await service.searchSchools(keyword: keyword)
        schools = result.schools
        message = result.message
    }
}

private struct SchoolResultCard: View {
    var school: School
    var onSelect: () -> Void

    var body: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(school.name)
                            .font(AppTypography.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(school.region) · \(school.schoolType.isEmpty ? "학교" : school.schoolType)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                    Spacer()
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(AppColors.primaryGreen)
                }
                if !school.address.isEmpty {
                    Text(school.address)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton("선택", systemImage: "checkmark", action: onSelect)
            }
        }
    }
}

