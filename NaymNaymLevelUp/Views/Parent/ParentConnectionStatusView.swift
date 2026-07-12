import SwiftUI

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
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.caption.weight(.bold))
                Text(message)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
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
            return Color(hex: "#E58A2E")
        case .invitePending:
            return Color(hex: "#1FA6A7")
        case .connected:
            return Color(hex: "#527A2D")
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
