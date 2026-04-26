import SwiftUI

struct CommunityHeaderSectionView: View {
    @Binding var searchText: String
    let onSearchSubmit: () -> Void
    let onComposeTap: () -> Void

    var body: some View {
        SearchBar(
            text: $searchText,
            placeholder: "검색어를 입력해주세요.",
            accessorySystemImage: "square.and.pencil",
            onAccessoryTap: onComposeTap,
            onSubmit: onSearchSubmit
        )
    }
}

#Preview {
    StatefulPreviewWrapper("") { text in
        CommunityHeaderSectionView(
            searchText: text,
            onSearchSubmit: {},
            onComposeTap: {}
        )
        .padding()
        .background(PikkoColor.background)
    }
}
