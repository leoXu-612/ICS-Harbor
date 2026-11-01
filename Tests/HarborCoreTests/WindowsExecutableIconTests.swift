import XCTest
import AppKit
@testable import HarborCore

final class WindowsExecutableIconTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAK0lEQVR4nO3OIQEAAAwEoetfeovxBoGnq1tKQEBAQEBAQEBAQEBAQEBgHXhUDfhqRFDd3gAAAABJRU5ErkJggg==")!

    // Independent minimal PE fixture: resource RVA 0x1000 maps to file offset
    // 0x200; RT_GROUP_ICON 101 references RT_ICON 7 in language 1033.
    private func executable(pe64: Bool = true) -> Data {
        var data = Data(repeating: 0, count: 0x400)
        func put(_ offset: Int, _ value: UInt32, bytes: Int = 4) {
            for i in 0..<bytes { data[offset+i] = UInt8(truncatingIfNeeded: value >> (8*i)) }
        }
        put(0, 0x5a4d, bytes: 2); put(0x3c, 0x80)
        put(0x80, 0x4550); put(0x86, 1, bytes: 2)
        let size = pe64 ? 240 : 224
        put(0x94, UInt32(size), bytes: 2)
        put(0x98, pe64 ? 0x20b : 0x10b, bytes: 2)
        let directories = 0x98 + (pe64 ? 112 : 96)
        put(directories - 4, 16)
        put(directories + 16, 0x1000); put(directories + 20, 0x200)
        let section = 0x98 + size
        put(section+8, 0x200); put(section+12, 0x1000)
        put(section+16, 0x200); put(section+20, 0x200)
        put(0x20e, 2, bytes: 2)
        put(0x210, 3); put(0x214, 0x80000020)
        put(0x218, 14); put(0x21c, 0x80000050)
        put(0x22e, 1, bytes: 2); put(0x230, 7); put(0x234, 0x80000038)
        put(0x246, 1, bytes: 2); put(0x248, 1033); put(0x24c, 0x90)
        put(0x25e, 1, bytes: 2); put(0x260, 101); put(0x264, 0x80000068)
        put(0x276, 1, bytes: 2); put(0x278, 1033); put(0x27c, 0xa0)
        put(0x290, 0x1100); put(0x294, UInt32(png.count))
        put(0x2a0, 0x10c0); put(0x2a4, 20)
        put(0x2c2, 1, bytes: 2); put(0x2c4, 1, bytes: 2)
        data[0x2c6] = 32; data[0x2c7] = 32
        put(0x2ca, 1, bytes: 2); put(0x2cc, 32, bytes: 2)
        put(0x2ce, UInt32(png.count)); put(0x2d2, 7, bytes: 2)
        data.replaceSubrange(0x300..<(0x300+png.count), with: png)
        return data
    }

    func testPE32AndPE32PlusProduceDecodableIcon() throws {
        for pe64 in [false, true] {
            let ico = try XCTUnwrap(WindowsExecutableIcon.iconData(in: executable(pe64: pe64)))
            XCTAssertEqual(ico.prefix(6), Data([0,0,1,0,1,0]))
            XCTAssertEqual(ico.dropFirst(22), png)
            let image = try XCTUnwrap(NSImage(data: ico))
            XCTAssertEqual(image.size.width, 32)
            XCTAssertEqual(image.size.height, 32)
        }
    }

    func testMissingIconReferenceFallsBack() {
        var data = executable(); data[0x2d2] = 8
        XCTAssertNil(WindowsExecutableIcon.iconData(in: data))
    }

    func testTruncatedAndInvalidResourceOffsetsFallBack() {
        let data = executable()
        for length in stride(from: 0, to: 0x300 + png.count, by: 7) {
            XCTAssertNil(WindowsExecutableIcon.iconData(in: Data(data.prefix(length))))
        }
        for offset in [0x3c, 0x118, 0x214, 0x24c, 0x290, 0x294] {
            var invalid = data
            invalid.replaceSubrange(offset..<(offset+4), with: [255,255,255,255])
            XCTAssertNil(WindowsExecutableIcon.iconData(in: invalid))
        }
        XCTAssertNil(WindowsExecutableIcon.iconData(in: Data("not an executable".utf8)))
    }
}
