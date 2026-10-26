import Foundation

/// The monitor settings EchoVela changes over DDC/CI (VESA MCCS control codes).
public enum DDCControl: UInt8, CaseIterable, Sendable {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
}

/// A value a monitor reported for one control, with the largest value it accepts.
public struct DDCReading: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16

    public init(current: UInt16, maximum: UInt16) {
        self.current = current
        self.maximum = maximum
    }
}

/// Builds the DDC/CI messages EchoVela sends to a monitor and checks the replies.
///
/// A message goes to I²C address 0x37 (0x6E when written as an 8-bit address) with the host's
/// sub-address 0x51. The bytes after the sub-address are a length byte (0x80 + payload size),
/// the payload, and an XOR checksum of everything sent, including both addresses.
public enum DDCMessage {
    public static let displayAddress: UInt8 = 0x37
    public static let hostSubAddress: UInt8 = 0x51
    /// Bytes in a "Get VCP Feature" reply, from the monitor's address to the checksum.
    public static let replyLength = 11

    private static let getOpcode: UInt8 = 0x01
    private static let replyOpcode: UInt8 = 0x02
    private static let setOpcode: UInt8 = 0x03
    /// A reply's checksum starts from 0x50, the address the monitor answers to.
    private static let replyChecksumSeed: UInt8 = 0x50

    public static func checksum(seed: UInt8, bytes: some Sequence<UInt8>) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    /// The bytes to send after the sub-address to set a control to a value.
    public static func setRequest(control: UInt8, value: UInt16) -> [UInt8] {
        packet(payload: [setOpcode, control, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// The bytes to send after the sub-address to ask for a control's value.
    public static func getRequest(control: UInt8) -> [UInt8] {
        packet(payload: [getOpcode, control])
    }

    /// The same request with a checksum that leaves out the sub-address. A few monitors were
    /// only ever tested with this form, so EchoVela tries it when the standard request gets no reply.
    public static func lenientGetRequest(control: UInt8) -> [UInt8] {
        var bytes = getRequest(control: control)
        bytes[bytes.count - 1] = checksum(seed: displayAddress << 1, bytes: bytes.dropLast())
        return bytes
    }

    /// Reads a "Get VCP Feature" reply. Returns nil for a damaged reply, an error from the monitor,
    /// or a reply that claims the control has no range.
    public static func parseReply(_ reply: [UInt8]) -> DDCReading? {
        guard reply.count == replyLength else { return nil }
        guard checksum(seed: replyChecksumSeed, bytes: reply.dropLast()) == reply[replyLength - 1] else { return nil }
        guard reply[2] == replyOpcode, reply[3] == 0x00 else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0 else { return nil }
        return DDCReading(current: current, maximum: maximum)
    }

    private static func packet(payload: [UInt8]) -> [UInt8] {
        var bytes = [0x80 | UInt8(payload.count)] + payload
        let seed = (displayAddress << 1) ^ hostSubAddress
        bytes.append(checksum(seed: seed, bytes: bytes))
        return bytes
    }
}
