import SwiftUI

struct CommunityHeaderSectionView: View {
    @Binding var searchText: String
    let onSearchSubmit: () -> Void
    let onSearchClear: () -> Void
    let onComposeTap: () -> Void

    var body: some View {
        SearchBar(
            text: $searchText,
            placeholder: "검색어를 입력해주세요.",
            accessorySystemImage: "square.and.pencil",
            onAccessoryTap: onComposeTap,
            onSubmit: onSearchSubmit,
            showsSearchAction: true,
            onClearTap: onSearchClear
        )
    }
}

#Preview {
    StatefulPreviewWrapper("") { text in
        CommunityHeaderSectionView(
            searchText: text,
            onSearchSubmit: {},
            onSearchClear: {},
            onComposeTap: {}
        )
        .padding()
        .background(PikkoColor.background)
    }
}
