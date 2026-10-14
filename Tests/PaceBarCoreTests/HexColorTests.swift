import XCTest
@testable import PaceBarCore

final class HexColorTests: XCTestCase {
    func testParsesLongAndShortForms() {
        XCTAssertEqual(HexColor.parse("#0A84FF"), 0x0A84FF)
        XCTAssertEqual(HexColor.parse("0a84ff"), 0x0A84FF)
        XCTAssertEqual(HexColor.parse("  #ff9500\n"), 0xFF9500)
        XCTAssertEqual(HexColor.parse("#FFF"), 0xFFFFFF)
        XCTAssertEqual(HexColor.parse("f80"), 0xFF8800)
        XCTAssertEqual(HexColor.parse("#000000"), 0)
    }

    func testRejectsAnythingElse() {
        for bad in ["", "#", "#12", "#1234", "#12345", "#1234567", "#GG0000", "0x0A84FF", "# 0A84FF", "+FFF", "－FFF", "٠٠٠"] {
            XCTAssertNil(HexColor.parse(bad), bad)
        }
    }

    func testFormats() {
        XCTAssertEqual(HexColor.format(0x0A84FF), "#0A84FF")
        XCTAssertEqual(HexColor.format(0), "#000000")
        XCTAssertEqual(HexColor.format(0xFF_FFFFFF), "#FFFFFF") // stray alpha bits ignored
    }

    func testRoundTrip() {
        for hex: UInt32 in [0, 0x141417, 0x86EFAC, 0xFFFFFF] {
            XCTAssertEqual(HexColor.parse(HexColor.format(hex)), hex)
        }
    }

    func testContrastRatio() {
        XCTAssertEqual(HexColor.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(HexColor.contrastRatio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
        XCTAssertEqual(HexColor.contrastRatio(0x777777, 0x777777), 1, accuracy: 0.0001)
        // WCAG reference: #767676 on white is just over 4.5:1.
        XCTAssertEqual(HexColor.contrastRatio(0x767676, 0xFFFFFF), 4.54, accuracy: 0.01)
    }
}
