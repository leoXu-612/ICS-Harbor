import SwiftUI

struct LibraryView: View {
    let model: AppModel

    var body: some View {
        UnifiedCatalogView(model: model, source: nil)
    }
}
