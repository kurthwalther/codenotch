import XCTest
import SwiftUI
@testable import Codenotch

/// The notice cards report where they landed so the cursor poll can say which
/// one it is on. That only works if SwiftUI's frames and the pointer end up in
/// the same coordinate system, which is the assumption pinned down here.
@MainActor
final class NoticeHoverTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        var frames: [String: CGRect] = [:]
    }

    private struct Probe: View {
        let box: Box
        var body: some View {
            VStack(spacing: 0) {
                Color.red.frame(width: 100, height: 40)
                    .background(measure("top"))
                Color.blue.frame(width: 100, height: 40)
                    .background(measure("bottom"))
            }
            .onPreferenceChange(NoticeCardFrames.self) { frames in
                MainActor.assumeIsolated { box.frames = frames }
            }
        }

        private func measure(_ id: String) -> some View {
            GeometryReader { proxy in
                Color.clear.preference(key: NoticeCardFrames.self,
                                       value: [id: proxy.frame(in: .global)])
            }
        }
    }

    /// SwiftUI hands back frames from the hosting view's top-left, y growing
    /// down — the first card above the second.
    func testCardFramesAreMeasuredFromTheTopDown() {
        let box = Box()
        let hosting = NSHostingView(rootView: Probe(box: box))
        hosting.frame = CGRect(x: 0, y: 0, width: 100, height: 80)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        let top = try? XCTUnwrap(box.frames["top"])
        let bottom = try? XCTUnwrap(box.frames["bottom"])
        XCTAssertEqual(top?.minY ?? -1, 0, accuracy: 0.5, "the first card starts at the top")
        XCTAssertEqual(bottom?.minY ?? -1, 40, accuracy: 0.5, "the second is below it")
    }

    /// And an AppKit view either agrees about which way y grows or says so.
    /// The poll asks rather than assumes, so this only has to be stable.
    func testTheHostingViewSaysWhichWayYGrows() {
        let hosting = NSHostingView(rootView: Color.clear)
        hosting.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        // It is flipped today, which is why converting the pointer through it
        // already lands in SwiftUI's top-down space. The poll handles either
        // answer; this is here so a change shows up as a failing test rather
        // than as a hover that quietly stops working.
        XCTAssertTrue(hosting.isFlipped)
    }
}
