import Foundation
import YYModel
import YYModelSwift

@objcMembers final class OldModel: NSObject { var id: Int = 0 }
struct NewModel: YYModelCodable { var id: Int; var name: String }

@main struct MixedModelRunner {
    static func main() throws {
        let json = #"{"id":7,"name":"Swift"}"#
        let old = OldModel.yy_model(withJSON: json)
        let new = try NewModel.yy_decode(withJSON: json)
        let checks = ["independentPublicImports":old?.id == new.id && new.name == "Swift",
                      "swiftExport":new.yy_modelToJSONData().flatMap { NewModel.yy_model(withJSON: $0) }?.id == 7]
        try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Mixed model contracts: \(checks.values.filter {$0}.count)/\(checks.count)")
    }
}
