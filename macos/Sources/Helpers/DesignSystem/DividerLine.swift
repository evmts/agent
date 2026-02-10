import SwiftUI

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: DS.Color.border))
            .frame(height: 1)
            .ignoresSafeArea(edges: .horizontal)
    }
}
