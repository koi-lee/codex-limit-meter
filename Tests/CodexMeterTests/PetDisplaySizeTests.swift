import XCTest
@testable import CodexMeter

final class PetDisplaySizeTests: XCTestCase {
    func testDetailsGrowWithRecordsAndRespectSizeLimit() {
        for size in PetDisplaySize.allCases {
            XCTAssertLessThan(size.detailHeight(page: "changes", count: 1), 220)
            XCTAssertGreaterThan(size.detailHeight(page: "changes", count: 3), size.detailHeight(page: "changes", count: 1))
            XCTAssertEqual(size.detailHeight(page: "changes", count: 100), size.detailMaxHeight)
            XCTAssertLessThan(size.detailHeight(page: "news", count: 0), 300)
        }
        XCTAssertLessThan(PetDisplaySize.small.detailWidth, PetDisplaySize.medium.detailWidth)
        XCTAssertLessThan(PetDisplaySize.medium.detailWidth, PetDisplaySize.large.detailWidth)
    }
    func testPreferenceFallbackAndPersistence() {
        let name = "size-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(PetDisplaySize.selected(in: defaults), .medium)
        defaults.set("invalid", forKey: PetDisplaySize.preferenceKey)
        XCTAssertEqual(PetDisplaySize.selected(in: defaults), .medium)
        for size in PetDisplaySize.allCases {
            defaults.set(size.rawValue, forKey: PetDisplaySize.preferenceKey)
            XCTAssertEqual(PetDisplaySize.selected(in: defaults), size)
        }
    }
}
