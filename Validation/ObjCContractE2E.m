#import <Foundation/Foundation.h>
#import "YYModel.h"
#include <math.h>

@interface ContractPointer : NSObject
@property(nonatomic) void *value;
@end
@implementation ContractPointer
- (NSUInteger)hash { return [self yy_modelHash]; }
- (BOOL)isEqual:(id)object { return [self yy_modelIsEqual:object]; }
@end
@interface ContractConstantHashPointer : ContractPointer @end
@implementation ContractConstantHashPointer
- (NSUInteger)hash { return 0; }
@end
@interface ContractCString : NSObject
@property(nonatomic) char *value;
@end
@implementation ContractCString
- (NSUInteger)hash { return [self yy_modelHash]; }
- (BOOL)isEqual:(id)object { return [self yy_modelIsEqual:object]; }
@end
@interface ContractMixed : ContractPointer
@property(nonatomic,copy) NSString *name;
@end
@implementation ContractMixed @end
@interface ContractFloating : NSObject
@property(nonatomic) double value;
@end
@implementation ContractFloating
- (NSUInteger)hash { return [self yy_modelHash]; }
- (BOOL)isEqual:(id)object { return [self yy_modelIsEqual:object]; }
@end

@interface ContractMapperBase : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *tail;
@end
@implementation ContractMapperBase
+ (NSDictionary *)modelCustomPropertyMapper { return @{@"name":@"legacy"}; }
@end
@interface ContractMapperChild : ContractMapperBase @end
@implementation ContractMapperChild
+ (NSDictionary *)modelCustomPropertyMapper { return @{@"tail":@"other"}; }
@end
@interface ContractMapperMerged : ContractMapperChild <YYModel> @end
@implementation ContractMapperMerged
+ (BOOL)modelMergesSuperclassConfiguration { return YES; }
@end
@interface ContractMapperDisabled : ContractMapperMerged @end
@implementation ContractMapperDisabled
+ (BOOL)modelMergesSuperclassConfiguration { return NO; }
@end
@interface ContractMapperOverride : ContractMapperMerged @end
@implementation ContractMapperOverride
+ (NSDictionary *)modelCustomPropertyMapper { return @{@"name":@"renamed"}; }
@end

@interface ContractItem : NSObject <NSSecureCoding>
@property(nonatomic,copy) NSString *name;
@end
@implementation ContractItem
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self yy_modelEncodeWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    return [self yy_modelInitWithCoder:coder];
}
@end
@interface ContractGenericBase : NSObject
@property(nonatomic,strong) NSArray *members;
@property(nonatomic,strong) NSArray *other;
@end
@implementation ContractGenericBase
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{@"members":ContractItem.class}; }
@end
@interface ContractGenericChild : ContractGenericBase @end
@implementation ContractGenericChild
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{@"other":ContractItem.class}; }
@end
@interface ContractGenericMerged : ContractGenericChild @end
@implementation ContractGenericMerged
+ (BOOL)modelMergesSuperclassConfiguration { return YES; }
@end

@interface ContractListBase : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *tail;
@end
@implementation ContractListBase @end
@interface ContractBlackBase : ContractListBase @end
@implementation ContractBlackBase
+ (NSArray *)modelPropertyBlacklist { return @[@"name"]; }
@end
@interface ContractBlackChild : ContractBlackBase @end
@implementation ContractBlackChild
+ (NSArray *)modelPropertyBlacklist { return @[@"tail"]; }
+ (BOOL)modelMergesSuperclassConfiguration { return YES; }
@end
@interface ContractWhiteBase : ContractListBase @end
@implementation ContractWhiteBase
+ (NSArray *)modelPropertyWhitelist { return @[@"name"]; }
@end
@interface ContractWhiteChild : ContractWhiteBase @end
@implementation ContractWhiteChild
+ (NSArray *)modelPropertyWhitelist { return @[@"tail"]; }
+ (BOOL)modelMergesSuperclassConfiguration { return YES; }
@end

