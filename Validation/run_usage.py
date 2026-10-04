#!/usr/bin/env python3
"""Document date wire conventions and Objective-C optional-property availability.
Exit 0 means the documentation probe completed, not that known limits are fixed.
"""
import argparse
import json
import subprocess
from pathlib import Path
import run as common

OBJC = r'''#import <Foundation/Foundation.h>
#import "YYModel.h"
@interface DateProbe:NSObject
@property(nonatomic,strong) NSDate *created;
@end
@implementation DateProbe @end
int main(int argc,const char *argv[]) { @autoreleasepool {
 NSMutableDictionary *r=[NSMutableDictionary new];
 NSDictionary *inputs=@{@"positiveMillisNumber":@1700000000000LL,@"negativeMillisNumber":@-1700000000000LL,@"positiveSecondsNumber":@1700000000,@"negativeSecondsNumber":@-1700000000,@"positiveMillisString":@"1700000000000",@"negativeMillisString":@"-1700000000000"};
 for(NSString *key in inputs) { DateProbe *m=[DateProbe yy_modelWithDictionary:@{@"created":inputs[key]}];r[key]=m.created?@(m.created.timeIntervalSince1970):NSNull.null; }
 [[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
 }}
'''
SWIFT = r'''import Foundation
struct Stamp:Codable {let created:Date}
@main struct Probe {
 static func main() throws {
  let value=Stamp(created:Date(timeIntervalSince1970:1700000000))
  let defaultData=try JSONEncoder().encode(value)
  let native=try JSONDecoder().decode(Stamp.self,from:defaultData)
  let yy=try YYJSONDecoder().decode(Stamp.self,from:defaultData)
  let configured=JSONEncoder();configured.dateEncodingStrategy = .secondsSince1970
  let explicit=try YYJSONDecoder().decode(Stamp.self,from:configured.encode(value))
  let r:[String:Any]=["expectedEpoch":1700000000,"defaultEncodedJSON":String(decoding:defaultData,as:UTF8.self),"nativeDefaultRoundtrip":native.created.timeIntervalSince1970,"yyDefaultEncoderRoundtrip":yy.created.timeIntervalSince1970,"yyExplicitSecondsEncoderRoundtrip":explicit.created.timeIntervalSince1970]
  try JSONSerialization.data(withJSONObject:r,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
 }
}
'''
OPTIONAL = r'''import Foundation
class OptionalProbe:NSObject { @objc var age:Int? }
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parent/'artifacts/usage')
    args=parser.parse_args();args.source_root=args.source_root.resolve();args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=True)
    for name,text in [('date.m',OBJC),('date.swift',SWIFT),('optional.swift',OPTIONAL)]: (args.output/name).write_text(text)
    source=args.source_root/'YYModel'
    common.execute(['clang','-O2','-fobjc-arc','-framework','Foundation','-I',source,*source.glob('*.m'),args.output/'date.m','-o',args.output/'objc'],args.output,'objc-build.log')
    common.execute([args.output/'objc',args.output/'objc.json'],args.output,'objc.log')
    common.execute(['swiftc','-O',args.source_root/'YYModelSwift/YYJSONDecoder.swift',args.output/'date.swift','-o',args.output/'swift'],args.output,'swift-build.log')
    common.execute([args.output/'swift',args.output/'swift.json'],args.output,'swift.log')
    optional=subprocess.run(['swiftc','-typecheck',str(args.output/'optional.swift')],capture_output=True,text=True)
    (args.output/'optional.log').write_text(optional.stdout+optional.stderr)
    swift=json.loads((args.output/'swift.json').read_text());objc=json.loads((args.output/'objc.json').read_text())
    result=dict(swift=swift,objc=objc,optionalIntRejected=optional.returncode!=0 and 'cannot be represented in Objective-C' in optional.stderr,
                knownLimits=dict(defaultJSONEncoderDateConventionMismatch=swift['yyDefaultEncoderRoundtrip']!=swift['expectedEpoch'],
                                negativeOCMillisecondsUnsupported=objc['negativeMillisNumber']!=-1700000000 or objc['negativeMillisString']!=-1700000000),
                sourceHashes={str(p.relative_to(args.source_root)):common.sha(p) for p in [source/'NSObject+YYModel.m',args.source_root/'YYModelSwift/YYJSONDecoder.swift']},
                validationSHA256=common.sha(Path(__file__)))
    (args.output/'results.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))
    if not result['optionalIntRejected'] or swift['nativeDefaultRoundtrip']!=1700000000 or swift['yyExplicitSecondsEncoderRoundtrip']!=1700000000: return 1
    return 0

if __name__=='__main__':raise SystemExit(main())
