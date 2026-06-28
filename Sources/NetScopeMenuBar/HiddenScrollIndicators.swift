import AppKit
import SwiftUI

extension View {
    func hiddenAppKitScrollIndicators() -> some View {
        background(HiddenScrollIndicatorConfigurator())
    }
}

private struct HiddenScrollIndicatorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> HiddenScrollIndicatorProbeView {
        HiddenScrollIndicatorProbeView(frame: .zero)
    }

    func updateNSView(_ nsView: HiddenScrollIndicatorProbeView, context: Context) {
        nsView.configureScrollIndicatorsIfReady()
    }
}

@MainActor
private final class HiddenScrollIndicatorProbeView: NSView {
    private static let maximumFallbackChecks = 3

    private weak var configuredScrollView: NSScrollView?
    private var fallbackCheckCount = 0
    private var isFallbackCheckQueued = false
    private var lifecycleGeneration = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        resetConfigurationState()
        configureScrollIndicatorsIfReady()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()

        configureScrollIndicatorsIfReady()
    }

    override func layout() {
        super.layout()

        configureScrollIndicatorsIfReady()
    }

    func configureScrollIndicatorsIfReady() {
        guard window != nil else {
            return
        }

        if configureEnclosingScrollViewIfAvailable() {
            return
        }

        scheduleFallbackCheckIfNeeded()
    }

    private func resetConfigurationState() {
        lifecycleGeneration += 1
        configuredScrollView = nil
        fallbackCheckCount = 0
        isFallbackCheckQueued = false
    }

    private func scheduleFallbackCheckIfNeeded() {
        guard !isFallbackCheckQueued,
              fallbackCheckCount < Self.maximumFallbackChecks else {
            return
        }

        isFallbackCheckQueued = true
        let scheduledGeneration = lifecycleGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            guard self.lifecycleGeneration == scheduledGeneration else {
                return
            }

            self.isFallbackCheckQueued = false

            guard self.window != nil else {
                return
            }

            self.fallbackCheckCount += 1
            guard !self.configureEnclosingScrollViewIfAvailable() else {
                return
            }

            self.scheduleFallbackCheckIfNeeded()
        }
    }

    @discardableResult
    private func configureEnclosingScrollViewIfAvailable() -> Bool {
        guard let scrollView = enclosingScrollView else {
            return false
        }

        if configuredScrollView !== scrollView || !Self.areScrollIndicatorsHidden(in: scrollView) {
            Self.hideScrollIndicators(in: scrollView)
        }

        configuredScrollView = scrollView
        fallbackCheckCount = 0
        isFallbackCheckQueued = false
        return true
    }

    private static func areScrollIndicatorsHidden(in scrollView: NSScrollView) -> Bool {
        scrollView.hasVerticalScroller == false &&
        scrollView.hasHorizontalScroller == false &&
        scrollView.verticalScroller == nil &&
        scrollView.horizontalScroller == nil &&
        scrollView.autohidesScrollers &&
        scrollView.scrollerStyle == .overlay
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
