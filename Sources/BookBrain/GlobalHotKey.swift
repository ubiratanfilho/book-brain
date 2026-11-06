import Carbon
import Foundation

final class GlobalHotKey {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: () -> Void

  init(action: @escaping () -> Void) { self.action = action }

  func register() -> Bool {
    var event = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let context = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
        owner.action()
        return noErr
      }, 1, &event, context, &handler)
    guard status == noErr else { return false }
    let id = EventHotKeyID(signature: 0x4242_524E, id: 1)
    return RegisterEventHotKey(
      UInt32(kVK_ANSI_B), UInt32(cmdKey | shiftKey), id,
      GetApplicationEventTarget(), 0, &hotKey
    ) == noErr
  }

  deinit {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let handler { RemoveEventHandler(handler) }
  }
}
