import AppKit
import SwiftUI

struct HeaderIconButton: NSViewRepresentable {
    let systemSymbolName: String
    let tooltip: String
    let onPress: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPress: onPress)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.press(_:))
        button.setButtonType(.momentaryChange)
        button.toolTip = tooltip
        configureImage(for: button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onPress = onPress
        button.toolTip = tooltip
        configureImage(for: button)
    }

    private func configureImage(for button: NSButton) {
        guard let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: tooltip) else {
            return
        }

        image.isTemplate = true
        image.size = NSSize(width: 15, height: 15)
        button.image = image
    }

    final class Coordinator: NSObject {
        var onPress: () -> Void

        init(onPress: @escaping () -> Void) {
            self.onPress = onPress
        }

        @MainActor
        @objc func press(_ sender: NSButton) {
            onPress()
        }
    }
}
