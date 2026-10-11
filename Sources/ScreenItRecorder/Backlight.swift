import AppKit

/// Display backlight through Apple's private DisplayServices framework (works for Apple
/// displays such as the Studio Display). Screen capture records the image before the
/// backlight, so dimming never changes the recorded colours. If the symbols are missing on
/// some future macOS, every call is a no-op.
enum Backlight {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static func displayID(_ screen: NSScreen) -> UInt32? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }

    static func get(_ id: UInt32) -> Float? {
        var value: Float = 0
        guard let getFn, getFn(id, &value) == 0 else { return nil }
        return value
    }

    static func set(_ id: UInt32, _ value: Float) {
        _ = setFn?(id, min(1, max(0, value)))
    }
}
