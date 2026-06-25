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

    func makeNSView(context: Context) -> HiddenScrollIndicatorProbeView {
        let view = HiddenScrollIndicatorProbeView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: HiddenScrollIndicatorProbeView, context: Context) {
        nsView.configureScrollIndicatorsIfReady()
    }
}

@MainActor
private final class Coordinator {
    @discardableResult
    func configureScrollView(containing view: NSView) -> Bool {
        guard view.window != nil,
              let scrollView = view.enclosingScrollView else {
            return false
        }

        Self.hideScrollIndicators(in: scrollView)
        return true
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
    private var didConfigureScrollView = false
    private var didScheduleFallback = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            didConfigureScrollView = false
            didScheduleFallback = false
        }

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
        guard !didConfigureScrollView,
              window != nil else {
            return
        }

        if coordinator?.configureScrollView(containing: self) == true {
            didConfigureScrollView = true
            return
        }

        scheduleSingleFallback()
    }

    private func scheduleSingleFallback() {
        guard !didScheduleFallback else {
            return
        }

        didScheduleFallback = true
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.didConfigureScrollView,
                  self.window != nil else {
                return
            }

            if self.coordinator?.configureScrollView(containing: self) == true {
                self.didConfigureScrollView = true
            } else {
                assertionFailure("hiddenAppKitScrollIndicators() must be applied inside a ScrollView so the probe can resolve its enclosing NSScrollView.")
            }
        }
    }
}
