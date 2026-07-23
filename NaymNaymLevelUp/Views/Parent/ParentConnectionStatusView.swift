import SwiftUI

enum ParentConnectionPresentation {
    static func showsInviteAction(link: ChildLink?, state: ParentConnectionState) -> Bool {
        guard !showsConnectedStatusOnly(link: link) else { return false }
        return state == .notLinked || state == .invitePending
    }

    static func showsConnectedStatusOnly(link: ChildLink?) -> Bool {
        link?.parentConnectedAt != nil
    }

    static func showsWaitingCopy(link: ChildLink?, state: ParentConnectionState) -> Bool {
        !showsConnectedStatusOnly(link: link) && state == .invitePending
    }
}

struct ParentConnectionStatusView: View {
    let state: ParentConnectionState
    let connectedName: String?
    let onTap: () -> Void

    init(
        state: ParentConnectionState,
        connectedName: String? = nil,
        onTap: @escaping () -> Void
    ) {
        self.state = state
        self.connectedName = connectedName
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: state == .connected ? 12 : 8) {
                Image(systemName: iconName)
                    .font(state == .connected ? .title2.weight(.bold) : .caption.weight(.bold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(message)
                        .font(state == .connected ? AppTypography.headline : AppTypography.supporting.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if state == .connected {
                        Text(connectedName == nil ? "연결된 보호자 1명" : "연결 완료")
                            .font(AppTypography.caption.weight(.bold))
                            .foregroundStyle(tint.opacity(0.86))
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: state == .connected ? "arrow.clockwise" : "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, state == .connected ? 16 : 12)
            .padding(.vertical, state == .connected ? 15 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message)
        .accessibilityHint(actionHint)
    }

    private var message: String {
        guard let connectedName else { return state.childMessage }
        return state.parentMessage(childName: connectedName)
    }

    private var iconName: String {
        switch state {
        case .notLinked:
            return "person.crop.circle.badge.plus"
        case .invitePending:
            return "hourglass"
        case .connected:
            return "checkmark.circle.fill"
        case .syncError:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .notLinked:
            return AppColors.orange
        case .invitePending:
            return AppColors.infoBlue
        case .connected:
            return AppColors.primaryGreen
        case .syncError:
            return AppColors.warningRed
        }
    }

    private var actionHint: String {
        if connectedName != nil {
            return "아이 기록을 새로고침합니다"
        }
        switch state {
        case .notLinked, .invitePending:
            return "보호자 초대 화면을 엽니다"
        case .connected, .syncError:
            return "연결 상태를 새로고침합니다"
        }
    }
}