@interface ContractDynamic : NSObject
@property(nonatomic,strong) NSString *name;
@end
@implementation ContractDynamic
@dynamic name;
- (NSString *)name { return @"ObjC"; }
- (void)setName:(NSString *)name {}
@end
@interface ContractValue : NSObject
@property(nonatomic) unsigned long long identifier;
@property(nonatomic,strong) NSDate *date;
@end
@implementation ContractValue @end
@interface ContractArchive : NSObject <NSSecureCoding>
@property(nonatomic,strong) NSArray *members;
@end
@implementation ContractArchive
+ (BOOL)supportsSecureCoding { return YES; }
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{@"members":ContractItem.class}; }
- (void)encodeWithCoder:(NSCoder *)coder { [self yy_modelEncodeWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    return [self yy_modelInitWithCoder:coder];
}
@end

// Legacy non-secure archive round trips are checked separately from secure
// allowlist requirements, with and without a declared generic member class.
@interface ContractGapItem : NSObject <NSSecureCoding>
@property(nonatomic,copy) NSString *name;
@end
@implementation ContractGapItem
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self yy_modelEncodeWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    return [self yy_modelInitWithCoder:coder];
}
@end
@interface ContractGapArchive : NSObject <NSCoding>
@property(nonatomic,strong) NSArray *members;
@end

@interface ContractGapUndeclaredArchive : ContractGapArchive @end
@implementation ContractGapUndeclaredArchive
+ (NSDictionary *)modelContainerPropertyGenericClass { return nil; }
@end
@implementation ContractGapArchive
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{@"members":ContractGapItem.class}; }
- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    return [self yy_modelInitWithCoder:aDecoder];
}
- (void)encodeWithCoder:(NSCoder *)aCoder {
    [self yy_modelEncodeWithCoder:aCoder];
}
@end

