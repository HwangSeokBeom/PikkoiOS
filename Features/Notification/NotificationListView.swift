import SwiftUI

struct NotificationListView: View {
    @ObservedObject var presenter: NotificationListPresenter

    var body: some View {
        List {
            if let emptyTitle = presenter.viewState.emptyTitle {
                Section {
                    EmptyStateView(
                        title: emptyTitle,
                        message: presenter.viewState.emptyMessage ?? "",
                        systemImage: "bell"
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    HStack {
                        Text("안 읽은 알림")
                            .font(PikkoTypography.bodyStrong)
                        Spacer()
                        Text("\(presenter.viewState.unreadCount)")
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, PikkoSpacing.sm)
                            .frame(minHeight: 24)
                            .background(PikkoColor.accentStrong)
                            .clipShape(Capsule())
                    }
                }

                Section {
                    ForEach(presenter.viewState.items) { item in
                        NotificationCell(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task { await presenter.send(.itemTapped(item.id)) }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("삭제", role: .destructive) {
                                    Task { await presenter.send(.deleteItem(item.id)) }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PikkoColor.background)
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }
}

private struct NotificationCell: View {
    let item: NotificationItemViewState

    var body: some View {
        HStack(alignment: .top, spacing: PikkoSpacing.md) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PikkoColor.accentStrong)
                    .frame(width: 36, height: 36)
                    .background(PikkoColor.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if item.isUnread {
                    Circle()
                        .fill(PikkoColor.danger)
                        .frame(width: 9, height: 9)
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: PikkoSpacing.sm) {
                    Text(item.title)
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.primaryText)
                        .lineLimit(2)
                    Spacer(minLength: PikkoSpacing.sm)
                    Text(item.timeText)
                        .font(PikkoTypography.micro)
                        .foregroundStyle(PikkoColor.tertiaryText)
                        .lineLimit(1)
                }

                Text(item.body)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, PikkoSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.body)")
    }

    private var systemImage: String {
        switch item.type {
        case .orderStatus, .payment, .review:
            return "bag"
        case .chatMessage:
            return "bubble.left.and.bubble.right"
        case .communityComment:
            return "text.bubble"
        case .communityLike:
            return "heart"
        case .communityMention:
            return "at"
        case .system:
            return "bell"
        }
    }
}
