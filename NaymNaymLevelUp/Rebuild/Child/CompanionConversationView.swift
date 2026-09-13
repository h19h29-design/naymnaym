import SwiftUI

// Offline, choice-based conversation. No network client, persistence or XP writes.
enum CompanionTopic: String, CaseIterable, Identifiable {
    case hello, meal, difficult, allergy, growth, tired
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hello: return "안녕! 같이 놀자"
        case .meal: return "오늘 한 입 먹어 봤어"
        case .difficult: return "먹기 어려운 반찬이 있어"
        case .allergy: return "알레르기가 걱정돼"
        case .growth: return "우리 얼마나 자랐지?"
        case .tired: return "오늘은 조금 지쳤어"
        }
    }
    var symbol: String {
        switch self {
        case .hello: return "hand.wave"
        case .meal: return "fork.knife"
        case .difficult: return "leaf"
        case .allergy: return "shield.lefthalf.filled"
        case .growth: return "sparkles"
        case .tired: return "heart"
        }
    }
    var reaction: CompanionClip {
        switch self {
        case .hello: return .greeting
        case .meal, .growth: return .encouraging
        case .difficult, .allergy, .tired: return .listening
        }
    }
    func reply(turn: Int, level: Int) -> String {
        let alternate = turn % 2 != 0
        switch self {
        case .hello: return alternate ? "반가워! 오늘도 네 이야기를 들을 준비가 됐어." : "안녕! 잠깐 쉬면서 오늘 이야기를 나눠 보자."
        case .meal: return alternate ? "새로운 맛을 만나 봤구나! 어떤 느낌이었는지 천천히 떠올려 봐. 기록은 오늘 탭에서 할 수 있어." : "네 속도로 해 본 게 멋져! 많이 먹는 것보다 네 느낌을 알아가는 게 중요해."
        case .difficult: return alternate ? "맛이나 냄새, 식감이 낯설 수 있어. 지금 꼭 먹어야 하는 건 아니야. 어른에게 어떤 점이 어려운지 말해 봐." : "그럴 수 있어. 싫은 마음도 말해 줘서 고마워. 억지로 먹지 말고 믿을 수 있는 어른과 이야기해 보자."
        case .allergy: return "알레르기가 걱정되는 음식은 먹어 보지 말고, 보호자나 선생님에게 먼저 확인해 줘. 나는 음식이 안전한지 판단할 수 없어. 몸이 불편하면 바로 어른에게 알려 줘."
        case .growth: return "지금 우리는 레벨 \(max(1, level))이야! 성장 탭에서 함께 쌓은 기록을 볼 수 있어. 여기서 이야기하는 것만으로 경험치가 바뀌지는 않아."
        case .tired: return alternate ? "쉬어 가도 괜찮아. 오늘은 편안하게 숨을 고르고 네 몸의 이야기를 들어 보자." : "지친 날도 있지. 잘해야 한다는 부담은 잠깐 내려놓자. 힘들면 가까운 어른에게 이야기해 줘."
        }
    }
}

struct CompanionDialogue: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

struct CompanionConversation {
    private(set) var messages: [CompanionDialogue] = []
    private(set) var turn = 0
    mutating func respond(to topic: CompanionTopic, level: Int) {
        messages.append(.init(isUser: true, text: topic.title))
        messages.append(.init(isUser: false, text: topic.reply(turn: turn, level: level)))
        messages = Array(messages.suffix(12))
        turn += 1
    }
}

// Extends the existing forest world: a character stage, a short transcript and
// native topic buttons. Prepared replies are explicitly labeled, never called AI.
struct CompanionConversationView: View {
    let level: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var conversation = CompanionConversation()
    @State private var selectedTopic: CompanionTopic?
    @State private var clip = CompanionClip.idleBreathing
    @State private var revision = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if conversation.messages.isEmpty {
                            Text("반가워! 오늘은 어떤 하루였어? 네 속도로 천천히 이야기해 줘.")
                                .font(.body).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                        }
                        Text("아래 문장을 골라 주세요. 대화는 저장·전송하지 않아요.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(conversation.messages) { message in
                            HStack {
                                if message.isUser { Spacer(minLength: 28) }
                                Text(message.text).font(.body)
                                    .padding(14)
                                    .foregroundStyle(message.isUser ? Color.white : Color.primary)
                                    .background(message.isUser ? RebuildDesignTokens.forest700 : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                                    .accessibilityLabel("\(message.isUser ? "내 말" : "캐릭터"): \(message.text)")
                                if !message.isUser { Spacer(minLength: 28) }
                            }
                        }
                        VStack(spacing: 8) {
                            if selectedTopic != nil {
                                Label("대화 준비 중", systemImage: "ellipsis.bubble")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                                ForEach(CompanionTopic.allCases) { topic in
                                    Button { selectedTopic = topic } label: {
                                        Label(topic.title, systemImage: topic.symbol)
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                            .padding(.horizontal, 12).padding(.vertical, 4)
                                    }
                                    .buttonStyle(.bordered).tint(conversationTint)
                                    .disabled(selectedTopic != nil)
                                    .accessibilityIdentifier("companion_topic_\(topic.rawValue)")
                                }
                            }
                        }.id("choices")
                    }.padding(16)
                }
                .background(Color(.systemGroupedBackground))
                .safeAreaInset(edge: .top, spacing: 0) { characterHeader }
                .onChange(of: conversation.turn) { _ in
                    if reduceMotion { proxy.scrollTo("choices", anchor: .bottom) }
                    else { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("choices", anchor: .bottom) } }
                }
            }
            .navigationTitle("냠냠이와 이야기").navigationBarTitleDisplayMode(.inline)
            .tint(conversationTint)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() }.foregroundStyle(conversationTint) } }
            .task(id: selectedTopic) {
                guard let topic = selectedTopic else { return }
                clip = .thinking; revision += 1
                do { try await Task.sleep(nanoseconds: 1_400_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                conversation.respond(to: topic, level: level)
                clip = topic.reaction; revision += 1
                selectedTopic = nil
            }
            .task(id: revision) {
                guard selectedTopic == nil, clip != .idleBreathing else { return }
                do { try await Task.sleep(nanoseconds: 4_800_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                clip = .idleBreathing; revision += 1
            }
        }
    }

    private var conversationTint: Color {
        colorScheme == .dark ? Color(red: 0.61, green: 0.89, blue: 0.71) : RebuildDesignTokens.forest700
    }

    private var characterHeader: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                Image("CompanionForestStage").resizable().scaledToFill()
                    .frame(height: typeSize.isAccessibilitySize ? 120 : 180).clipped().accessibilityHidden(true)
                if CompanionPlayback.supports(level: level) {
                    CompanionAnimationView(clip: clip, reduceMotion: reduceMotion,
                        playbackRevision: revision, isActive: scenePhase == .active)
                        .frame(width: typeSize.isAccessibilitySize ? 120 : 180, height: typeSize.isAccessibilitySize ? 120 : 180)
                } else {
                    GrowthCharacterView(level: level, size: typeSize.isAccessibilitySize ? 120 : 180)
                }
            }.frame(height: typeSize.isAccessibilitySize ? 120 : 180)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            Text("선택형 대화 · 저장·전송하지 않아요").font(.footnote).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.bottom, 8).background(Color(.systemGroupedBackground))
    }
}
