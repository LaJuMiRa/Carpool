import Testing
@testable import CarpoolUI

struct CarColorTests {
    @Test(arguments: [(1, 1), (2, 2), (3, 3), (4, 1), (5, 2), (7, 1), (0, 1)])
    func slotsCycleThroughThreeSets(slot: Int, set: Int) {
        #expect(CarColor(slot: slot).set == set)
    }
}

struct CarNamingTests {
    @Test func nicknameIsTitle() {
        let naming = CarNaming(make: "VW", model: "Golf", nickname: "Radieschen")
        #expect(naming.title == "Radieschen")
        #expect(naming.subtitle == "VW Golf")
        #expect(naming.spokenName == "Radieschen, VW Golf")
    }

    @Test func modelIsTitleWithoutNickname() {
        let naming = CarNaming(make: "Škoda", model: "Octavia", nickname: "  ")
        #expect(naming.nickname == nil)
        #expect(naming.title == "Octavia")
    }
}

struct CarBodyStyleTests {
    @Test(arguments: [("Octavia", CarBodyStyle.wagon), ("Golf Variant", .wagon), ("CX-5", .wagon),
                      ("Yaris", .hatchback), ("500", .hatchback), ("Golf", .sedan), ("Model 3", .sedan)])
    func guessesFromModel(model: String, style: CarBodyStyle) {
        #expect(CarBodyStyle.guess(model: model) == style)
    }
}

struct PaintColorTests {
    @Test func specificNamesWinOverGeneric() {
        #expect(PaintColor.rgb(for: "Dunkelgrau") == 0x4A4F55)
        #expect(PaintColor.rgb(for: "grau metallic") == 0x8A8F95)
    }

    @Test func unknownPaintFallsBack() {
        #expect(PaintColor.rgb(for: "Mondstaub") == 0xB8BCC0)
    }

    @Test func darkPaintsAreDetected() {
        #expect(PaintColor.isDark("schwarz"))
        #expect(!PaintColor.isDark("silber"))
    }
}
