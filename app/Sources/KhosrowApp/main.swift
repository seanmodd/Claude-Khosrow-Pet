#if canImport(AppKit)
import AppKit

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.run()

#else
import Foundation

// Khosrow's UI is AppKit-only. On non-Apple platforms the executable still
// builds (so CI and local Linux checks can compile the whole package) but does
// not run a UI. The KhosrowKit library and its tests are fully cross-platform.
FileHandle.standardError.write(Data(
    "Khosrow is a macOS (AppKit) app; this platform can build but not run it.\n".utf8))
#endif
