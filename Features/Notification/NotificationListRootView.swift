import SwiftUI

struct NotificationListRootView: View {
    @StateObject private var presenter: NotificationListPresenter
    @StateObject private var router: NotificationListRouter

    init(presenter: NotificationListPresenter, router: NotificationListRouter) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
    }

    var body: some View {
        NotificationListView(presenter: presenter)
            .navigationTitle(presenter.viewState.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("전체 읽음") {
                            Task { await presenter.send(.markAllAsReadTapped) }
                        }
                        Button("전체 삭제", role: .destructive) {
                            Task { await presenter.send(.deleteAllTapped) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("알림 관리")
                }
            }
            .task {
                await presenter.send(.onAppear)
            }
    }
}

@MainActor
struct NotificationListBuilder {
    private let notificationService: AppNotificationService
    private let appNotificationRouter: AppNotificationRouting

    init(
        notificationService: AppNotificationService,
        appNotificationRouter: AppNotificationRouting
    ) {
        self.notificationService = notificationService
        self.appNotificationRouter = appNotificationRouter
    }

    func build() -> NotificationListRootView {
        let router = NotificationListRouter(appNotificationRouter: appNotificationRouter)
        let interactor = NotificationListInteractor(notificationService: notificationService)
        let presenter = NotificationListPresenter(interactor: interactor, router: router)
        return NotificationListRootView(presenter: presenter, router: router)
    }
}
