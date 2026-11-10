#if !APPSTORE
import Foundation
import IOKit.ps

/// Notices the charger being plugged in or out, and has the level card show the battery.
///
/// Public API only (IOKit power sources), and no polling: macOS calls back when a power
/// source changes, so it costs nothing while nothing happens. That callback also comes each
/// time the charge moves a percent; only a change of power source (SystemHUDLogic.chargerChange)
/// shows the card. A Mac without a battery never gets a reading, so nothing ever shows.
///
/// Off by default (Settings → Volume & brightness → Charging). Needs no Accessibility.
@MainActor
final class BatteryWatcher {
    static let shared = BatteryWatcher()

    private var source: CFRunLoopSource?
    /// Plugged in at the last reading; nil until the first one (the baseline, never shown).
    private var wasOnPower: Bool?

    /// Whether this Mac has a battery at all (Settings hides the switch on a desktop Mac).
    static var hasBattery: Bool { MachineVitals.readBattery() != nil }

    private init() {}

    /// At launch and from Settings.
    func update() {
        if SystemHUDController.isEnabled(.battery) { start() } else { stop() }
    }

    private func start() {
        guard source == nil else { return }
        wasOnPower = MachineVitals.readBattery()?.onPower
        guard let source = IOPSNotificationCreateRunLoopSource(batteryWatcherCallback, nil)?
            .takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
    }

    private func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        self.source = nil
        wasOnPower = nil
    }

    fileprivate func powerSourceChanged() {
        guard let battery = MachineVitals.readBattery() else { return }
        let change = SystemHUDLogic.chargerChange(was: wasOnPower, now: battery.onPower)
        wasOnPower = battery.onPower
        guard let change else { return }
        SystemHUDController.shared.showBattery(percent: battery.percent,
                                               onPower: battery.onPower,
                                               direction: change)
    }
}

/// IOKit's C callback: on the main run loop, where the source was added.
private func batteryWatcherCallback(_ context: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated { BatteryWatcher.shared.powerSourceChanged() }
}
#endif
