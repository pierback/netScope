import AppKit
import Combine
import NetScopeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let model = MenuBarModel()
    private var statusCancellable: AnyCancellable?
    private var isPopoverOpen = false
    private var popoverGlobalDismissMonitor: Any?
    private lazy var rollingObservationScheduler = RollingObservationScheduler(
        isPowerConstrained: { [weak self] in
            self?.isPowerConstrained ?? false
        },
        runSample: { [weak self] completion in
            self?.model.recordRollingAppCounterSample(completion: completion)
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()

        if let button = statusItem.button {
            button.title = ""
            button.image = MenuBarIcon.image(for: .normal)
            button.imagePosition = .imageOnly
            button.toolTip = "NetScope: on-demand network diagnosis"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 680)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: model,
                onClearBaseline: { [weak self] in
                    self?.model.clearBaseline()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )

        statusCancellable = model.$status.sink { [weak self] status in
            self?.renderStatus(status)
        }

        rollingObservationScheduler.start()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit NetScope", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }

        showPopover()
    }

    private func showStatusMenu() {
        closePopover()

        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Check Network Path", action: #selector(checkNetworkPathFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let clearBaselineItem = NSMenuItem(title: "Clear Learned Baseline", action: #selector(clearBaselineFromMenu), keyEquivalent: "")
        clearBaselineItem.target = self
        menu.addItem(clearBaselineItem)

        let quitItem = NSMenuItem(title: "Quit NetScope", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func checkNetworkPathFromMenu() {
        model.refresh()
    }

    @objc private func clearBaselineFromMenu() {
        model.clearBaseline()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        isPopoverOpen = true
        rollingObservationScheduler.setForegroundObservationActive(true)
        rollingObservationScheduler.pause()
        rollingObservationScheduler.runNow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startPopoverDismissMonitoring()
    }

    private func closePopover() {
        popover.performClose(nil)
        markPopoverClosedAndResumeBackgroundObservation()
    }

    func applicationDidResignActive(_ notification: Notification) {
        closePopover()
    }

    func popoverDidClose(_ notification: Notification) {
        markPopoverClosedAndResumeBackgroundObservation()
    }

    private func markPopoverClosedAndResumeBackgroundObservation() {
        let shouldResume = isPopoverOpen || popoverGlobalDismissMonitor != nil
        isPopoverOpen = false
        stopPopoverDismissMonitoring()

        if shouldResume {
            rollingObservationScheduler.setForegroundObservationActive(false)
            rollingObservationScheduler.scheduleNext()
        }
    }

    private func startPopoverDismissMonitoring() {
        stopPopoverDismissMonitoring()
        popoverGlobalDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopPopoverDismissMonitoring() {
        if let monitor = popoverGlobalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverGlobalDismissMonitor = nil
        }
    }

    private var isPowerConstrained: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.isLowPowerModeEnabled || processInfo.thermalState == .serious || processInfo.thermalState == .critical
    }

    func applicationWillTerminate(_ notification: Notification) {
        rollingObservationScheduler.stop()
        stopPopoverDismissMonitoring()
    }

    private func renderStatus(_ status: NetworkStatus) {
        guard let button = statusItem.button else {
            return
        }

        switch status {
        case .normal:
            button.image = MenuBarIcon.image(for: .normal)
            button.toolTip = "NetScope: normal"
        case .possiblePressure:
            button.image = MenuBarIcon.image(for: .possiblePressure)
            button.toolTip = "NetScope: possible network pressure"
        case .likelyIssue:
            button.image = MenuBarIcon.image(for: .likelyIssue)
            button.toolTip = "NetScope: likely network issue"
        }
    }
}
