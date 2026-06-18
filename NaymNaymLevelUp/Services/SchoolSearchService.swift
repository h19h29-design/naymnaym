import Foundation

struct SchoolSearchResult {
    var schools: [School]
    var usedSample: Bool
    var message: String?
}

struct SchoolSearchService {
    var client: NEISClient
    var sampleProvider: SampleDataProvider

    init(client: NEISClient = NEISClient(), sampleProvider: SampleDataProvider = SampleDataProvider()) {
        self.client = client
        self.sampleProvider = sampleProvider
    }

    func searchSchools(keyword: String) async -> SchoolSearchResult {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SchoolSearchResult(schools: [], usedSample: false, message: "학교 이름을 입력하면 검색할 수 있어요.")
        }

        do {
            let data = try await client.request(path: "schoolInfo", query: ["SCHUL_NM": trimmed])
            let decoded = try JSONDecoder().decode(SchoolInfoResponse.self, from: data)
            let rows = decoded.schoolInfo?.flatMap { $0.row ?? [] } ?? []
            let schools = rows.map {
                School(
                    name: $0.SCHUL_NM,
                    officeCode: $0.ATPT_OFCDC_SC_CODE,
                    schoolCode: $0.SD_SCHUL_CODE,
                    region: $0.LCTN_SC_NM ?? $0.ATPT_OFCDC_SC_NM,
                    address: $0.ORG_RDNMA ?? "",
                    schoolType: $0.SCHUL_KND_SC_NM ?? ""
                )
            }

            if !schools.isEmpty {
                return SchoolSearchResult(schools: schools, usedSample: false, message: nil)
            }
        } catch NEISClientError.missingAPIKey {
            return sampleFallback(keyword: trimmed)
        } catch {
            return SchoolSearchResult(
                schools: [],
                usedSample: false,
                message: "학교 검색에 실패했어요. 네트워크 상태를 확인하고 다시 검색해 주세요."
            )
        }

        return SchoolSearchResult(
            schools: [],
            usedSample: false,
            message: "검색 결과가 없어요. 학교 이름을 조금 더 정확히 입력해 주세요."
        )
    }

    private func sampleFallback(keyword: String) -> SchoolSearchResult {
        let filtered = sampleProvider.sampleSchools.filter {
            keyword.isEmpty || $0.name.localizedCaseInsensitiveContains(keyword) || $0.region.localizedCaseInsensitiveContains(keyword)
        }
        let schools = filtered.isEmpty ? sampleProvider.sampleSchools : filtered
        return SchoolSearchResult(
            schools: schools,
            usedSample: true,
            message: "API 키가 없어서 샘플 학교로 체험 중이에요. 실제 급식 조회는 API 키 설정 후 사용할 수 있어요."
        )
    }
}

private struct SchoolInfoResponse: Decodable {
    var schoolInfo: [SchoolInfoSection]?
}

private struct SchoolInfoSection: Decodable {
    var row: [SchoolInfoRow]?
}

private struct SchoolInfoRow: Decodable {
    var ATPT_OFCDC_SC_CODE: String
    var ATPT_OFCDC_SC_NM: String
    var SD_SCHUL_CODE: String
    var SCHUL_NM: String
    var SCHUL_KND_SC_NM: String?
    var LCTN_SC_NM: String?
    var ORG_RDNMA: String?
}
