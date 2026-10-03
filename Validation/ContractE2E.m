#import <Foundation/Foundation.h>
#import "YYModel.h"
#import <dispatch/dispatch.h>
@interface LargeBox:NSObject
@property(nonatomic) unsigned long long identifier;
@end
@implementation LargeBox @end
@interface Checked:NSObject
@property(nonatomic,strong) NSString *name;
@end
@implementation Checked
- (BOOL)modelCustomTransformFromDictionary:(NSDictionary *)d { return ![self.name isEqualToString:@"bad"]; }
@end
@interface Parent:NSObject
@property(nonatomic,strong) Checked *child;
@property(nonatomic,strong) NSArray *children;
@end
@implementation Parent
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{@"children":[Checked class]}; }
@end
@interface StrictParent:Parent
@property(nonatomic,strong) NSDictionary *dictionary;
@property(nonatomic,strong) NSSet *set;
@end
@implementation StrictParent
+ (BOOL)modelRequiresSuccessfulNestedTransforms { return YES; }
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{@"dictionary":[Checked class],@"set":[Checked class]}; }
@end
@interface Outer:NSObject
@property(nonatomic,strong) Parent *branch;
@end
@implementation Outer
+ (BOOL)modelRequiresSuccessfulNestedTransforms { return YES; }
@end
@interface WillChecked:Checked @end
@implementation WillChecked
- (NSDictionary *)modelCustomWillTransformFromDictionary:(NSDictionary *)d { return nil; }
@end
@interface StrictWill:NSObject
@property(nonatomic,strong) WillChecked *child;
@end
@implementation StrictWill
+ (BOOL)modelRequiresSuccessfulNestedTransforms { return YES; }
@end
@interface ReentrantChecked:Checked @end
@implementation ReentrantChecked
- (BOOL)modelCustomTransformFromDictionary:(NSDictionary *)d {
    [Checked yy_modelWithDictionary:@{@"name":@"bad"}];
    return YES;
}
@end
@interface ReentrantParent:NSObject
@property(nonatomic,strong) ReentrantChecked *child;
@end
@implementation ReentrantParent
+ (BOOL)modelRequiresSuccessfulNestedTransforms { return YES; }
@end
int main(int argc,const char *argv[]) { @autoreleasepool {
 NSMutableDictionary *r=[NSMutableDictionary new];
 for (NSString *text in @[@"9223372036854775807",@"9223372036854775808",@"18446744073709551615"]) {
  NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:text];
  LargeBox *m=[LargeBox yy_modelWithDictionary:@{@"identifier":n}];
  NSString *j=[NSString stringWithFormat:@"{\"identifier\":%@.0}",text];
  LargeBox *fromJSON=[LargeBox yy_modelWithJSON:j];
  LargeBox *fromString=[LargeBox yy_modelWithDictionary:@{@"identifier":text}];
  r[text]=@{@"decimalInputClass":NSStringFromClass(n.class),@"decimalInput":n.stringValue,@"decimalActual":[NSString stringWithFormat:@"%llu",m.identifier],@"jsonInput":j,@"jsonActual":[NSString stringWithFormat:@"%llu",fromJSON.identifier],@"stringActual":[NSString stringWithFormat:@"%llu",fromString.identifier]};
 }
 NSDictionary *bad=@{@"name":@"bad"};Checked *root=[Checked yy_modelWithDictionary:bad];Parent *p=[Parent yy_modelWithDictionary:@{@"child":bad,@"children":@[bad]}];
 r[@"validation"]=@{@"rootRejected":@(root==nil),@"childPresent":@(p.child!=nil),@"childName":p.child.name ?: @"",@"childrenCount":@(p.children.count)};
 NSMutableDictionary *strict=[NSMutableDictionary new];
 strict[@"objectRejected"]=@([StrictParent yy_modelWithDictionary:@{@"child":bad}]==nil);
 strict[@"arrayRejected"]=@([StrictParent yy_modelWithDictionary:@{@"children":@[bad]}]==nil);
 strict[@"dictionaryRejected"]=@([StrictParent yy_modelWithDictionary:@{@"dictionary":@{@"key":bad}}]==nil);
 strict[@"setRejected"]=@([StrictParent yy_modelWithDictionary:@{@"set":@[bad]}]==nil);
 strict[@"deepRejected"]=@([Outer yy_modelWithDictionary:@{@"branch":@{@"children":@[bad]}}]==nil);
 strict[@"willRejected"]=@([StrictWill yy_modelWithDictionary:@{@"child":@{@"name":@"ok"}}]==nil);
 StrictParent *existing=[StrictParent new];existing.child=[Checked yy_modelWithDictionary:@{@"name":@"ok"}];
 strict[@"existingSetterFails"]=@(![existing yy_modelSetWithDictionary:@{@"child":bad}]);
 strict[@"validTreeSucceeds"]=@([StrictParent yy_modelWithDictionary:@{@"child":@{@"name":@"ok"},@"children":@[@{@"name":@"ok"}],@"dictionary":@{@"key":@{@"name":@"ok"}},@"set":@[@{@"name":@"ok"}]}]!=nil);
 strict[@"jsonRejected"]=@([StrictParent yy_modelWithJSON:@"{\"child\":{\"name\":\"bad\"}}"]==nil);
 strict[@"legacyUnchanged"]=@([Parent yy_modelWithDictionary:@{@"child":bad}].child!=nil);
 strict[@"reentrantUnrelatedFailureIgnored"]=@([ReentrantParent yy_modelWithDictionary:@{@"child":@{@"name":@"ok"}}]!=nil);
 NSMutableArray *parallel=[NSMutableArray new];
 dispatch_apply(32,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(size_t index){
  @autoreleasepool {
   BOOL ok=([StrictParent yy_modelWithDictionary:@{@"children":@[bad]}]==nil) && ([Parent yy_modelWithDictionary:@{@"children":@[bad]}].children.count==1);
   @synchronized(parallel){[parallel addObject:@(ok)];}
  }
 });
 strict[@"concurrentPoliciesIndependent"]=@(![parallel containsObject:@NO]);r[@"strict"]=strict;
 NSMutableDictionary *edges=[NSMutableDictionary new];
 for (NSString *text in @[@"0",@"1.9",@"18446744073709551615.9",@"-0.9",@"-1",@"18446744073709551616",@"NaN"]) {
  LargeBox *m=[LargeBox new];m.identifier=42;
  [m yy_modelSetWithDictionary:@{@"identifier":[NSDecimalNumber decimalNumberWithString:text]}];
  edges[text]=[NSString stringWithFormat:@"%llu",m.identifier];
 }
 r[@"unsignedEdges"]=edges;
 NSData *out=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];[out writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
}}
