import Foundation

enum RootTab: String, CaseIterable, Hashable, Identifiable {
    case home
    case order
    case community
    case profile

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home:
            return "홈"
        case .order:
            return "주문"
        case .community:
            return "커뮤니티"
        case .profile:
            return "프로필"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .order:
            return "list.clipboard.fill"
        case .community:
            return "person.3.fill"
        case .profile:
            return "person.crop.circle.fill"
        }
    }

    var inactiveSystemImage: String {
        switch self {
        case .home:
            return "house"
        case .order:
            return "list.clipboard"
        case .community:
            return "person.3"
        case .profile:
            return "person.crop.circle"
        }
    }
}
