#import <Foundation/Foundation.h>
#import "YYModel.h"
#include <math.h>
@interface PublicDateModel : NSObject
@property(nonatomic,strong) NSDate *created;
@end
@implementation PublicDateModel @end
int main(int argc, const char *argv[]) { @autoreleasepool {
    NSArray *cases = @[
        @[@"positiveNumberMillis", @1700000000000LL, @1700000000],
        @[@"negativeNumberMillis", @-1700000000000LL, @-1700000000],
        @[@"negativeNumberSeconds", @-1700000000, @-1700000000],
        @[@"positiveStringMillis", @"1700000000000", @1700000000],
        @[@"negativeStringMillis", @"-1700000000000", @-1700000000],
        @[@"negativeStringSeconds", @"-1700000000", @-1700000000],
        @[@"whitespaceNegativeMillis", @" \t-1700000000000\n", @-1700000000],
        @[@"zeroNumber", @0, @0], @[@"zeroString", @"0000000000", @0],
        @[@"nan", @(NAN), NSNull.null], @[@"infinity", @(INFINITY), NSNull.null],
        @[@"negativeInfinity", @(-INFINITY), NSNull.null],
        @[@"ISO", @"2023-11-14T22:13:20Z", @1700000000],
        @[@"dateOnly", @"2026-10-03", @1790985600],
        @[@"RFC", @"Sat, 03 Oct 2026 08:00:00 +0000", @1791014400],
        @[@"asctime", @"Sat Oct 03 08:00:00 2026", @1791014400],
    ];
    NSMutableDictionary *results = [NSMutableDictionary new];
    for (NSArray *item in cases) {
        PublicDateModel *model = [PublicDateModel yy_modelWithDictionary:@{@"created":item[1]}];
        NSTimeInterval timestamp = model.created.timeIntervalSince1970;
        id actual = !model.created ? NSNull.null : isfinite(timestamp) ? @(timestamp) : @"nonfinite";
        BOOL passed = item[2] == NSNull.null ? actual == NSNull.null : [actual isKindOfClass:NSNumber.class] && fabs([actual doubleValue]-[item[2] doubleValue]) < 0.001;
        results[item[0]] = @{@"actual":actual, @"expected":item[2], @"passed":@(passed)};
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
    return data && [data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 2;
} }
