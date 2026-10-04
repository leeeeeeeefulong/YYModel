#import <Foundation/Foundation.h>
#import "YYModel.h"
#include <math.h>
@interface ProbeBase : NSObject
@property(nonatomic,strong) NSString *name;
@property(nonatomic,strong) NSString *tail;
@end
@implementation ProbeBase
+ (NSDictionary *)modelCustomPropertyMapper { return @{ @"name":@"legacy" }; }
@end
@interface ProbeChild : ProbeBase @end
@implementation ProbeChild
+ (NSDictionary *)modelCustomPropertyMapper { return @{ @"tail":@"other" }; }
@end
@interface ArchiveMember:NSObject <NSSecureCoding>
@property(nonatomic,strong) NSString *name;
@end
@implementation ArchiveMember
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c { [self yy_modelEncodeWithCoder:c]; }
- (instancetype)initWithCoder:(NSCoder *)c { self=[super init]; return [self yy_modelInitWithCoder:c]; }
@end
@interface ArchiveRoot:NSObject <NSSecureCoding>
@property(nonatomic,strong) NSArray *array;
@property(nonatomic,strong) NSDictionary *dictionary;
@property(nonatomic,strong) NSSet *set;
@property(nonatomic,strong) id anything;
@property(nonatomic,strong) NSObject *object;
@end
@implementation ArchiveRoot
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c { [self yy_modelEncodeWithCoder:c]; }
- (instancetype)initWithCoder:(NSCoder *)c { self=[super init]; return [self yy_modelInitWithCoder:c]; }
@end
@interface DictionaryRoot:NSObject
@property(nonatomic,strong) NSDictionary *dictionary;
@property(nonatomic,strong) NSArray *array;
@property(nonatomic,strong) NSSet *set;
@end
@implementation DictionaryRoot
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{ @"dictionary":ArchiveMember.class, @"array":ArchiveMember.class, @"set":ArchiveMember.class }; }
@end
@interface GenericParent:NSObject
@property(nonatomic,strong) NSArray *members;
@property(nonatomic,strong) NSArray *other;
@end
@implementation GenericParent
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{ @"members":ArchiveMember.class }; }
@end
@interface GenericChild:GenericParent @end
@implementation GenericChild
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{ @"other":ArchiveMember.class }; }
@end
@interface BlackParent:ProbeBase @end
@implementation BlackParent
+ (NSArray *)modelPropertyBlacklist { return @[@"name"]; }
@end
@interface BlackChild:BlackParent @end
@implementation BlackChild
+ (NSArray *)modelPropertyBlacklist { return @[@"tail"]; }
@end
@interface WhiteParent:ProbeBase @end
@implementation WhiteParent
+ (NSArray *)modelPropertyWhitelist { return @[@"name"]; }
@end
@interface WhiteChild:WhiteParent @end
@implementation WhiteChild
+ (NSArray *)modelPropertyWhitelist { return @[@"tail"]; }
@end
@interface ArchiveTypedRoot:ArchiveRoot @end
@implementation ArchiveTypedRoot
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{ @"array":ArchiveMember.class,@"dictionary":ArchiveMember.class,@"set":ArchiveMember.class }; }
@end
@interface ObjCDynamic:NSObject
@property(nonatomic,strong) NSString *name;
@end
@implementation ObjCDynamic
@dynamic name;
- (NSString *)name { return @"pureObjectiveC"; }
- (void)setName:(NSString *)n {}
@end
@interface ParentEqual:NSObject
@property(nonatomic,strong) NSString *marker;
@end
@implementation ParentEqual
- (NSUInteger)hash { return [self yy_modelHash]; }
- (BOOL)isEqual:(id)x { return [self yy_modelIsEqual:x]; }
@end
@interface ChildEqual:ParentEqual
@property(nonatomic,strong) NSNumber *value;
@end
@implementation ChildEqual @end
@interface EqualRoot:NSObject
@property(nonatomic,strong) NSString *anchor;
@property SEL selector;
@property long double extended;
@end
@implementation EqualRoot
- (NSUInteger)hash { return [self yy_modelHash]; }
- (BOOL)isEqual:(id)x { return [self yy_modelIsEqual:x]; }
@end
@interface PointerOnly:NSObject
@property(nonatomic) void *value;
@end
@implementation PointerOnly
- (NSUInteger)hash { return [self yy_modelHash]; }
- (BOOL)isEqual:(id)x { return [self yy_modelIsEqual:x]; }
@end
@interface DateRoot:NSObject
@property(nonatomic,strong) NSDate *date;
@end
@implementation DateRoot @end
static id J(id x) { return x ?: NSNull.null; }
static id archiveResult(ArchiveRoot *model, BOOL secure) {
    NSMutableDictionary *result=[NSMutableDictionary new];
    @try {
        NSError *error=nil;
        NSData *data=[NSKeyedArchiver archivedDataWithRootObject:model requiringSecureCoding:secure error:&error];
        result[@"encodeError"]=J(error.localizedDescription);
        if (data) {
            ArchiveRoot *decoded=nil;
            if (secure) {
                decoded=[NSKeyedUnarchiver unarchivedObjectOfClass:ArchiveRoot.class fromData:data error:&error];
            } else {
                decoded=[NSKeyedUnarchiver unarchiveObjectWithData:data];
            }
            result[@"decodeError"]=J(error.localizedDescription);
            result[@"rootPresent"]=@(decoded!=nil);
            result[@"arrayCount"]=@(decoded.array.count);
            result[@"dictionaryCount"]=@(decoded.dictionary.count);
            result[@"setCount"]=@(decoded.set.count);
            result[@"anythingClass"]=decoded.anything ? NSStringFromClass([decoded.anything class]) : NSNull.null;
            result[@"objectClass"]=decoded.object ? NSStringFromClass(decoded.object.class) : NSNull.null;
        }
    } @catch(NSException *e) { result[@"exception"]=e.description; }
    return result;
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    NSMutableDictionary *r=[NSMutableDictionary new];
    ProbeChild *child=[ProbeChild yy_modelWithDictionary:@{ @"name":@"normal", @"legacy":@"ancestor", @"other":@"tail" }];
    r[@"mapperOverride"]=@{ @"name":J(child.name), @"tail":J(child.tail), @"json":J([child yy_modelToJSONObject]) };
    GenericChild *generic=[GenericChild yy_modelWithDictionary:@{@"members":@[@{@"name":@"one"},NSNull.null,@42]}];
    r[@"genericOverride"]=@{@"count":@(generic.members.count),@"firstClass":generic.members.count ? NSStringFromClass([generic.members[0] class]) : NSNull.null,@"json":J([generic yy_modelToJSONObject])};
    NSDictionary *listInput=@{@"name":@"normal",@"legacy":@"ancestor",@"tail":@"tail"};
    r[@"blacklistOverride"]=J([[BlackChild yy_modelWithDictionary:listInput] yy_modelToJSONObject]);
    r[@"whitelistOverride"]=J([[WhiteChild yy_modelWithDictionary:listInput] yy_modelToJSONObject]);
    YYClassPropertyInfo *info=[[YYClassPropertyInfo alloc] initWithProperty:class_getProperty(ObjCDynamic.class,"name")];
    if ([info respondsToSelector:NSSelectorFromString(@"isSwiftDynamic")]) r[@"pureObjCDynamicMarkedSwift"]=[info valueForKey:@"isSwiftDynamic"];
    ParentEqual *parent=[ParentEqual new];ChildEqual *descendant=[ChildEqual new];parent.marker=descendant.marker=@"same";
    r[@"ancestorEquality"]=@{@"parentToChild":@([parent isEqual:descendant]),@"childToParent":@([descendant isEqual:parent])};
    ArchiveMember *member=[ArchiveMember yy_modelWithDictionary:@{@"name":@"child"}];
    ArchiveRoot *root=[ArchiveRoot new];root.array=@[member];root.dictionary=@{@"key":member};root.set=[NSSet setWithObject:member];root.anything=member;root.object=member;
    r[@"legacyArchive"]=archiveResult(root,NO);
    r[@"secureArchive"]=archiveResult(root,YES);
    NSMutableDictionary *separate=[NSMutableDictionary new];
    for(NSString *field in @[@"array",@"dictionary",@"set",@"anything",@"object"]) {
        ArchiveRoot *single=[ArchiveRoot new];[single setValue:[root valueForKey:field] forKey:field];separate[field]=archiveResult(single,YES);
    }
    r[@"secureSeparateFields"]=separate;
    NSMutableDictionary *typed=[NSMutableDictionary new];
    for(NSString *field in @[@"array",@"dictionary",@"set"]) {
        ArchiveTypedRoot *single=[ArchiveTypedRoot new];[single setValue:[root valueForKey:field] forKey:field];typed[field]=archiveResult(single,YES);
    }
    r[@"secureTypedContainers"]=typed;

    DictionaryRoot *containers=[DictionaryRoot yy_modelWithDictionary:@{@"dictionary":@{@"key":member},@"array":@[member],@"set":@[member]}];
    r[@"existingContainers"]=@{ @"dictionaryCount":@(containers.dictionary.count), @"arrayCount":@(containers.array.count), @"setCount":@(containers.set.count) };
    EqualRoot *a=[EqualRoot new], *b=[EqualRoot new];a.anchor=b.anchor=@"same";a.selector=@selector(description);b.selector=@selector(hash);r[@"selectorDifferentEquals"]=@([a isEqual:b]);
    a.selector=b.selector;a.extended=1.0L;b.extended=2.0L;r[@"longDoubleDifferentEquals"]=@([a isEqual:b]);
    PointerOnly *pa=[PointerOnly new],*pb=[PointerOnly new];pa.value=(void *)1;pb.value=(void *)2;
    r[@"differentPointers"]=@{@"equal":@([pa isEqual:pb]),@"hashEqual":@(pa.hash==pb.hash),@"distinctObjects":@(pa!=pb)};
    NSMutableDictionary *dates=[NSMutableDictionary new];
    for(id input in @[@0,@"0000000000",@"01/02/2023",@"02/01/2023",@"1700000000",@"1000000000000",@1000000000000LL,@"1e3",@"2023-11-14T22:13:20Z"]) {
        DateRoot *date=[DateRoot yy_modelWithDictionary:@{@"date":input}];
        dates[[NSString stringWithFormat:@"%@:%@",NSStringFromClass([input class]),input]]= date.date && isfinite(date.date.timeIntervalSince1970) ? @(date.date.timeIntervalSince1970) : NSNull.null;
    }
    r[@"dates"]=dates;
    r[@"NSObjectConformsYYModel"]=@([NSObject conformsToProtocol:@protocol(YYModel)]);
    NSUInteger size=0;NSGetSizeAndAlignment("l",&size,NULL);r[@"encodingL"]=@{@"FoundationSize":@(size),@"YYType":@(YYEncodingGetType("l")),@"longEncode":[NSString stringWithUTF8String:@encode(long)]};
    NSData *data=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
    return data && [data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 2;
} }