static void Check(NSMutableDictionary *checks, NSString *name, id actual, id expected) {
    actual = actual ?: NSNull.null;
    expected = expected ?: NSNull.null;
    checks[name] = @{@"actual":actual,@"expected":expected,@"passed":@([actual isEqual:expected])};
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 2) return 2;
    NSMutableDictionary *checks = [NSMutableDictionary new];
    ContractPointer *left = [ContractPointer new], *right = [ContractPointer new];
    left.value = (void *)1; right.value = (void *)2;
    Check(checks,@"pointer:different",@([left isEqual:right]),@NO);
    Check(checks,@"pointer:reverse",@([right isEqual:left]),@NO);
    Check(checks,@"pointer:identity",@([left isEqual:left]),@YES);
    Check(checks,@"pointer:set",@([NSSet setWithObjects:left,right,nil].count),@2);
    right.value = left.value;
    Check(checks,@"pointer:sameValueDistinctInstances",@([left isEqual:right]),@NO);
    ContractConstantHashPointer *c1 = [ContractConstantHashPointer new], *c2 = [ContractConstantHashPointer new];
    Check(checks,@"pointer:constantHash",@([c1 isEqual:c2]),@NO);
    ContractCString *s1 = [ContractCString new], *s2 = [ContractCString new];
    s1.value = "first"; s2.value = "second";
    Check(checks,@"cstring:distinct",@([s1 isEqual:s2]),@NO);
    ContractMixed *m1 = [ContractMixed new], *m2 = [ContractMixed new];
    m1.name = m2.name = @"same"; m1.value = (void *)1; m2.value = (void *)2;
    Check(checks,@"mixed:pointerStillIgnored",@([m1 isEqual:m2]),@YES);
    m2.name = @"different";
    Check(checks,@"mixed:valueStillCompared",@([m1 isEqual:m2]),@NO);

    // 2.3.1: non-finite floats keep the original per-value equality/hash contract
    // instead of merging into one nil via the JSON-export filter.
    ContractFloating *nan = [ContractFloating new]; nan.value = NAN;
    ContractFloating *pos = [ContractFloating new]; pos.value = INFINITY;
    ContractFloating *neg = [ContractFloating new]; neg.value = -INFINITY;
    ContractFloating *finite = [ContractFloating new]; finite.value = 7;
    ContractFloating *same = [ContractFloating new]; same.value = 7;
    Check(checks,@"nonfinite:nanVsInfinity",@([nan isEqual:pos]),@NO);
    Check(checks,@"nonfinite:infinities",@([pos isEqual:neg]),@NO);
    Check(checks,@"nonfinite:setCount",@([NSSet setWithArray:@[nan,pos,neg]].count),@3);
    Check(checks,@"nonfinite:finiteEqual",@([finite isEqual:same]),@YES);
    Check(checks,@"nonfinite:nanVsFinite",@([nan isEqual:finite]),@NO);
    // The JSON-export filter semantic is unchanged: a NaN property is omitted, not written.
    nan.value = NAN;
    Check(checks,@"nonfinite:jsonExportOmitsNaN",[nan yy_modelToJSONObject],@{});

    NSDictionary *input = @{@"name":@"normal",@"legacy":@"ancestor",@"other":@"tail",@"renamed":@"winner"};
    ContractMapperChild *plain = [ContractMapperChild yy_modelWithDictionary:input];
    Check(checks,@"mapper:default",plain.name,@"normal");
    Check(checks,@"mapper:defaultExport",[plain yy_modelToJSONObject],@{@"name":@"normal",@"other":@"tail"});
    ContractMapperMerged *merged = [ContractMapperMerged yy_modelWithJSON:@"{\"name\":\"normal\",\"legacy\":\"ancestor\",\"other\":\"tail\"}"];
    Check(checks,@"mapper:optIn",merged.name,@"ancestor");
    Check(checks,@"mapper:optInExport",[merged yy_modelToJSONObject],@{@"legacy":@"ancestor",@"other":@"tail"});
    Check(checks,@"mapper:disableInherited",[ContractMapperDisabled yy_modelWithDictionary:input].name,@"normal");
    Check(checks,@"mapper:childWins",[ContractMapperOverride yy_modelWithDictionary:input].name,@"winner");
    Check(checks,@"mapper:withoutProtocol",@([ContractMapperChild conformsToProtocol:@protocol(YYModel)]),@NO);
    Check(checks,@"protocol:NSObject",@([NSObject conformsToProtocol:@protocol(YYModel)]),@NO);
    Check(checks,@"protocol:explicit",@([ContractMapperMerged conformsToProtocol:@protocol(YYModel)]),@YES);

    NSDictionary *containerInput = @{@"members":@[@{@"name":@"one"},NSNull.null,@42],@"other":@[@{@"name":@"two"}]};
    ContractGenericChild *raw = [ContractGenericChild yy_modelWithDictionary:containerInput];
    Check(checks,@"generic:defaultCount",@(raw.members.count),@3);
    Check(checks,@"generic:defaultType",@([raw.members.firstObject isKindOfClass:NSDictionary.class]),@YES);
    Check(checks,@"generic:childType",@([raw.other.firstObject isKindOfClass:ContractItem.class]),@YES);
    ContractGenericMerged *typed = [ContractGenericMerged yy_modelWithDictionary:containerInput];
    Check(checks,@"generic:optInCount",@(typed.members.count),@1);
    Check(checks,@"generic:optInType",@([typed.members.firstObject isKindOfClass:ContractItem.class]),@YES);
    NSDictionary *listInput = @{@"name":@"N",@"tail":@"T"};
    Check(checks,@"blacklist:override",[[ContractBlackChild yy_modelWithDictionary:listInput] yy_modelToJSONObject],@{@"name":@"N"});
    Check(checks,@"whitelist:override",[[ContractWhiteChild yy_modelWithDictionary:listInput] yy_modelToJSONObject],@{@"tail":@"T"});

    YYClassPropertyInfo *info = [[YYClassPropertyInfo alloc] initWithProperty:class_getProperty(ContractDynamic.class,"name")];
    Check(checks,@"dynamic:flag",@((info.type & YYEncodingTypePropertyDynamic) != 0),@YES);
    // 2.3.0: the legacy isSwiftDynamic getter is fully removed from the ObjC product.
    Check(checks,@"dynamic:legacyRemoved",@([info respondsToSelector:NSSelectorFromString(@"isSwiftDynamic")]),@NO);
    ContractValue *number = [ContractValue yy_modelWithDictionary:@{@"identifier":[NSDecimalNumber decimalNumberWithString:@"18446744073709551615"]}];
    Check(checks,@"numeric:UInt64",[NSString stringWithFormat:@"%llu",number.identifier],@"18446744073709551615");
    ContractValue *date = [ContractValue yy_modelWithDictionary:@{@"date":@-1700000000000LL}];
    Check(checks,@"date:negativeMillis",date.date ? @(date.date.timeIntervalSince1970) : nil,@-1700000000);
    date = [ContractValue yy_modelWithDictionary:@{@"date":@"0000000000"}];
    Check(checks,@"date:zeroString",date.date ? @(date.date.timeIntervalSince1970) : nil,@0);
    date = [ContractValue yy_modelWithDictionary:@{@"date":@(INFINITY)}];
    Check(checks,@"date:nonfinite",@(date.date == nil),@YES);

    NSError *error = nil;
    ContractArchive *archive = [ContractArchive yy_modelWithDictionary:@{@"members":@[@{@"name":@"secure"}]}];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:archive requiringSecureCoding:YES error:&error];
    ContractArchive *decoded = data ? [NSKeyedUnarchiver unarchivedObjectOfClass:ContractArchive.class fromData:data error:&error] : nil;
    Check(checks,@"archive:secureContainer",[[decoded yy_modelToJSONObject] objectForKey:@"members"],@[@{@"name":@"secure"}]);
    Check(checks,@"archive:error",error.localizedDescription,nil);

    for (Class archiveClass in @[ContractGapArchive.class, ContractGapUndeclaredArchive.class]) {
        NSString *prefix = archiveClass == ContractGapArchive.class ? @"archive:declaredNonSecure" : @"archive:undeclaredNonSecure";
        ContractGapArchive *gap = [archiveClass new];
        gap.members = @[[ContractGapItem new], NSNull.null, @7, [ContractGapItem new]];
        ((ContractGapItem *)gap.members[0]).name = @"one";
        ((ContractGapItem *)gap.members[3]).name = @"two";
        NSData *gapData = [NSKeyedArchiver archivedDataWithRootObject:gap];
        ContractGapArchive *gapDecoded = [NSKeyedUnarchiver unarchiveObjectWithData:gapData];
        Check(checks,[prefix stringByAppendingString:@":count"],@(gapDecoded.members.count),@4);
        Check(checks,[prefix stringByAppendingString:@":null"],@(gapDecoded.members.count > 1 && [gapDecoded.members[1] isKindOfClass:NSNull.class]),@YES);
        Check(checks,[prefix stringByAppendingString:@":number"],gapDecoded.members.count > 2 ? gapDecoded.members[2] : nil,@7);
        BOOL models = gapDecoded.members.count == 4 &&
            [gapDecoded.members[0] isKindOfClass:ContractGapItem.class] &&
            [gapDecoded.members[3] isKindOfClass:ContractGapItem.class];
        Check(checks,[prefix stringByAppendingString:@":models"],@(models),@YES);
        Check(checks,[prefix stringByAppendingString:@":values"],models ? @[((ContractGapItem *)gapDecoded.members[0]).name, ((ContractGapItem *)gapDecoded.members[3]).name] : nil,@[@"one",@"two"]);
    }
    NSUInteger passed = 0;
    for (NSDictionary *check in checks.allValues) if ([check[@"passed"] boolValue]) passed++;
    NSDictionary *receipt = @{@"checks":checks,@"total":@(checks.count),@"passed":@(passed),@"allPassed":@(passed == checks.count)};
    NSData *result = [NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if (!result || ![result writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES]) return 2;
    return passed == checks.count ? 0 : 1;
} }
