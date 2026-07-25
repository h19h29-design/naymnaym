import SwiftUI

struct RebuildRootView: View {
    private enum Role {
        case child
        case guardian
    }

    @State private var selectedRole: Role?

    var body: some View {
        VStack(spacing: RebuildDesignTokens.spacing[4]) {
            roleButton("아이로 시작", role: .child)
            roleButton("보호자로 시작", role: .guardian)
        }
        .padding(RebuildDesignTokens.spacing[4])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RebuildDesignTokens.cream50)
    }

    private func roleButton(_ title: String, role: Role) -> some View {
        Button {
            selectedRole = role
        } label: {
            Text(title)
                .font(RebuildDesignTokens.headlineFont)
                .frame(maxWidth: .infinity, minHeight: RebuildDesignTokens.minimumActionSize)
        }
        .foregroundStyle(RebuildDesignTokens.ink900)
        .background(selectedRole == role ? RebuildDesignTokens.leaf300 : RebuildDesignTokens.cream100)
        .clipShape(RoundedRectangle(cornerRadius: RebuildDesignTokens.radii[0]))
    }
}
