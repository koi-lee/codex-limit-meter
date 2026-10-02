import Foundation

enum AccountRegionAccess: Equatable {
    case unknown
    case restricted
    case available

    init(countryCode: String?) {
        guard let countryCode else {
            self = .unknown
            return
        }
        self = countryCode.uppercased() == "CHN" ? .restricted : .available
    }

    var allowsPersonalQuota: Bool { self == .available }
}
