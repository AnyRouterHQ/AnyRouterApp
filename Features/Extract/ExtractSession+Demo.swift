import Foundation

/// Demo data for screenshots and UI tests (`-ARDemoData YES -ARDemoExtract <stage>`; `applyDemo(stage:)` uses it). The
/// model's answer is canned, so no engine or network is involved.
extension ExtractSession {
    static let demoName = "receipt.png"
    static let demoText = "CAFE SAIGON\nPho bo 65,000\nTra da 15,000\nTOTAL 80,000\nCảm ơn quý khách"
    /// Date is empty, Tax quotes words the receipt does not have, Payment method is left out: the three kinds of "no source".
    static let demoReply = ##"""
        [{"name":"Merchant","value":"Cafe Saigon","quote":"CAFE SAIGON"},
         {"name":"Date","value":"","quote":""},
         {"name":"Total","value":"80,000","quote":"TOTAL 80,000"},
         {"name":"Tax","value":"8,000","quote":"VAT 10% 8,000"}]
        """##

    /// The stage the launch arguments ask for: "empty", "document", "fields" or "selected". Nil outside demo runs.
    static var demoStage: String? {
        DemoData.isEnabled ? UserDefaults.standard.string(forKey: "ARDemoExtract") : nil
    }
}
