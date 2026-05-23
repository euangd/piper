// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ihor Shevchuk

import SwiftUI

struct CenteredContent<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            Spacer()
            content
            Spacer()
        }
    }
}
