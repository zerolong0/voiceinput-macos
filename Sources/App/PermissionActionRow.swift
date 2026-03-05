import SwiftUI

struct PermissionActionRow: View {
    let icon: String
    let title: String
    let desc: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct StyleButton: View {
    let id: String
    let name: String
    let icon: String
    let desc: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.medium))
                    Text(desc).font(.caption).foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .font(.system(size: 16))
            }
            .padding(12)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
