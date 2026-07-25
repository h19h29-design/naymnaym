import SwiftUI

struct RebuildSchoolSearchView: View {
    @ObservedObject var viewModel: RebuildOnboardingViewModel
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            Text("어느 학교에 다니나요?")
                .font(RebuildDesignTokens.titleFont)
                .accessibilityAddTraits(.isHeader)
            TextField("학교 이름", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(RebuildDesignTokens.bodyFont)
                .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                .accessibilityLabel("학교 이름 검색")
                .task(id: query) {
                    await viewModel.searchSchools(query: query)
                }
            searchContent
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch viewModel.schoolSearchState {
        case .idle:
            Text("학교 이름을 입력해 주세요.")
        case .loading:
            ProgressView("학교를 찾고 있어요.")
        case let .results(schools), let .demoResults(schools):
            ScrollView {
                LazyVStack(spacing: RebuildDesignTokens.spacing[2]) {
                    ForEach(schools) { school in
                        Button {
                            viewModel.selectSchool(school)
                        } label: {
                            Text(school.name)
                                .font(RebuildDesignTokens.bodyFont)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: RebuildDesignTokens.minimumActionSize,
                                    alignment: .leading
                                )
                        }
                        .accessibilityLabel("\(school.name) 선택")
                    }
                }
            }
        case .empty:
            Text("검색 결과가 없어요. 학교 이름을 확인해 주세요.")
        case let .failed(message):
            Text(message)
                .foregroundStyle(RebuildDesignTokens.danger700)
        }
    }
}
