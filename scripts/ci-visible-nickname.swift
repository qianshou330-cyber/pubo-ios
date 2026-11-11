import Foundation
import Vision

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var observations = [[String: Any]]()
for phase in ["normal", "accessibility"] {
    for (kind, expected) in [("author", "这是一"), ("guest-author", "测试朋")] {
        let name = phase + "-" + kind + "-crop.png"
        let file = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { continue }
        var item: [String: Any] = ["file":name, "expectedPrefix":expected]
        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(url:file, options:[:]).perform([request])
            let texts = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let compact = texts.joined().filter { !$0.isWhitespace }
            item["recognized"] = texts
            item["matched"] = compact.contains(expected)
        } catch {
            item["recognizerError"] = String(describing: type(of:error))
            item["matched"] = false
        }
        observations.append(item)
    }
}
let data = try JSONSerialization.data(withJSONObject:observations, options:[.prettyPrinted,.sortedKeys])
try data.write(to:root.appendingPathComponent("vision-visible-nickname.json"))
