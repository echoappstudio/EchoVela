import Foundation
import IOKit
import EchoVelaCore

/// A DDC/CI connection to one external monitor. Every message goes through one serial queue per
/// monitor, shared by every connection EchoVela makes to it, so a new check after the displays
/// change never talks over an older one. Writes are coalesced: while a write is in flight, newer
/// values replace older ones that haven't been sent yet, so dragging a slider never builds up a backlog.
final class DDCConnection: @unchecked Sendable {
    private let service: UnsafeMutableRawPointer
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pendingWrites: [UInt8: (value: UInt16, always: Bool)] = [:]
    private var lastWritten: [UInt8: UInt16] = [:]
    private var isRetired = false

    /// - Parameter monitorKey: Identifies the monitor (its settings key), so every connection to
    ///   it shares one queue.
    init(service: UnsafeMutableRawPointer, monitorKey: String) {
        self.service = service
        self.queue = DDCQueues.queue(for: monitorKey)
    }

    deinit {
        SystemDisplayFunctions.releaseAVService(service)
    }

    /// Sends a value soon; returns immediately. Brightness skips a value the monitor already has
    /// (a fade sends many); with `always`, the value is sent even if it looks unchanged, because
    /// the monitor may have changed it itself (its own buttons, or a reset in standby).
    func submit(_ control: DDCControl, value: UInt16, always: Bool = false) {
        lock.lock()
        let wasAlways = pendingWrites[control.rawValue]?.always ?? false
        pendingWrites[control.rawValue] = (value, always || wasAlways)
        lock.unlock()
        queue.async { [self] in
            drainWrites()
        }
    }

    /// Asks the monitor for a control's value (about 0.1 s, up to about 1 s if it doesn't answer).
    func read(_ control: DDCControl) async -> DDCReading? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: performRead(control.rawValue))
            }
        }
    }

    /// Stops this connection: a newer one to the same monitor replaces it. Questions still waiting
    /// on the queue return at once instead of taking the monitor's time.
    func retire() {
        lock.lock()
        isRetired = true
        pendingWrites.removeAll()
        lock.unlock()
    }

    // MARK: On the queue

    private var retired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRetired
    }

    private func nextPendingWrite() -> (control: UInt8, value: UInt16, alreadySent: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = pendingWrites.first else { return nil }
        pendingWrites[entry.key] = nil
        return (entry.key, entry.value.value, !entry.value.always && lastWritten[entry.key] == entry.value.value)
    }

    private func markWritten(_ control: UInt8, value: UInt16) {
        lock.lock()
        lastWritten[control] = value
        lock.unlock()
    }

    private func drainWrites() {
        while let write = nextPendingWrite() {
            guard !write.alreadySent else { continue }
            if performWrite(control: write.control, value: write.value) {
                markWritten(write.control, value: write.value)
            }
        }
    }

    private func send(_ bytes: [UInt8]) -> Bool {
        // Monitors miss a message now and then, so each one goes out twice.
        var sent = false
        for _ in 0 ..< 2 {
            usleep(10_000)
            sent = SystemDisplayFunctions.write(bytes, to: service, address: DDCMessage.displayAddress, subAddress: DDCMessage.hostSubAddress)
        }
        return sent
    }

    private func performWrite(control: UInt8, value: UInt16) -> Bool {
        let message = DDCMessage.setRequest(control: control, value: value)
        for _ in 0 ..< 3 {
            if retired { return false }
            if send(message) { return true }
            usleep(20_000)
        }
        return false
    }

    private func performRead(_ control: UInt8) -> DDCReading? {
        for request in [DDCMessage.getRequest(control: control), DDCMessage.lenientGetRequest(control: control)] {
            for _ in 0 ..< 3 {
                if retired { return nil }
                if send(request) {
                    usleep(50_000)
                    if let reply = SystemDisplayFunctions.read(count: DDCMessage.replyLength, from: service, address: DDCMessage.displayAddress),
                       let reading = DDCMessage.parseReply(reply, for: control) {
                        return reading
                    }
                }
                usleep(20_000)
            }
        }
        return nil
    }
}

/// One serial queue per monitor, kept for as long as EchoVela runs (a few monitors at most).
private enum DDCQueues {
    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        var queues: [String: DispatchQueue] = [:]
    }

    private static let store = Store()

    static func queue(for monitorKey: String) -> DispatchQueue {
        store.lock.lock()
        defer { store.lock.unlock() }
        if let queue = store.queues[monitorKey] {
            return queue
        }
        let queue = DispatchQueue(label: "EchoVela.DDC.\(store.queues.count)", qos: .userInitiated)
        store.queues[monitorKey] = queue
        return queue
    }
}

/// Finds the external display connections on an Apple silicon Mac that can carry DDC messages.
enum DDCConnectionFinder {
    struct Found {
        let candidate: DDCServiceCandidate
        let service: UnsafeMutableRawPointer
    }

    private static let framebufferNames: Set<String> = ["AppleCLCD2", "IOMobileFramebufferShim"]
    private static let serviceProxyName = "DCPAVServiceProxy"

    /// In the registry each display connection (a framebuffer) is followed by its
    /// DCPAVServiceProxy, so each proxy is paired with the framebuffer seen just before it.
    static func findExternalConnections() -> [Found] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var found: [Found] = []
        var framebufferCount = 0
        var currentFramebuffer: DDCServiceCandidate?
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            var keepEntry = false
            let name = registryName(of: entry)
            if framebufferNames.contains(name) {
                framebufferCount += 1
                currentFramebuffer = candidate(from: entry, index: framebufferCount)
            } else if name == serviceProxyName,
                      let framebuffer = currentFramebuffer,
                      stringProperty("Location", of: entry) == "External",
                      let service = SystemDisplayFunctions.makeAVService(for: entry) {
                found.append(Found(candidate: framebuffer, service: service))
                // The service may rely on the registry entry, so it stays retained.
                keepEntry = true
            }
            if !keepEntry {
                IOObjectRelease(entry)
            }
        }
        return found
    }

    private static func candidate(from entry: io_registry_entry_t, index: Int) -> DDCServiceCandidate {
        var candidate = DDCServiceCandidate(index: index)
        candidate.edidUUID = stringProperty("EDID UUID", of: entry) ?? ""
        candidate.registryLocation = registryPath(of: entry)
        if let attributes = property("DisplayAttributes", of: entry) as? NSDictionary,
           let product = attributes["ProductAttributes"] as? NSDictionary {
            candidate.productName = product["ProductName"] as? String ?? ""
            candidate.serialNumber = (product["SerialNumber"] as? NSNumber)?.intValue ?? 0
        }
        return candidate
    }

    private static func property(_ key: String, of entry: io_registry_entry_t) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func stringProperty(_ key: String, of entry: io_registry_entry_t) -> String? {
        property(key, of: entry) as? String
    }

    private static func registryName(of entry: io_registry_entry_t) -> String {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        defer { buffer.deallocate() }
        guard IORegistryEntryGetName(entry, buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }

    private static func registryPath(of entry: io_registry_entry_t) -> String {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 512)
        defer { buffer.deallocate() }
        guard IORegistryEntryGetPath(entry, kIOServicePlane, buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }
}
