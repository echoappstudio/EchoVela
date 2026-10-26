import Foundation

/// What macOS reports about a connected display.
public struct DisplayIdentity: Equatable, Sendable {
    public var displayID: UInt32
    public var vendorID: Int
    public var productID: Int
    public var serialNumber: Int
    public var weekOfManufacture: Int
    public var yearOfManufacture: Int
    /// Physical size in millimetres.
    public var horizontalSize: Int
    public var verticalSize: Int
    public var productName: String
    /// The display's place in the I/O Registry, when macOS reports it.
    public var registryLocation: String

    public init(
        displayID: UInt32,
        vendorID: Int = 0,
        productID: Int = 0,
        serialNumber: Int = 0,
        weekOfManufacture: Int = 0,
        yearOfManufacture: Int = 0,
        horizontalSize: Int = 0,
        verticalSize: Int = 0,
        productName: String = "",
        registryLocation: String = ""
    ) {
        self.displayID = displayID
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.weekOfManufacture = weekOfManufacture
        self.yearOfManufacture = yearOfManufacture
        self.horizontalSize = horizontalSize
        self.verticalSize = verticalSize
        self.productName = productName
        self.registryLocation = registryLocation
    }
}

/// An external display connection on Apple silicon that can carry DDC messages, with what the
/// I/O Registry says about the monitor on the other end.
public struct DDCServiceCandidate: Equatable, Sendable {
    /// The connection's position among the Mac's display connections.
    public var index: Int
    /// The registry's "EDID UUID", built from the monitor's EDID.
    public var edidUUID: String
    public var productName: String
    public var serialNumber: Int
    public var registryLocation: String

    public init(index: Int, edidUUID: String = "", productName: String = "", serialNumber: Int = 0, registryLocation: String = "") {
        self.index = index
        self.edidUUID = edidUUID
        self.productName = productName
        self.serialNumber = serialNumber
        self.registryLocation = registryLocation
    }
}

/// Pairs each display with the connection most likely to lead to it.
///
/// macOS doesn't say which connection belongs to which display, so each pair is scored on the
/// details they share. A matching registry location is decisive; matching EDID parts, product
/// name and serial number each add a little.
public enum DisplayServiceMatching {
    public static func score(_ display: DisplayIdentity, _ candidate: DDCServiceCandidate) -> Int {
        var score = 0
        for part in edidParts(of: display) where part.hex != "0000" && edidSegment(candidate.edidUUID, at: part.offset) == part.hex {
            score += 1
        }
        if !candidate.registryLocation.isEmpty, candidate.registryLocation == display.registryLocation {
            score += 10
        }
        if !candidate.productName.isEmpty, candidate.productName.lowercased() == display.productName.lowercased() {
            score += 1
        }
        if candidate.serialNumber != 0, candidate.serialNumber == display.serialNumber {
            score += 1
        }
        return score
    }

    /// Display ID → candidate index. Each display and each connection is used at most once,
    /// best scores first, and a pair that shares nothing is never made.
    public static func assign(displays: [DisplayIdentity], candidates: [DDCServiceCandidate]) -> [UInt32: Int] {
        var pairs: [(score: Int, displayOrder: Int, candidateOrder: Int)] = []
        for (displayOrder, display) in displays.enumerated() {
            for (candidateOrder, candidate) in candidates.enumerated() {
                let pairScore = score(display, candidate)
                if pairScore > 0 {
                    pairs.append((score: pairScore, displayOrder: displayOrder, candidateOrder: candidateOrder))
                }
            }
        }
        pairs.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.displayOrder != rhs.displayOrder { return lhs.displayOrder < rhs.displayOrder }
            return lhs.candidateOrder < rhs.candidateOrder
        }
        var result: [UInt32: Int] = [:]
        var usedCandidates = Set<Int>()
        for pair in pairs {
            let displayID = displays[pair.displayOrder].displayID
            let candidateIndex = candidates[pair.candidateOrder].index
            guard result[displayID] == nil, !usedCandidates.contains(candidateIndex) else { continue }
            result[displayID] = candidateIndex
            usedCandidates.insert(candidateIndex)
        }
        return result
    }

    /// The four-character hex groups of an EDID UUID that come from the vendor, product,
    /// manufacture date and physical size, with where each starts.
    static func edidParts(of display: DisplayIdentity) -> [(hex: String, offset: Int)] {
        let product = UInt16(clamping: display.productID)
        return [
            (hex(UInt16(clamping: display.vendorID)), 0),
            (hex(UInt8(product & 0xFF)) + hex(UInt8(product >> 8)), 4),
            (hex(UInt8(clamping: display.weekOfManufacture)) + hex(UInt8(clamping: display.yearOfManufacture - 1990)), 19),
            (hex(UInt8(clamping: display.horizontalSize / 10)) + hex(UInt8(clamping: display.verticalSize / 10)), 30)
        ]
    }

    static func edidSegment(_ uuid: String, at offset: Int) -> String? {
        let characters = Array(uuid)
        guard offset >= 0, characters.count >= offset + 4 else { return nil }
        return String(characters[offset ..< offset + 4]).uppercased()
    }

    private static func hex(_ value: UInt16) -> String {
        String(format: "%04X", UInt32(value))
    }

    private static func hex(_ value: UInt8) -> String {
        String(format: "%02X", UInt32(value))
    }
}
