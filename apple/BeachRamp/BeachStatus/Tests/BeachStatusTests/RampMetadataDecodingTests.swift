import Foundation
import Testing
@testable import BeachStatus

struct RampMetadataDecodingTests {
    private func decode(_ json: String) throws -> Ramp {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Ramp.self, from: Data(json.utf8))
    }

    private let base = """
    "id": 3, "ramp_name": "BEACHWAY AV", "access_status": "OPEN",
    "status_category": "open", "object_id": 42, "city": "NEW SMYRNA BEACH",
    "access_id": "NSB-001", "location": "S OF FLAGLER", "last_updated": "2026-08-15T12:00:00Z"
    """

    @Test func decodesWithoutMetadata() throws {
        let ramp = try decode("{\(base)}")
        #expect(ramp.shortName == nil)
        #expect(ramp.address == nil)
        #expect(ramp.drivingHours == nil)
        #expect(ramp.closureHeightFt == nil)
        #expect(ramp.sortOrder == nil)
        #expect(ramp.shortDisplayName == "Beachway Av")
    }

    @Test func decodesWithMetadata() throws {
        let ramp = try decode("""
        {\(base),
         "short_name": "Beachway", "address": "100 N Atlantic Ave",
         "driving_hours": "8:00 AM – 7:30 PM", "closure_height_ft": 2.4, "sort_order": 1}
        """)
        #expect(ramp.shortName == "Beachway")
        #expect(ramp.closureHeightFt == 2.4)
        #expect(ramp.sortOrder == 1)
        #expect(ramp.shortDisplayName == "Beachway")
    }

    @Test func boardOrderPutsOrderedFirstThenNames() throws {
        func ramp(_ name: String, order: Int?) -> Ramp {
            Ramp(id: name.hashValue, rampName: name, accessStatus: "OPEN", statusCategory: "open",
                 objectID: 1, city: "NSB", accessID: name, location: "", lastUpdated: nil,
                 sortOrder: order)
        }
        let sorted = [ramp("3RD AV", order: 4), ramp("ZULU", order: nil),
                      ramp("BEACHWAY AV", order: 1), ramp("ALPHA", order: nil)].boardOrdered()
        #expect(sorted.map(\.rampName) == ["BEACHWAY AV", "3RD AV", "ALPHA", "ZULU"])
    }
}
