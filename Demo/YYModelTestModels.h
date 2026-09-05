//
//  YYModelTestModels.h
//  YYModel Test Demo — Test model classes exercising all YYModel features.
//
//  Tests:
//  [T1] Basic property mapping (NSString, NSNumber, BOOL, int, double)
//  [T2] Nested object (Address contains Geo)
//  [T3] Array of strings (tags)
//  [T4] Array of nested objects (comments)
//  [T5] Key-path mapping (company.name → companyName)
//  [T6] Multi-key fallback (website → @[@"website", @"homepage", @"url"])
//  [T7] Blacklist / Whitelist
//  [T8] Custom transform (modelCustomTransformFromDictionary:)
//  [T9] NSDecimalNumber precision
//  [T10] NSCoding / NSSecureCoding round-trip
//  [T11] Model copy (yy_modelCopy)
//  [T12] Model hash / isEqual
//  [T13] Model → JSON → Model round-trip
//  [T14] Null / missing field handling
//  [T15] Date parsing (timestamp)
//

#import <Foundation/Foundation.h>
#import "YYModel.h"

// ============================================================
#pragma mark - Geo (nested object for T2)
// ============================================================

@interface Geo : NSObject
@property (nonatomic, copy) NSString *lat;
@property (nonatomic, copy) NSString *lng;
@end

// ============================================================
#pragma mark - Address (T2: nested object)
// ============================================================

@interface Address : NSObject
@property (nonatomic, copy) NSString *street;
@property (nonatomic, copy) NSString *suite;
@property (nonatomic, copy) NSString *city;
@property (nonatomic, copy) NSString *zipcode;
@property (nonatomic, strong) Geo *geo;
@end

// ============================================================
#pragma mark - Company (T5: key-path mapping target)
// ============================================================

@interface Company : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *catchPhrase;
@property (nonatomic, copy) NSString *bs;
@end

// ============================================================
#pragma mark - User (main model — exercises T1-T8, T10-T15)
// ============================================================

@interface User : NSObject <NSSecureCoding>

// T1: Basic types
@property (nonatomic, assign) NSInteger userId;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *username;
@property (nonatomic, copy)   NSString *email;
@property (nonatomic, copy)   NSString *phone;
@property (nonatomic, copy)   NSString *website;

// T2: Nested object
@property (nonatomic, strong) Address *address;
@property (nonatomic, strong) Company *company;

// T5: Key-path mapping (company.name → companyName)
@property (nonatomic, copy) NSString *companyName;

// T6: Multi-key fallback
@property (nonatomic, copy) NSString *homepage;

@end

// ============================================================
#pragma mark - Post (T4, T13: array model)
// ============================================================

@interface Post : NSObject
@property (nonatomic, assign) NSInteger postId;
@property (nonatomic, assign) NSInteger userId;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *body;
@end

// ============================================================
#pragma mark - YYComment (T4: nested array model)
// ============================================================

@interface YYComment : NSObject
@property (nonatomic, assign) NSInteger commentId;
@property (nonatomic, assign) NSInteger postId;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *email;
@property (nonatomic, copy)   NSString *body;
@end

// ============================================================
#pragma mark - Album / Photo (T3, T14)
// ============================================================

@interface Album : NSObject
@property (nonatomic, assign) NSInteger albumId;
@property (nonatomic, assign) NSInteger userId;
@property (nonatomic, copy)   NSString *title;
@end

@interface Photo : NSObject
@property (nonatomic, assign) NSInteger photoId;
@property (nonatomic, assign) NSInteger albumId;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *url;
@property (nonatomic, copy)   NSString *thumbnailUrl;
@end

// ============================================================
#pragma mark - Todo (T7, T14: blacklist/null test)
// ============================================================

@interface Todo : NSObject
@property (nonatomic, assign) NSInteger todoId;
@property (nonatomic, assign) NSInteger userId;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, assign) BOOL completed;

// T7: This property will be blacklisted
@property (nonatomic, copy) NSString *internalNote;
@end

// ============================================================
#pragma mark - PrecisionModel (T9: NSDecimalNumber)
// ============================================================

@interface PrecisionModel : NSObject
@property (nonatomic, strong) NSDecimalNumber *price;
@property (nonatomic, strong) NSDecimalNumber *rate;
@property (nonatomic, copy)   NSString *currency;
@end
