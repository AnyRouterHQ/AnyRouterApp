import Testing
import UIKit
@testable import AnyRouter

struct LaunchAssetsTests {
    @Test func launchScreenAssetsExistInCatalog() throws {
        let launch = try #require(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any])
        let image = try #require(launch["UIImageName"] as? String)
        let color = try #require(launch["UIColorName"] as? String)
        #expect(UIImage(named: image, in: .main, compatibleWith: nil) != nil)
        #expect(UIColor(named: color, in: .main, compatibleWith: nil) != nil)
    }
}
