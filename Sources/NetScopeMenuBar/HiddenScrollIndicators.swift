import AppKit
import SwiftUI

extension View {
    func hiddenAppKitScrollIndicators() -> some View {
        background(HiddenScrollIndicatorConfigurator())
    }
}

private struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = HiddenScrollIndicatorProbeView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? HiddenScrollIndicatorProbeView else {
            assertionFailure("Expected HiddenScrollIndicatorProbeView")
            return
        }

        nsView.coordinator = context.coordinator
        context.coordinator.scheduleScrollViewConfiguration(from: nsView)
    }
}

@MainActor
private final class Coordinator {
    private static let configurationDelays: [TimeInterval] = [0.0, 0.05, 0.2]
    private static let maximumVisitedViews = 256

    private var configuredWindowID: ObjectIdentifier?
    private var scheduleGeneration = 0

    func scheduleScrollViewConfiguration(from view: NSView) {
        if let window = view.window,
           configuredWindowID == ObjectIdentifier(window) {
            return
        }

        scheduleGeneration += 1
        let generation = scheduleGeneration

        for delay in Self.configurationDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view] in
                guard let self, let view else {
                    return
                }

                guard generation == self.scheduleGeneration else {
                    return
                }

                if let configuredWindow = Self.configureScrollViews(near: view) {
                    self.configuredWindowID = ObjectIdentifier(configuredWindow)
                }
            }
        }
    }

    private static func configureScrollViews(near view: NSView) -> NSWindow? {
        if let scrollView = view.enclosingScrollView {
            hideScrollIndicators(in: scrollView)
            return view.window
        }

        guard let rootView = view.window?.contentView else {
            return nil
        }

        var didConfigureScrollView = false
        var pendingViews = [rootView]
        var visitedViewCount = 0

        while let currentView = pendingViews.popLast() {
            visitedViewCount += 1

            guard visitedViewCount <= maximumVisitedViews else {
                assertionFailure("Popover scroll indicator search exceeded \(maximumVisitedViews) views")
                return didConfigureScrollView ? view.window : nil
            }

            if let scrollView = currentView as? NSScrollView {
                hideScrollIndicators(in: scrollView)
                didConfigureScrollView = true
            }

            pendingViews.append(contentsOf: currentView.subviews)
        }

        return didConfigureScrollView ? view.window : nil
    }

    private static func hideScrollIndicators(in scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
    }
}

@MainActor
private final class HiddenScrollIndicatorProbeView: NSView {
    weak var coordinator: Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else {
            return
        }

        coordinator?.scheduleScrollViewConfiguration(from: self)
    }
}
