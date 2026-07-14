import Carbon
import Foundation

/// A hold-to-peek shortcut that does not require Input Monitoring. Option-Space
/// only changes the assistant's own presentation; it never sends input to BG3.
final class GlobalPeekHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onChange: ((Bool) -> Void)?

    func start(onChange: @escaping (Bool) -> Void) {
        guard hotKey == nil else { return }
        self.onChange = onChange
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let owner = Unmanaged<GlobalPeekHotKey>.fromOpaque(userData).takeUnretainedValue()
                owner.onChange?(GetEventKind(event) == UInt32(kEventHotKeyPressed))
                return noErr
            },
            events.count,
            &events,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        let identifier = EventHotKeyID(signature: 0x42473350, id: 1) // "BG3P"
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        onChange = nil
    }

    deinit { stop() }
}
