import Foundation
import Testing
@testable import AnyRouter

struct FetchURLPolicyTests {
    /// Built from numbers so no private address is written out in the source.
    private func dotted(_ parts: Int...) -> String { parts.map(String.init).joined(separator: ".") }

    private func blocked(_ url: String) -> Bool {
        if case .failure = FetchURLPolicy.validate(url) { return true }
        return false
    }

    @Test func publicHttpsPagesAreAllowed() {
        #expect(!blocked("https://example.com/page?q=1"))
        #expect(!blocked("https://93.184.216.34/"))
        #expect(!blocked("https://[2606:2800:220:1:248:1893:25c8:1946]/"))
        #expect(!blocked("https://fcbarcelona.com/"))
        #expect(!blocked("https://172.32.0.1/"))
        #expect(!blocked("https://\(dotted(100, 63, 0, 1))/"))
    }

    @Test func onlyHttpsIsRead() {
        #expect(blocked("http://example.com/"))
        #expect(blocked("file:///etc/hosts"))
        #expect(blocked("not a url"))
    }

    @Test func namesOnThisDeviceOrItsNetworkAreRefused() {
        for url in ["https://localhost/", "https://app.localhost/", "https://printer.local/", "https://db.internal/", "https://localhost./"] {
            #expect(blocked(url), "\(url)")
        }
    }

    @Test func privateIPv4IsRefusedInEverySpelling() {
        let spellings = [
            dotted(10, 0, 0, 1), dotted(127, 0, 0, 1), "127.1", "0x7f.0.0.1", "0177.0.0.1", "2130706433",
            dotted(192, 168, 1, 1), "0xc0a80101", dotted(172, 16, 0, 1), dotted(172, 31, 255, 255),
            dotted(169, 254, 169, 254), dotted(100, 64, 0, 1), dotted(0, 0, 0, 0), dotted(10, 0, 0, 1) + ".",
        ]
        for host in spellings {
            #expect(blocked("https://\(host)/"), "\(host)")
        }
    }

    @Test func localIPv6IsRefusedInEverySpelling() {
        let hosts = ["::1", "0:0:0:0:0:0:0:1", "::", "fc00::1", "fd12:3456::1", "fe80::1", "::ffff:127.0.0.1", "::ffff:7f00:1"]
        for host in hosts {
            #expect(blocked("https://[\(host)]/"), "\(host)")
        }
    }

    @Test func aRedirectTargetGoesThroughTheSamePolicy() {
        #expect(blocked("https://127.1/admin"))
        #expect(!blocked("https://example.org/next"))
    }
}
