import SwiftUI

// Use the established property wrapper; the macOS 27 SDK also exports a State macro
// whose compiler plugin is absent from this machine's Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
