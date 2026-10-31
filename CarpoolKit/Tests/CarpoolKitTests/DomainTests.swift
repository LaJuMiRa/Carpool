import Testing
@testable import CarpoolKit

struct FuelLevelTests {
    @Test(arguments: [(1, "¼"), (2, "½"), (3, "¾"), (4, "voll")])
    func labels(quarters: Int, label: String) {
        #expect(FuelLevel(quarters: quarters).label == label)
    }

    @Test func clampsOutOfRange() {
        #expect(FuelLevel(quarters: 0).quarters == 1)
        #expect(FuelLevel(quarters: 9).quarters == 4)
    }

    @Test(arguments: [(0.0, 1), (0.3, 1), (0.4, 2), (0.6, 2), (0.65, 3), (0.9, 4), (1.2, 4)])
    func snapsToNearestQuarter(fraction: Double, quarters: Int) {
        #expect(FuelLevel.nearest(toFraction: fraction).quarters == quarters)
    }
}

struct CarStatusTests {
    @Test func labelsAreSingleWords() {
        #expect(CarStatus.allCases.map(\.label) == ["frei", "reserviert", "unterwegs"])
    }
}
