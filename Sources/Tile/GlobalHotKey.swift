import AppKit
import Carbon

@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { instance.onPress?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, pointer, &handler)
    }

    func register(_ shortcut: String) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        let parts = shortcut.split(separator: "+").map(String.init)
        guard let key = parts.last, let keyCode = Self.keyCodes[key] else { return false }
        var modifiers: UInt32 = 0
        if parts.contains("cmd") { modifiers |= UInt32(cmdKey) }
        if parts.contains("ctrl") { modifiers |= UInt32(controlKey) }
        if parts.contains("option") { modifiers |= UInt32(optionKey) }
        if parts.contains("shift") { modifiers |= UInt32(shiftKey) }
        let identifier = EventHotKeyID(signature: 0x54494C45, id: 1)
        return RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    static func supports(_ shortcut: String) -> Bool {
        guard let key = shortcut.split(separator: "+").last else { return false }
        return keyCodes[String(key)] != nil
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
        "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46, "space": 49, "return": 36,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]
}
