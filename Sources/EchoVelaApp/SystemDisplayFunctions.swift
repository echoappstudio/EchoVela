import CoreGraphics
import Darwin
import Foundation
import IOKit

/// Display functions that ship with macOS but aren't in its public SDK. EchoVela looks them up when
/// it starts, so if a macOS update removes one, only the feature that needs it switches off.
enum SystemDisplayFunctions {
    private typealias CreateAVService = @convention(c) (UnsafeRawPointer?, io_service_t) -> UnsafeMutableRawPointer?
    private typealias AVServiceTransfer = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias CreateInfoDictionary = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private typealias DisplayCheck = @convention(c) (UInt32) -> Bool

    private static let libraries = [
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    ]

    nonisolated(unsafe) private static let createAVService = function("IOAVServiceCreateWithService", as: CreateAVService.self)
    nonisolated(unsafe) private static let writeI2C = function("IOAVServiceWriteI2C", as: AVServiceTransfer.self)
    nonisolated(unsafe) private static let readI2C = function("IOAVServiceReadI2C", as: AVServiceTransfer.self)
    nonisolated(unsafe) private static let createInfoDictionary = function("CoreDisplay_DisplayCreateInfoDictionary", as: CreateInfoDictionary.self)
    nonisolated(unsafe) private static let getBrightness = function("DisplayServicesGetBrightness", as: GetBrightness.self)
    nonisolated(unsafe) private static let setBrightness = function("DisplayServicesSetBrightness", as: SetBrightness.self)
    nonisolated(unsafe) private static let hdrSupported = function("CGSIsHDRSupported", as: DisplayCheck.self)
    nonisolated(unsafe) private static let hdrEnabled = function("CGSIsHDREnabled", as: DisplayCheck.self)

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        for path in libraries {
            guard let handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(path, RTLD_LAZY) else { continue }
            if let pointer = dlsym(handle, name) {
                return unsafeBitCast(pointer, to: type)
            }
        }
        return nil
    }

    // MARK: DDC over IOAVService (Apple silicon)

    /// A retained IOAVService for a registry entry, or nil.
    static func makeAVService(for entry: io_service_t) -> UnsafeMutableRawPointer? {
        createAVService?(nil, entry)
    }

    static func releaseAVService(_ service: UnsafeMutableRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(service).release()
    }

    static func write(_ bytes: [UInt8], to service: UnsafeMutableRawPointer, address: UInt8, subAddress: UInt8) -> Bool {
        guard let writeI2C, !bytes.isEmpty else { return false }
        var buffer = bytes
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return writeI2C(service, UInt32(address), UInt32(subAddress), base, UInt32(raw.count))
        }
        return status == 0
    }

    static func read(count: Int, from service: UnsafeMutableRawPointer, address: UInt8) -> [UInt8]? {
        guard let readI2C, count > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: count)
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return readI2C(service, UInt32(address), 0, base, UInt32(raw.count))
        }
        return status == 0 ? buffer : nil
    }

    // MARK: Display information

    /// What CoreDisplay knows about a display: names, vendor and product IDs, size, location.
    static func info(for displayID: CGDirectDisplayID) -> [String: Any] {
        guard let createInfoDictionary, let raw = createInfoDictionary(displayID) else { return [:] }
        let dictionary = Unmanaged<CFDictionary>.fromOpaque(raw).takeRetainedValue() as NSDictionary
        return dictionary as? [String: Any] ?? [:]
    }

    static func isHDROn(_ displayID: CGDirectDisplayID) -> Bool {
        guard let hdrSupported, let hdrEnabled else { return false }
        return hdrSupported(displayID) && hdrEnabled(displayID)
    }

    // MARK: Brightness of Apple and built-in displays

    static func nativeBrightness(of displayID: CGDirectDisplayID) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = -1
        guard getBrightness(displayID, &value) == 0, value >= 0 else { return nil }
        return Double(min(value, 1))
    }

    @discardableResult
    static func setNativeBrightness(_ level: Double, of displayID: CGDirectDisplayID) -> Bool {
        guard let setBrightness else { return false }
        return setBrightness(displayID, Float(level)) == 0
    }
}
