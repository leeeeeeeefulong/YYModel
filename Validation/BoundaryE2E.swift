import Foundation
struct Link: Codable { let site: URL; let name: String }
struct FloatBox: Codable { let value: Float; let name: String }
struct DoubleBox: Codable { let value: Double; let name: String }
struct DateBox: Codable { let value: Date; let name: String }
@main struct Runner {
 static func main() throws {
  var results: [String:Any] = [:]
  let yy = YYJSONDecoder()
  func link(_ name: String, _ text: String) {
   var r:[String:Any] = ["input":text]
   do { let m = try yy.decode(Link.self,from:Data(text.utf8));r["url"]=m.site.absoluteString;r["name"]=m.name;r["ok"]=true }
   catch { r["error"]=String(describing:error);r["ok"]=false };results[name]=r
  }
  link("urlClean",#"{"site":"","name":"ok"}"#)
  link("urlDirty",#"{"site":"","name":1}"#)
  do { let m=try yy.decode(Link.self,from:["site":"","name":1]);results["urlAny"]=["ok":true,"url":m.site.absoluteString,"name":m.name] }
  catch { results["urlAny"]=["ok":false,"error":String(describing:error)] }
  for text in [#"{"value":1e39,"name":"ok"}"#,#"{"value":1e39,"name":1}"#,#"{"value":"inf","name":"ok"}"#] {
   var r:[String:Any] = ["input":text]
   do { let m = try yy.decode(FloatBox.self,from:Data(text.utf8));r["ok"]=true;r["finite"]=m.value.isFinite;r["value"]=String(m.value)
    do { _ = try JSONEncoder().encode(m);r["encodable"]=true } catch { r["encodable"]=false }
   } catch { r["ok"]=false;r["error"]=String(describing:error) };results["float:"+text]=r
  }
  for text in ["nan","inf","-inf","1e400"] {
   let data = Data("{\"value\":\"\(text)\",\"name\":\"ok\"}".utf8)
   var r:[String:Any] = [:]
   do { let m = try yy.decode(DoubleBox.self,from:data);r["ok"]=true;r["finite"]=m.value.isFinite;r["value"]=String(m.value)
    do { _ = try JSONEncoder().encode(m);r["encodable"]=true } catch { r["encodable"]=false }
   } catch { r["ok"]=false;r["error"]=String(describing:error) };results["double:"+text]=r
   do { let m=try yy.decode(DateBox.self,from:data);results["date:"+text]=["ok":true,"finite":m.value.timeIntervalSince1970.isFinite,"epoch":String(m.value.timeIntervalSince1970)] }
   catch { results["date:"+text]=["ok":false,"error":String(describing:error)] }
  }
  for t in ["1700000000000","-1700000000000"] {
   for quoted in [false,true] { for dirty in [false,true] {
    let value=quoted ? "\"\(t)\"" : t;let name=dirty ? "1" : "\"ok\""
    let text="{\"value\":\(value),\"name\":\(name)}"
    var r:[String:Any]=["input":text,"expectedEpoch":Double(t)!/1000]
    do { let m=try yy.decode(DateBox.self,from:Data(text.utf8));r["ok"]=true;r["epoch"]=m.value.timeIntervalSince1970;r["name"]=m.name }
    catch { r["ok"]=false;r["error"]=String(describing:error) };results["timestamp:"+text]=r
   }}
  }
  for (label, number) in [("nan",Double.nan),("inf",Double.infinity),("overflow",1e39)] {
   for target in ["Float","Double","CGFloat","Decimal"] {
    var finite: Bool? = nil
    do {
     switch target {
     case "Float": finite = try yy.decode(Float.self,from:NSNumber(value:number)).isFinite
     case "Double": finite = try yy.decode(Double.self,from:NSNumber(value:number)).isFinite
     case "CGFloat": finite = try yy.decode(CGFloat.self,from:NSNumber(value:number)).isFinite
     default: finite = !(try yy.decode(Decimal.self,from:NSNumber(value:number))).isNaN
     }
     results["any:"+target+":"+label] = ["ok":true,"finite":finite!]
    } catch { results["any:"+target+":"+label] = ["ok":false,"error":String(describing:error)] }
   }
  }
  do { let d = try yy.decode(Date.self,from:Date(timeIntervalSince1970:Double.infinity));results["dateAnyInf"]=["ok":true,"finite":d.timeIntervalSince1970.isFinite] }
  catch { results["dateAnyInf"]=["ok":false,"error":String(describing:error)] }
  do { let d = try yy.decode(DoubleBox.self,from:Data(#"{"value":1.5,"name":1}"#.utf8));results["finiteControl"]=["ok":d.value==1.5 && d.name=="1"] }
  catch { results["finiteControl"]=["ok":false] }
  let native=JSONDecoder()
  do { let m=try native.decode(Link.self,from:Data(#"{"site":"","name":"ok"}"#.utf8));results["nativeURL"]=["ok":true,"url":m.site.absoluteString] }
  catch { results["nativeURL"]=["ok":false,"error":String(describing:error)] }
  do { let m=try native.decode(FloatBox.self,from:Data(#"{"value":1e39,"name":"ok"}"#.utf8));results["nativeFloat"]=["ok":true,"finite":m.value.isFinite] }
  catch { results["nativeFloat"]=["ok":false,"error":String(describing:error)] }
  try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
