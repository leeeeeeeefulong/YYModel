import Foundation

struct NumericCase: Decodable { let label: String; let target: String; let text: String; let expected: String?; let kind: String? }
struct NumericPayload<T: Decodable>: Decodable { let id: T; let name: String }

@main struct Runner {
    static func main() throws {
        let cases = try JSONDecoder().decode([NumericCase].self, from: Data(contentsOf: URL(fileURLWithPath:CommandLine.arguments[1])))
        let decoder = YYJSONDecoder()
        var output: [[String: Any]] = []
        func decode<T: Decodable>(_ type: T.Type, _ item: NumericCase) throws -> String {
            if item.kind == "nsDecimal" {
                return String(describing:try decoder.decode(NumericPayload<T>.self,from:["id":NSDecimalNumber(string:item.text),"name":1]).id)
            }
            let data = item.kind == "jsonNumber" ? Data("{\"id\":\(item.text),\"name\":1}".utf8) : try JSONSerialization.data(withJSONObject:["id":item.text,"name":1])
            return String(describing:try decoder.decode(NumericPayload<T>.self,from:data).id)
        }
        for item in cases {
            var entry: [String: Any] = ["label":item.label,"target":item.target,"text":item.text,"expected":item.expected as Any? ?? NSNull()]
            do {
                let value: String
                switch item.target {
                case "Int64": value = try decode(Int64.self,item)
                case "UInt64": value = try decode(UInt64.self,item)
                case "Int8": value = try decode(Int8.self,item)
                case "UInt8": value = try decode(UInt8.self,item)
                case "Decimal": value = try decode(Decimal.self,item)
                default: throw NSError(domain:"validation",code:1)
                }
                entry["actual"] = value
                entry["passed"] = item.expected == value
            } catch {
                entry["error"] = String(describing:error)
                entry["passed"] = item.expected == nil
            }
            output.append(entry)
        }
        let data = try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        let failures = output.filter { !($0["passed"] as! Bool) }.count
        print("Numeric cases: \(output.count), failed: \(failures)")
    }
}
