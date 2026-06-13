import AppKit
import SwiftUI

extension View {
    func hiddenAppKitScrollIndicators() -> some View {
        background(HiddenScrollIndicatorConfigurator())
    }
}

private struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleScrollViewConfiguration(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleScrollViewConfiguration(from: nsView)
    }

    private func scheduleScrollViewConfiguration(from view: NSView) {
        for delay in [0.0, 0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                configureScrollViews(near: view)
            }
        }
    }

    private func configureScrollViews(near view: NSView) {
        if let scrollView = view.enclosingScrollView {
            hideScrollIndicators(in: scrollView)
        }

        guard let rootView = view.window?.contentView else {
            return
        }

        for scrollView in scrollViews(in: rootView) {
            hideScrollIndicators(in: scrollView)
        }
    }

    private func hideScrollIndicators(in scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap(scrollViews(in:))
    }
}
