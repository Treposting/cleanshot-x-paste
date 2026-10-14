import Carbon
import Foundation

/// System-wide keyboard shortcuts via Carbon's RegisterEventHotKey.
/// This is what most menu-bar utilities use: it needs no Accessibility permission
/// and the shortcut is swallowed so the frontmost app never sees it.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32

        static func cmdShift(_ key: Int) -> Shortcut {
            Shortcut(keyCode: UInt32(key), modifiers: UInt32(cmdKey | shiftKey))
        }

        static func cmdShiftOption(_ key: Int) -> Shortcut {
            Shortcut(keyCode: UInt32(key), modifiers: UInt32(cmdKey | shiftKey | optionKey))
        }
    }

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    @discardableResult
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_5054), id: id) // 'SHPT'
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            NSLog("ShotPaste: failed to register hotkey \(shortcut) (status \(status))")
            return false
        }
        handlers[id] = handler
        refs.append(ref)
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        guard let handler = handlers[id] else { return }
        Task { @MainActor in handler() }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                HotKeyCenter.shared.fire(hotKeyID.id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
