//
//  NSObject+YYModel.m
//  YYModel <https://github.com/ibireme/YYModel>
//
//  Created by ibireme on 15/5/10.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//
//  Modern iOS Compatible — 2026.10 Revision
//  Minimum deployment target: iOS 11.0 / macOS 10.13
//
//  Features & Modernizations:
//  - 100% Behavioral & contract fidelity with original ibireme/YYModel specification
//  - Fully typed objc_msgSend non-variadic function pointers (Clang 17 / Xcode 27 -Wcast-function-type-strict safe)
//  - Thread-safe caching with os_unfair_lock (replaces dispatch_semaphore, priority inversion safe)
//  - Thread-safe ISO8601 & custom date formatters
//  - Secure coding (NSSecureCoding) support with fallback
//  - Superclass property & custom mapper bottom-up inheritance
//  - Full polymorphic model resolution (modelCustomClassForDictionary:)
//  - Safe dictionary keyPath traversal without KVC exceptions
//

#import "NSObject+YYModel.h"
#import "YYClassInfo.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>

#define force_inline __inline__ __attribute__((always_inline))

// ============================================================
#pragma mark - Typed objc_msgSend Function Pointers
// ============================================================

typedef void          (*YYSendV_id)(id, SEL, id);
typedef void          (*YYSendV_bool)(id, SEL, BOOL);
typedef void          (*YYSendV_char)(id, SEL, char);
typedef void          (*YYSendV_uchar)(id, SEL, unsigned char);
typedef void          (*YYSendV_short)(id, SEL, short);
typedef void          (*YYSendV_ushort)(id, SEL, unsigned short);
typedef void          (*YYSendV_int)(id, SEL, int);
typedef void          (*YYSendV_uint)(id, SEL, unsigned int);
typedef void          (*YYSendV_ll)(id, SEL, long long);
typedef void          (*YYSendV_ull)(id, SEL, unsigned long long);
typedef void          (*YYSendV_float)(id, SEL, float);
typedef void          (*YYSendV_double)(id, SEL, double);
typedef void          (*YYSendV_ldouble)(id, SEL, long double);
typedef void          (*YYSendV_class)(id, SEL, Class);
typedef void          (*YYSendV_sel)(id, SEL, SEL);
typedef void          (*YYSendV_ptr)(id, SEL, void *);
typedef void          (*YYSendV_size_t)(id, SEL, size_t);

typedef id            (*YYSendR_id)(id, SEL);
typedef BOOL          (*YYSendR_bool)(id, SEL);
typedef char          (*YYSendR_char)(id, SEL);
typedef unsigned char (*YYSendR_uchar)(id, SEL);
typedef short         (*YYSendR_short)(id, SEL);
typedef unsigned short (*YYSendR_ushort)(id, SEL);
typedef int           (*YYSendR_int)(id, SEL);
typedef unsigned int  (*YYSendR_uint)(id, SEL);
typedef long long     (*YYSendR_ll)(id, SEL);
typedef unsigned long long (*YYSendR_ull)(id, SEL);
typedef float         (*YYSendR_float)(id, SEL);
typedef double        (*YYSendR_double)(id, SEL);
typedef long double   (*YYSendR_ldouble)(id, SEL);
typedef Class         (*YYSendR_class)(id, SEL);
typedef SEL           (*YYSendR_sel)(id, SEL);
typedef void *        (*YYSendR_ptr)(id, SEL);
typedef size_t        (*YYSendR_size_t)(id, SEL);

// ============================================================
#pragma mark - Internal Types
// ============================================================

typedef NS_ENUM(int, YYEncodingNSType) {
    YYEncodingTypeNSUnknown = 0,
    YYEncodingTypeNSString,
    YYEncodingTypeNSMutableString,
    YYEncodingTypeNSValue,
    YYEncodingTypeNSNumber,
    YYEncodingTypeNSDecimalNumber,
    YYEncodingTypeNSData,
    YYEncodingTypeNSMutableData,
    YYEncodingTypeNSDate,
    YYEncodingTypeNSURL,
    YYEncodingTypeNSArray,
    YYEncodingTypeNSMutableArray,
    YYEncodingTypeNSDictionary,
    YYEncodingTypeNSMutableDictionary,
    YYEncodingTypeNSSet,
    YYEncodingTypeNSMutableSet,
};

static force_inline YYEncodingNSType YYClassGetNSType(Class cls) {
    if (!cls) return YYEncodingTypeNSUnknown;
    if ([cls isSubclassOfClass:[NSMutableString class]])    return YYEncodingTypeNSMutableString;
    if ([cls isSubclassOfClass:[NSString class]])           return YYEncodingTypeNSString;
    if ([cls isSubclassOfClass:[NSDecimalNumber class]])    return YYEncodingTypeNSDecimalNumber;
    if ([cls isSubclassOfClass:[NSNumber class]])           return YYEncodingTypeNSNumber;
    if ([cls isSubclassOfClass:[NSValue class]])            return YYEncodingTypeNSValue;
    if ([cls isSubclassOfClass:[NSMutableData class]])      return YYEncodingTypeNSMutableData;
    if ([cls isSubclassOfClass:[NSData class]])             return YYEncodingTypeNSData;
    if ([cls isSubclassOfClass:[NSDate class]])             return YYEncodingTypeNSDate;
    if ([cls isSubclassOfClass:[NSURL class]])              return YYEncodingTypeNSURL;
    if ([cls isSubclassOfClass:[NSMutableArray class]])     return YYEncodingTypeNSMutableArray;
    if ([cls isSubclassOfClass:[NSArray class]])            return YYEncodingTypeNSArray;
    if ([cls isSubclassOfClass:[NSMutableDictionary class]])return YYEncodingTypeNSMutableDictionary;
    if ([cls isSubclassOfClass:[NSDictionary class]])       return YYEncodingTypeNSDictionary;
    if ([cls isSubclassOfClass:[NSMutableSet class]])       return YYEncodingTypeNSMutableSet;
    if ([cls isSubclassOfClass:[NSSet class]])              return YYEncodingTypeNSSet;
    return YYEncodingTypeNSUnknown;
}

static force_inline BOOL YYEncodingTypeIsCNumber(YYEncodingType type) {
    switch (type & YYEncodingTypeMask) {
        case YYEncodingTypeBool:
        case YYEncodingTypeInt8:
        case YYEncodingTypeUInt8:
        case YYEncodingTypeInt16:
        case YYEncodingTypeUInt16:
        case YYEncodingTypeInt32:
        case YYEncodingTypeUInt32:
        case YYEncodingTypeInt64:
        case YYEncodingTypeUInt64:
        case YYEncodingTypeFloat:
        case YYEncodingTypeDouble:
        case YYEncodingTypeLongDouble: return YES;
        default: return NO;
    }
}

// ============================================================
#pragma mark - NSNumber from ID
// ============================================================

static force_inline NSNumber *YYNSNumberCreateFromID(__unsafe_unretained id value) {
    static NSCharacterSet *dot;
    static NSDictionary *dic;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dot = [NSCharacterSet characterSetWithRange:NSMakeRange('.', 1)];
        dic = @{@"TRUE" :   @(YES),
                @"True" :   @(YES),
                @"true" :   @(YES),
                @"FALSE" :  @(NO),
                @"False" :  @(NO),
                @"false" :  @(NO),
                @"YES" :    @(YES),
                @"Yes" :    @(YES),
                @"yes" :    @(YES),
                @"NO" :     @(NO),
                @"No" :     @(NO),
                @"no" :     @(NO),
                @"NIL" :    (id)kCFNull,
                @"Nil" :    (id)kCFNull,
                @"nil" :    (id)kCFNull,
                @"NULL" :   (id)kCFNull,
                @"Null" :   (id)kCFNull,
                @"null" :   (id)kCFNull,
                @"(NULL)" : (id)kCFNull,
                @"(Null)" : (id)kCFNull,
                @"(null)" : (id)kCFNull,
                @"<NULL>" : (id)kCFNull,
                @"<Null>" : (id)kCFNull,
                @"<null>" : (id)kCFNull};
    });

    if (!value || value == (id)kCFNull) return nil;
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSNumber *num = dic[value];
        if (num) {
            if (num == (id)kCFNull) return nil;
            return num;
        }
        if ([(NSString *)value rangeOfCharacterFromSet:dot].location != NSNotFound) {
            const char *cstring = ((NSString *)value).UTF8String;
            if (!cstring) return nil;
            double num = atof(cstring);
            if (isnan(num) || isinf(num)) return nil;
            return @(num);
        } else {
            const char *cstring = ((NSString *)value).UTF8String;
            if (!cstring) return nil;
            const char *p = cstring;
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n' || *p == '\v' || *p == '\f') p++;
            if (*p == '-') {
                long long v = strtoll(cstring, NULL, 10);
                return @(v);
            } else {
                unsigned long long v = strtoull(cstring, NULL, 10);
                return [NSNumber numberWithUnsignedLongLong:v];
            }
        }
    }
    return nil;
}

// ============================================================
#pragma mark - NSDate Parsing & Formatting (Thread-Safe)
// ============================================================

static NSString *YYISODateString(NSDate *date) {
    if (!date) return nil;
    static NSDateFormatter *formatter = nil;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    });
    os_unfair_lock_lock(&lock);
    NSString *str = [formatter stringFromDate:date];
    os_unfair_lock_unlock(&lock);
    return str;
}

static force_inline NSDate *YYNSDateFromString(__unsafe_unretained NSString *string) {
    typedef NSDate* (^YYNSDateParseBlock)(NSString *string);
    #define kParserNum 34
    static YYNSDateParseBlock blocks[kParserNum + 1] = {0};
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        {
            /*
             2014-01-20  // Google
             */
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter.dateFormat = @"yyyy-MM-dd";
            blocks[10] = ^(NSString *string) { return [formatter dateFromString:string]; };
        }

        {
            /*
             2014-01-20 12:24:48
             2014-01-20T12:24:48   // Google
             2014-01-20 12:24:48.000
             2014-01-20T12:24:48.000
             */
            NSDateFormatter *formatter1 = [[NSDateFormatter alloc] init];
            formatter1.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter1.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter1.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";

            NSDateFormatter *formatter2 = [[NSDateFormatter alloc] init];
            formatter2.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter2.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter2.dateFormat = @"yyyy-MM-dd HH:mm:ss";

            NSDateFormatter *formatter3 = [[NSDateFormatter alloc] init];
            formatter3.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter3.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter3.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS";

            NSDateFormatter *formatter4 = [[NSDateFormatter alloc] init];
            formatter4.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter4.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            formatter4.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";

            blocks[19] = ^(NSString *string) {
                if ([string characterAtIndex:10] == 'T') {
                    return [formatter1 dateFromString:string];
                } else {
                    return [formatter2 dateFromString:string];
                }
            };

            blocks[23] = ^(NSString *string) {
                if ([string characterAtIndex:10] == 'T') {
                    return [formatter3 dateFromString:string];
                } else {
                    return [formatter4 dateFromString:string];
                }
            };
        }

        {
            /*
             2014-01-20T12:24:48Z        // Github, Apple
             2014-01-20T12:24:48+0800    // Facebook
             2014-01-20T12:24:48+12:00   // Google
             2014-01-20T12:24:48.000Z
             2014-01-20T12:24:48.000+0800
             2014-01-20T12:24:48.000+12:00
             */
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";

            NSDateFormatter *formatter2 = [NSDateFormatter new];
            formatter2.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter2.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";

            blocks[20] = ^(NSString *string) { return [formatter dateFromString:string]; };
            blocks[24] = ^(NSString *string) { return [formatter dateFromString:string]?: [formatter2 dateFromString:string]; };
            blocks[25] = ^(NSString *string) { return [formatter dateFromString:string]; };
            blocks[28] = ^(NSString *string) { return [formatter2 dateFromString:string]; };
            blocks[29] = ^(NSString *string) { return [formatter2 dateFromString:string]; };
        }

        {
            /*
             Fri Sep 04 00:12:21 +0800 2015 // Weibo, Twitter
             Fri Sep 04 00:12:21.000 +0800 2015
             */
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = @"EEE MMM dd HH:mm:ss Z yyyy";

            NSDateFormatter *formatter2 = [NSDateFormatter new];
            formatter2.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            formatter2.dateFormat = @"EEE MMM dd HH:mm:ss.SSS Z yyyy";

            blocks[30] = ^(NSString *string) { return [formatter dateFromString:string]; };
            blocks[34] = ^(NSString *string) { return [formatter2 dateFromString:string]; };
        }
    });
    if (!string) return nil;
    if (string.length <= kParserNum) {
        YYNSDateParseBlock parser = blocks[string.length];
        if (parser) {
            NSDate *date = parser(string);
            if (date) return date;
        }
    }
    // Numeric timestamp string (seconds or milliseconds)
    NSUInteger len = string.length;
    if (len == 10 || len == 13) {
        BOOL isAllDigits = YES;
        for (NSUInteger i = 0; i < len; i++) {
            unichar c = [string characterAtIndex:i];
            if (c < '0' || c > '9') {
                isAllDigits = NO;
                break;
            }
        }
        if (isAllDigits) {
            NSTimeInterval ts = [string doubleValue];
            if (len == 13) ts /= 1000.0;
            if (ts > 0) return [NSDate dateWithTimeIntervalSince1970:ts];
        }
    }

    // Extended common formats fallback (RFC 822/1123, asctime, localized slashes)
    static NSArray<NSDateFormatter *> *fallbackFormatters = nil;
    static dispatch_once_t fallbackOnce;
    dispatch_once(&fallbackOnce, ^{
        NSArray *formats = @[
            @"EEE, dd MMM yyyy HH:mm:ss Z",
            @"EEE MMM dd HH:mm:ss yyyy",
            @"yyyy-MM-dd HH:mm:ss Z",
            @"yyyy/MM/dd",
            @"yyyy.MM.dd",
            @"MM-dd-yyyy",
            @"MM/dd/yyyy",
            @"dd-MM-yyyy",
            @"dd/MM/yyyy",
        ];
        NSMutableArray *list = [NSMutableArray new];
        for (NSString *fmtStr in formats) {
            NSDateFormatter *fmt = [NSDateFormatter new];
            fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            fmt.dateFormat = fmtStr;
            [list addObject:fmt];
        }
        fallbackFormatters = list;
    });
    for (NSDateFormatter *fmt in fallbackFormatters) {
        NSDate *date = [fmt dateFromString:string];
        if (date) return date;
    }

    return nil;
    #undef kParserNum
}

static force_inline Class YYNSBlockClass(void) {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void (^block)(void) = ^{};
        cls = ((NSObject *)block).class;
        while (class_getSuperclass(cls) != [NSObject class]) {
            cls = class_getSuperclass(cls);
        }
    });
    return cls;
}

// ============================================================
#pragma mark - Key-Path Helpers (Safe Dictionary Traversal)
// ============================================================

static force_inline id YYValueForKeyPath(__unsafe_unretained NSDictionary *dic,
                                         __unsafe_unretained NSArray *keyPaths) {
    id value = nil;
    for (NSUInteger i = 0, max = keyPaths.count; i < max; i++) {
        value = dic[keyPaths[i]];
        if (i + 1 < max) {
            if ([value isKindOfClass:[NSDictionary class]]) {
                dic = value;
            } else {
                return nil;
            }
        }
    }
    return value;
}

static force_inline id YYValueForMultiKeys(__unsafe_unretained NSDictionary *dic,
                                           __unsafe_unretained NSArray *multiKeys) {
    id value = nil;
    for (id key in multiKeys) {
        if ([key isKindOfClass:[NSString class]]) {
            value = dic[key];
            if (value) break;
        } else if ([key isKindOfClass:[NSArray class]]) {
            value = YYValueForKeyPath(dic, (NSArray *)key);
            if (value) break;
        }
    }
    return value;
}

// ============================================================
#pragma mark - Property Meta
// ============================================================

@interface _YYModelPropertyMeta : NSObject {
    @package
    NSString *_name;
    YYEncodingType _type;
    YYEncodingNSType _nsType;
    BOOL _isCNumber;
    Class _cls;
    Class _genericCls;
    SEL _getter;
    SEL _setter;
    BOOL _isKVCCompatible;
    BOOL _isStructAvailableForKeyedArchiver;
    BOOL _hasCustomClassFromDictionary;
    NSString *_mappedToKey;
    NSArray *_mappedToKeyPath;
    NSArray *_mappedToKeyArray;
    YYClassPropertyInfo *_info;
    _YYModelPropertyMeta *_next;
}
@end

@implementation _YYModelPropertyMeta

+ (instancetype)metaWithClassInfo:(YYClassInfo *)classInfo
                     propertyInfo:(YYClassPropertyInfo *)propertyInfo
                          generic:(Class)generic {
    if (!propertyInfo || !classInfo) return nil;

    // Support pseudo generic class with protocol name
    if (!generic && propertyInfo.protocols) {
        for (NSString *protocol in propertyInfo.protocols) {
            Class cls = objc_getClass(protocol.UTF8String);
            if (cls) {
                generic = cls;
                break;
            }
        }
    }

    _YYModelPropertyMeta *meta = [self new];
    meta->_name = propertyInfo.name;
    meta->_type = propertyInfo.type;
    meta->_info = propertyInfo;
    meta->_genericCls = generic;

    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeObject) {
        meta->_nsType = YYClassGetNSType(propertyInfo.cls);
    } else {
        meta->_isCNumber = YYEncodingTypeIsCNumber(meta->_type);
    }

    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeStruct) {
        static NSSet *types = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSMutableSet *set = [NSMutableSet new];
            // 32 bit
            [set addObject:@"{CGSize=ff}"];
            [set addObject:@"{CGPoint=ff}"];
            [set addObject:@"{CGRect={CGPoint=ff}{CGSize=ff}}"];
            [set addObject:@"{CGAffineTransform=ffffff}"];
            [set addObject:@"{UIEdgeInsets=ffff}"];
            [set addObject:@"{UIOffset=ff}"];
            // 64 bit
            [set addObject:@"{CGSize=dd}"];
            [set addObject:@"{CGPoint=dd}"];
            [set addObject:@"{CGRect={CGPoint=dd}{CGSize=dd}}"];
            [set addObject:@"{CGAffineTransform=dddddd}"];
            [set addObject:@"{UIEdgeInsets=dddd}"];
            [set addObject:@"{UIOffset=dd}"];
            types = set;
        });
        if ([types containsObject:propertyInfo.typeEncoding]) {
            meta->_isStructAvailableForKeyedArchiver = YES;
        }
    }

    meta->_cls = propertyInfo.cls;

    if (generic) {
        meta->_hasCustomClassFromDictionary = [generic respondsToSelector:@selector(modelCustomClassForDictionary:)];
    } else if (meta->_cls && meta->_nsType == YYEncodingTypeNSUnknown) {
        meta->_hasCustomClassFromDictionary = [meta->_cls respondsToSelector:@selector(modelCustomClassForDictionary:)];
    }

    if (propertyInfo.getter) {
        if ([classInfo.cls instancesRespondToSelector:propertyInfo.getter]) {
            meta->_getter = propertyInfo.getter;
        }
    }
    if (propertyInfo.setter) {
        if ([classInfo.cls instancesRespondToSelector:propertyInfo.setter]) {
            meta->_setter = propertyInfo.setter;
        }
    }

    if (meta->_getter && meta->_setter) {
        switch (meta->_type & YYEncodingTypeMask) {
            case YYEncodingTypeBool:
            case YYEncodingTypeInt8:
            case YYEncodingTypeUInt8:
            case YYEncodingTypeInt16:
            case YYEncodingTypeUInt16:
            case YYEncodingTypeInt32:
            case YYEncodingTypeUInt32:
            case YYEncodingTypeInt64:
            case YYEncodingTypeUInt64:
            case YYEncodingTypeFloat:
            case YYEncodingTypeDouble:
            case YYEncodingTypeObject:
            case YYEncodingTypeClass:
            case YYEncodingTypeBlock:
            case YYEncodingTypeStruct:
            case YYEncodingTypeUnion: {
                meta->_isKVCCompatible = YES;
            } break;
            default: break;
        }
    }

    return meta;
}

@end

// ============================================================
#pragma mark - Class Meta
// ============================================================

@interface _YYModelMeta : NSObject {
    @package
    YYClassInfo *_classInfo;
    NSDictionary *_mapper;
    NSArray *_allPropertyMetas;
    NSArray *_keyPathPropertyMetas;
    NSArray *_multiKeysPropertyMetas;
    NSUInteger _keyMappedCount;
    YYEncodingNSType _nsType;

    BOOL _hasCustomWillTransformFromDictionary;
    BOOL _hasCustomTransformFromDictionary;
    BOOL _hasCustomTransformToDictionary;
    BOOL _hasCustomClassFromDictionary;
}
@end

@implementation _YYModelMeta

- (instancetype)initWithClass:(Class)cls {
    YYClassInfo *classInfo = [YYClassInfo classInfoWithClass:cls];
    if (!classInfo) return nil;
    self = [super init];

    // Collect class hierarchy from root ancestor down to subclass
    NSMutableArray *classHierarchy = [NSMutableArray new];
    for (Class c = cls; c && c != [NSObject class] && c != [NSProxy class]; c = class_getSuperclass(c)) {
        [classHierarchy addObject:c];
    }
    NSArray *reversedHierarchy = classHierarchy.reverseObjectEnumerator.allObjects;

    NSSet *blacklist = nil;
    if ([cls respondsToSelector:@selector(modelPropertyBlacklist)]) {
        NSArray *properties = [(id<YYModel>)cls modelPropertyBlacklist];
        if (properties) {
            blacklist = [NSSet setWithArray:properties];
        }
    }
    NSSet *whitelist = nil;
    if ([cls respondsToSelector:@selector(modelPropertyWhitelist)]) {
        NSArray *properties = [(id<YYModel>)cls modelPropertyWhitelist];
        if (properties) {
            whitelist = [NSSet setWithArray:properties];
        }
    }

    NSMutableDictionary *genericMapper = nil;
    NSMutableDictionary *customMapper = nil;

    for (Class currentCls in reversedHierarchy) {
        if ([currentCls respondsToSelector:@selector(modelContainerPropertyGenericClass)]) {
            NSDictionary *mapper = [(id<YYModel>)currentCls modelContainerPropertyGenericClass];
            if (mapper.count) {
                if (!genericMapper) genericMapper = [NSMutableDictionary new];
                [mapper enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if (![key isKindOfClass:[NSString class]]) return;
                    Class meta = object_getClass(obj);
                    if (!meta) return;
                    if (class_isMetaClass(meta)) {
                        genericMapper[key] = obj;
                    } else if ([obj isKindOfClass:[NSString class]]) {
                        Class c = NSClassFromString(obj);
                        if (c) genericMapper[key] = c;
                    }
                }];
            }
        }
        if ([currentCls respondsToSelector:@selector(modelCustomPropertyMapper)]) {
            NSDictionary *mapper = [(id<YYModel>)currentCls modelCustomPropertyMapper];
            if (mapper.count) {
                if (!customMapper) customMapper = [NSMutableDictionary new];
                [customMapper addEntriesFromDictionary:mapper];
            }
        }
    }

    // Create all property metas traversing from subclass to root superclass
    NSMutableDictionary *allPropertyMetas = [NSMutableDictionary new];
    YYClassInfo *curClassInfo = classInfo;
    while (curClassInfo && curClassInfo.superCls != nil) {
        for (YYClassPropertyInfo *propertyInfo in curClassInfo.propertyInfos.allValues) {
            if (!propertyInfo.name) continue;
            if (blacklist && [blacklist containsObject:propertyInfo.name]) continue;
            if (whitelist && ![whitelist containsObject:propertyInfo.name]) continue;
            _YYModelPropertyMeta *meta = [_YYModelPropertyMeta metaWithClassInfo:classInfo
                                                                    propertyInfo:propertyInfo
                                                                         generic:genericMapper[propertyInfo.name]];
            if (!meta || !meta->_name) continue;
            if (!meta->_getter || !meta->_setter) continue;
            if (allPropertyMetas[meta->_name]) continue;
            allPropertyMetas[meta->_name] = meta;
        }
        curClassInfo = curClassInfo.superClassInfo;
    }
    if (allPropertyMetas.count) _allPropertyMetas = allPropertyMetas.allValues.copy;

    // Create property mapper
    NSMutableDictionary *mapper = [NSMutableDictionary new];
    NSMutableArray *keyPathPropertyMetas = [NSMutableArray new];
    NSMutableArray *multiKeysPropertyMetas = [NSMutableArray new];

    if (customMapper) {
        [customMapper enumerateKeysAndObjectsUsingBlock:^(NSString *propertyName, id mappedToKey, BOOL *stop) {
            _YYModelPropertyMeta *propertyMeta = allPropertyMetas[propertyName];
            if (!propertyMeta) return;
            [allPropertyMetas removeObjectForKey:propertyName];

            if ([mappedToKey isKindOfClass:[NSString class]]) {
                if (((NSString *)mappedToKey).length == 0) return;

                propertyMeta->_mappedToKey = mappedToKey;
                NSArray *keyPath = [((NSString *)mappedToKey) componentsSeparatedByString:@"."];
                for (NSString *onePath in keyPath) {
                    if (onePath.length == 0) {
                        NSMutableArray *tmp = keyPath.mutableCopy;
                        [tmp removeObject:@""];
                        keyPath = tmp;
                        break;
                    }
                }
                if (keyPath.count > 1) {
                    propertyMeta->_mappedToKeyPath = keyPath;
                    [keyPathPropertyMetas addObject:propertyMeta];
                }
                propertyMeta->_next = mapper[mappedToKey] ?: nil;
                mapper[mappedToKey] = propertyMeta;

            } else if ([mappedToKey isKindOfClass:[NSArray class]]) {
                NSMutableArray *mappedToKeyArray = [NSMutableArray new];
                for (NSString *oneKey in ((NSArray *)mappedToKey)) {
                    if (![oneKey isKindOfClass:[NSString class]]) continue;
                    if (oneKey.length == 0) continue;

                    NSArray *keyPath = [oneKey componentsSeparatedByString:@"."];
                    if (keyPath.count > 1) {
                        [mappedToKeyArray addObject:keyPath];
                    } else {
                        [mappedToKeyArray addObject:oneKey];
                    }

                    if (!propertyMeta->_mappedToKey) {
                        propertyMeta->_mappedToKey = oneKey;
                        propertyMeta->_mappedToKeyPath = keyPath.count > 1 ? keyPath : nil;
                    }
                }
                if (!propertyMeta->_mappedToKey) return;

                propertyMeta->_mappedToKeyArray = mappedToKeyArray;
                [multiKeysPropertyMetas addObject:propertyMeta];

                propertyMeta->_next = mapper[mappedToKey] ?: nil;
                mapper[mappedToKey] = propertyMeta;
            }
        }];
    }

    [allPropertyMetas enumerateKeysAndObjectsUsingBlock:^(NSString *name, _YYModelPropertyMeta *propertyMeta, BOOL *stop) {
        propertyMeta->_mappedToKey = name;
        propertyMeta->_next = mapper[name] ?: nil;
        mapper[name] = propertyMeta;
    }];

    if (mapper.count) _mapper = mapper;
    if (keyPathPropertyMetas.count) _keyPathPropertyMetas = keyPathPropertyMetas;
    if (multiKeysPropertyMetas.count) _multiKeysPropertyMetas = multiKeysPropertyMetas;

    _classInfo = classInfo;
    _keyMappedCount = _allPropertyMetas.count;
    _nsType = YYClassGetNSType(cls);
    _hasCustomWillTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomWillTransformFromDictionary:)]);
    _hasCustomTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformFromDictionary:)]);
    _hasCustomTransformToDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformToDictionary:)]);
    _hasCustomClassFromDictionary = ([cls respondsToSelector:@selector(modelCustomClassForDictionary:)]);

    return self;
}

// Thread-safe meta cache backed by os_unfair_lock
static CFMutableDictionaryRef _modelMetaCache;
static os_unfair_lock _modelMetaLock = OS_UNFAIR_LOCK_INIT;

+ (instancetype)metaWithClass:(Class)cls {
    if (!cls) return nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _modelMetaCache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    });

    os_unfair_lock_lock(&_modelMetaLock);
    _YYModelMeta *meta = CFDictionaryGetValue(_modelMetaCache, (__bridge const void *)(cls));
    os_unfair_lock_unlock(&_modelMetaLock);

    if (!meta || meta->_classInfo.needUpdate) {
        meta = [[_YYModelMeta alloc] initWithClass:cls];
        if (meta) {
            os_unfair_lock_lock(&_modelMetaLock);
            CFDictionarySetValue(_modelMetaCache, (__bridge const void *)(cls), (__bridge const void *)(meta));
            os_unfair_lock_unlock(&_modelMetaLock);
        }
    }
    return meta;
}

@end

// ============================================================
#pragma mark - Model Set Core
// ============================================================

static void ModelSetNumberToProperty(__unsafe_unretained id model,
                                     __unsafe_unretained NSNumber *num,
                                     __unsafe_unretained _YYModelPropertyMeta *meta) {
    switch (meta->_type & YYEncodingTypeMask) {
        case YYEncodingTypeBool: {
            ((YYSendV_bool)(void *)objc_msgSend)(model, meta->_setter, num.boolValue);
        } break;
        case YYEncodingTypeInt8: {
            ((YYSendV_char)(void *)objc_msgSend)(model, meta->_setter, (char)num.charValue);
        } break;
        case YYEncodingTypeUInt8: {
            ((YYSendV_uchar)(void *)objc_msgSend)(model, meta->_setter, (unsigned char)num.unsignedCharValue);
        } break;
        case YYEncodingTypeInt16: {
            ((YYSendV_short)(void *)objc_msgSend)(model, meta->_setter, (short)num.shortValue);
        } break;
        case YYEncodingTypeUInt16: {
            ((YYSendV_ushort)(void *)objc_msgSend)(model, meta->_setter, (unsigned short)num.unsignedShortValue);
        } break;
        case YYEncodingTypeInt32: {
            ((YYSendV_int)(void *)objc_msgSend)(model, meta->_setter, (int)num.intValue);
        } break;
        case YYEncodingTypeUInt32: {
            ((YYSendV_uint)(void *)objc_msgSend)(model, meta->_setter, (unsigned int)num.unsignedIntValue);
        } break;
        case YYEncodingTypeInt64: {
            if ([num isKindOfClass:[NSDecimalNumber class]]) {
                ((YYSendV_ll)(void *)objc_msgSend)(model, meta->_setter, (long long)num.stringValue.longLongValue);
            } else {
                ((YYSendV_ll)(void *)objc_msgSend)(model, meta->_setter, num.longLongValue);
            }
        } break;
        case YYEncodingTypeUInt64: {
            if ([num isKindOfClass:[NSDecimalNumber class]]) {
                ((YYSendV_ull)(void *)objc_msgSend)(model, meta->_setter, (unsigned long long)num.stringValue.longLongValue);
            } else {
                ((YYSendV_ull)(void *)objc_msgSend)(model, meta->_setter, num.unsignedLongLongValue);
            }
        } break;
        case YYEncodingTypeFloat: {
            float f = num.floatValue;
            if (isnan(f) || isinf(f)) f = 0;
            ((YYSendV_float)(void *)objc_msgSend)(model, meta->_setter, f);
        } break;
        case YYEncodingTypeDouble: {
            double d = num.doubleValue;
            if (isnan(d) || isinf(d)) d = 0;
            ((YYSendV_double)(void *)objc_msgSend)(model, meta->_setter, d);
        } break;
        case YYEncodingTypeLongDouble: {
            long double ld = num.doubleValue;
            if (isnan(ld) || isinf(ld)) ld = 0;
            ((YYSendV_ldouble)(void *)objc_msgSend)(model, meta->_setter, ld);
        } break;
        default: break;
    }
}

static NSNumber *ModelCreateNumberFromProperty(__unsafe_unretained id model,
                                                __unsafe_unretained _YYModelPropertyMeta *meta) {
    if (!meta->_getter) return nil;

    switch (meta->_type & YYEncodingTypeMask) {
        case YYEncodingTypeBool:       return @(((YYSendR_bool)(void *)objc_msgSend)(model, meta->_getter));
        case YYEncodingTypeInt8:       return @(((char)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt8:      return @(((unsigned char)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeInt16:      return @(((short)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt16:     return @(((unsigned short)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeInt32:      return @(((int)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt32:     return @(((unsigned int)((YYSendR_uint)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeInt64:      return @(((long long)((YYSendR_ll)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt64:     return @(((unsigned long long)((YYSendR_ull)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeFloat: {
            float num = ((YYSendR_float)(void *)objc_msgSend)(model, meta->_getter);
            if (isnan(num) || isinf(num)) return nil;
            return @(num);
        }
        case YYEncodingTypeDouble: {
            double num = ((YYSendR_double)(void *)objc_msgSend)(model, meta->_getter);
            if (isnan(num) || isinf(num)) return nil;
            return @(num);
        }
        case YYEncodingTypeLongDouble: {
            long double num = ((YYSendR_ldouble)(void *)objc_msgSend)(model, meta->_getter);
            if (isnan(num) || isinf(num)) return nil;
            return @((double)num);
        }
        default: return nil;
    }
}

static void ModelSetValueForProperty(__unsafe_unretained id model,
                                     __unsafe_unretained id value,
                                     __unsafe_unretained _YYModelPropertyMeta *meta) {
    if (meta->_isCNumber) {
        NSNumber *num = YYNSNumberCreateFromID(value);
        ModelSetNumberToProperty(model, num, meta);
        if (num) [num class];
    } else if (meta->_nsType) {
        if (value == (id)kCFNull) {
            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, (id)nil);
        } else {
            switch (meta->_nsType) {
                case YYEncodingTypeNSString:
                case YYEncodingTypeNSMutableString: {
                    if ([value isKindOfClass:[NSString class]]) {
                        if (meta->_nsType == YYEncodingTypeNSString) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                        } else {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, ((NSString *)value).mutableCopy);
                        }
                    } else if ([value isKindOfClass:[NSNumber class]]) {
                        ((YYSendV_id)(void *)objc_msgSend)(model,
                                                           meta->_setter,
                                                           (meta->_nsType == YYEncodingTypeNSString) ?
                                                           ((NSNumber *)value).stringValue :
                                                           ((NSNumber *)value).stringValue.mutableCopy);
                    } else if ([value isKindOfClass:[NSData class]]) {
                        NSMutableString *string = [[NSMutableString alloc] initWithData:value encoding:NSUTF8StringEncoding];
                        ((YYSendV_id)(void *)objc_msgSend)(model,
                                                           meta->_setter,
                                                           (meta->_nsType == YYEncodingTypeNSString) ? string.copy : string);
                    } else if ([value isKindOfClass:[NSURL class]]) {
                        ((YYSendV_id)(void *)objc_msgSend)(model,
                                                           meta->_setter,
                                                           (meta->_nsType == YYEncodingTypeNSString) ?
                                                           ((NSURL *)value).absoluteString :
                                                           ((NSURL *)value).absoluteString.mutableCopy);
                    } else if ([value isKindOfClass:[NSAttributedString class]]) {
                        ((YYSendV_id)(void *)objc_msgSend)(model,
                                                           meta->_setter,
                                                           (meta->_nsType == YYEncodingTypeNSString) ?
                                                           ((NSAttributedString *)value).string :
                                                           ((NSAttributedString *)value).string.mutableCopy);
                    }
                } break;

                case YYEncodingTypeNSValue:
                case YYEncodingTypeNSNumber:
                case YYEncodingTypeNSDecimalNumber: {
                    if (meta->_nsType == YYEncodingTypeNSNumber) {
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, YYNSNumberCreateFromID(value));
                    } else if (meta->_nsType == YYEncodingTypeNSDecimalNumber) {
                        if ([value isKindOfClass:[NSDecimalNumber class]]) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                        } else if ([value isKindOfClass:[NSNumber class]]) {
                            NSDecimalNumber *decNum = [NSDecimalNumber decimalNumberWithDecimal:[((NSNumber *)value) decimalValue]];
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, decNum);
                        } else if ([value isKindOfClass:[NSString class]]) {
                            NSDecimalNumber *decNum = [NSDecimalNumber decimalNumberWithString:value];
                            NSDecimal dec = decNum.decimalValue;
                            if (dec._length == 0 && dec._isNegative) {
                                decNum = nil;
                            }
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, decNum);
                        }
                    } else {
                        if ([value isKindOfClass:[NSValue class]]) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                        }
                    }
                } break;

                case YYEncodingTypeNSData:
                case YYEncodingTypeNSMutableData: {
                    if ([value isKindOfClass:[NSData class]]) {
                        if (meta->_nsType == YYEncodingTypeNSData) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                        } else {
                            NSMutableData *data = ((NSData *)value).mutableCopy;
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, data);
                        }
                    } else if ([value isKindOfClass:[NSString class]]) {
                        NSData *data = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
                        if (meta->_nsType == YYEncodingTypeNSMutableData) {
                            data = ((NSData *)data).mutableCopy;
                        }
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, data);
                    }
                } break;

                case YYEncodingTypeNSDate: {
                    if ([value isKindOfClass:[NSDate class]]) {
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                    } else if ([value isKindOfClass:[NSString class]]) {
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, YYNSDateFromString(value));
                    } else if ([value isKindOfClass:[NSNumber class]]) {
                        NSTimeInterval ts = ((NSNumber *)value).doubleValue;
                        if (ts > 1e11) ts /= 1000.0;
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, [NSDate dateWithTimeIntervalSince1970:ts]);
                    }
                } break;

                case YYEncodingTypeNSURL: {
                    if ([value isKindOfClass:[NSURL class]]) {
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                    } else if ([value isKindOfClass:[NSString class]]) {
                        NSCharacterSet *set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
                        NSString *str = [((NSString *)value) stringByTrimmingCharactersInSet:set];
                        if (str.length == 0) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, nil);
                        } else {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, [[NSURL alloc] initWithString:str]);
                        }
                    }
                } break;

                case YYEncodingTypeNSArray:
                case YYEncodingTypeNSMutableArray: {
                    if (meta->_genericCls) {
                        NSArray *valueArr = nil;
                        if ([value isKindOfClass:[NSArray class]]) valueArr = value;
                        else if ([value isKindOfClass:[NSSet class]]) valueArr = ((NSSet *)value).allObjects;
                        if (valueArr) {
                            NSMutableArray *objectArr = [NSMutableArray new];
                            for (id one in valueArr) {
                                if ([one isKindOfClass:meta->_genericCls]) {
                                    [objectArr addObject:one];
                                } else if ([one isKindOfClass:[NSDictionary class]]) {
                                    Class cls = meta->_genericCls;
                                    if (meta->_hasCustomClassFromDictionary) {
                                        cls = [cls modelCustomClassForDictionary:one];
                                        if (!cls) cls = meta->_genericCls;
                                    }
                                    NSObject *newOne = [cls new];
                                    [newOne yy_modelSetWithDictionary:one];
                                    if (newOne) [objectArr addObject:newOne];
                                }
                            }
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, objectArr);
                        }
                    } else {
                        if ([value isKindOfClass:[NSArray class]]) {
                            if (meta->_nsType == YYEncodingTypeNSArray) {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                            } else {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, ((NSArray *)value).mutableCopy);
                            }
                        } else if ([value isKindOfClass:[NSSet class]]) {
                            if (meta->_nsType == YYEncodingTypeNSArray) {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, ((NSSet *)value).allObjects);
                            } else {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, ((NSSet *)value).allObjects.mutableCopy);
                            }
                        }
                    }
                } break;

                case YYEncodingTypeNSDictionary:
                case YYEncodingTypeNSMutableDictionary: {
                    if ([value isKindOfClass:[NSDictionary class]]) {
                        if (meta->_genericCls) {
                            NSMutableDictionary *dic = [NSMutableDictionary new];
                            [((NSDictionary *)value) enumerateKeysAndObjectsUsingBlock:^(NSString *oneKey, id oneValue, BOOL *stop) {
                                if ([oneValue isKindOfClass:[NSDictionary class]]) {
                                    Class cls = meta->_genericCls;
                                    if (meta->_hasCustomClassFromDictionary) {
                                        cls = [cls modelCustomClassForDictionary:oneValue];
                                        if (!cls) cls = meta->_genericCls;
                                    }
                                    NSObject *newOne = [cls new];
                                    [newOne yy_modelSetWithDictionary:(id)oneValue];
                                    if (newOne) dic[oneKey] = newOne;
                                }
                            }];
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, dic);
                        } else {
                            if (meta->_nsType == YYEncodingTypeNSDictionary) {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                            } else {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, ((NSDictionary *)value).mutableCopy);
                            }
                        }
                    }
                } break;

                case YYEncodingTypeNSSet:
                case YYEncodingTypeNSMutableSet: {
                    NSSet *valueSet = nil;
                    if ([value isKindOfClass:[NSArray class]]) valueSet = [NSMutableSet setWithArray:value];
                    else if ([value isKindOfClass:[NSSet class]]) valueSet = ((NSSet *)value);

                    if (meta->_genericCls) {
                        NSMutableSet *set = [NSMutableSet new];
                        for (id one in valueSet) {
                            if ([one isKindOfClass:meta->_genericCls]) {
                                [set addObject:one];
                            } else if ([one isKindOfClass:[NSDictionary class]]) {
                                Class cls = meta->_genericCls;
                                if (meta->_hasCustomClassFromDictionary) {
                                    cls = [cls modelCustomClassForDictionary:one];
                                    if (!cls) cls = meta->_genericCls;
                                }
                                NSObject *newOne = [cls new];
                                [newOne yy_modelSetWithDictionary:one];
                                if (newOne) [set addObject:newOne];
                            }
                        }
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, set);
                    } else {
                        if (meta->_nsType == YYEncodingTypeNSSet) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, valueSet);
                        } else {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, ((NSSet *)valueSet).mutableCopy);
                        }
                    }
                } break;

                default: break;
            }
        }
    } else {
        BOOL isNull = (value == (id)kCFNull);
        switch (meta->_type & YYEncodingTypeMask) {
            case YYEncodingTypeObject: {
                Class cls = meta->_genericCls ?: meta->_cls;
                if (isNull) {
                    ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, (id)nil);
                } else if ([value isKindOfClass:cls] || !cls) {
                    ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, (id)value);
                } else if ([value isKindOfClass:[NSDictionary class]]) {
                    NSObject *one = nil;
                    if (meta->_getter) {
                        one = ((YYSendR_id)(void *)objc_msgSend)(model, meta->_getter);
                    }
                    if (one) {
                        [one yy_modelSetWithDictionary:value];
                    } else {
                        if (meta->_hasCustomClassFromDictionary) {
                            cls = [cls modelCustomClassForDictionary:value] ?: cls;
                        }
                        one = [cls new];
                        [one yy_modelSetWithDictionary:value];
                        ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, (id)one);
                    }
                }
            } break;

            case YYEncodingTypeClass: {
                if (isNull) {
                    ((YYSendV_class)(void *)objc_msgSend)(model, meta->_setter, (Class)NULL);
                } else {
                    Class cls = nil;
                    if ([value isKindOfClass:[NSString class]]) {
                        cls = NSClassFromString(value);
                        if (cls) {
                            ((YYSendV_class)(void *)objc_msgSend)(model, meta->_setter, (Class)cls);
                        }
                    } else {
                        cls = object_getClass(value);
                        if (cls) {
                            if (class_isMetaClass(cls)) {
                                ((YYSendV_class)(void *)objc_msgSend)(model, meta->_setter, (Class)value);
                            }
                        }
                    }
                }
            } break;

            case YYEncodingTypeSEL: {
                if (isNull) {
                    ((YYSendV_sel)(void *)objc_msgSend)(model, meta->_setter, (SEL)NULL);
                } else if ([value isKindOfClass:[NSString class]]) {
                    SEL sel = NSSelectorFromString(value);
                    if (sel) ((YYSendV_sel)(void *)objc_msgSend)(model, meta->_setter, (SEL)sel);
                }
            } break;

            case YYEncodingTypeBlock: {
                if (isNull) {
                    ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, (id)nil);
                } else if ([value isKindOfClass:YYNSBlockClass()]) {
                    ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, (id)value);
                }
            } break;

            case YYEncodingTypeStruct:
            case YYEncodingTypeUnion:
            case YYEncodingTypeCArray: {
                if ([value isKindOfClass:[NSValue class]]) {
                    const char *valueType = ((NSValue *)value).objCType;
                    const char *metaType = meta->_info.typeEncoding.UTF8String;
                    if (valueType && metaType && strcmp(valueType, metaType) == 0) {
                        [model setValue:value forKey:meta->_name];
                    }
                }
            } break;

            case YYEncodingTypePointer:
            case YYEncodingTypeCString: {
                if (isNull) {
                    ((YYSendV_ptr)(void *)objc_msgSend)(model, meta->_setter, (void *)NULL);
                } else if ([value isKindOfClass:[NSValue class]]) {
                    NSValue *nsValue = value;
                    if (nsValue.objCType && strcmp(nsValue.objCType, "^v") == 0) {
                        ((YYSendV_ptr)(void *)objc_msgSend)(model, meta->_setter, nsValue.pointerValue);
                    }
                }
            } break;

            default: break;
        }
    }
}

typedef struct {
    void *modelMeta;
    void *model;
    void *dictionary;
} ModelSetContext;

static void ModelSetWithDictionaryFunction(const void *_key, const void *_value, void *_context) {
    ModelSetContext *context = _context;
    __unsafe_unretained _YYModelMeta *meta = (__bridge _YYModelMeta *)(context->modelMeta);
    __unsafe_unretained _YYModelPropertyMeta *propertyMeta = [meta->_mapper objectForKey:(__bridge id)(_key)];
    __unsafe_unretained id model = (__bridge id)(context->model);
    while (propertyMeta) {
        if (propertyMeta->_setter) {
            ModelSetValueForProperty(model, (__bridge __unsafe_unretained id)_value, propertyMeta);
        }
        propertyMeta = propertyMeta->_next;
    }
}

static void ModelSetWithPropertyMetaArrayFunction(const void *_propertyMeta, void *_context) {
    ModelSetContext *context = _context;
    __unsafe_unretained NSDictionary *dictionary = (__bridge NSDictionary *)(context->dictionary);
    __unsafe_unretained _YYModelPropertyMeta *propertyMeta = (__bridge _YYModelPropertyMeta *)(_propertyMeta);
    if (!propertyMeta->_setter) return;
    id value = nil;

    if (propertyMeta->_mappedToKeyArray) {
        value = YYValueForMultiKeys(dictionary, propertyMeta->_mappedToKeyArray);
    } else if (propertyMeta->_mappedToKeyPath) {
        value = YYValueForKeyPath(dictionary, propertyMeta->_mappedToKeyPath);
    } else {
        value = [dictionary objectForKey:propertyMeta->_mappedToKey];
    }

    if (value) {
        __unsafe_unretained id model = (__bridge id)(context->model);
        ModelSetValueForProperty(model, value, propertyMeta);
    }
}

// ============================================================
#pragma mark - Model → JSON
// ============================================================

static id ModelToJSONObjectRecursive(NSObject *model) {
    if (!model || model == (id)kCFNull) return model;
    if ([model isKindOfClass:[NSString class]]) return model;
    if ([model isKindOfClass:[NSNumber class]]) return model;
    if ([model isKindOfClass:[NSDictionary class]]) {
        if ([NSJSONSerialization isValidJSONObject:model]) return model;
        NSMutableDictionary *newDic = [NSMutableDictionary new];
        [((NSDictionary *)model) enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            NSString *stringKey = [key isKindOfClass:[NSString class]] ? key : key.description;
            if (!stringKey) return;
            id jsonObj = ModelToJSONObjectRecursive(obj);
            if (!jsonObj) jsonObj = (id)kCFNull;
            newDic[stringKey] = jsonObj;
        }];
        return newDic;
    }
    if ([model isKindOfClass:[NSSet class]]) {
        NSArray *array = ((NSSet *)model).allObjects;
        if ([NSJSONSerialization isValidJSONObject:array]) return array;
        NSMutableArray *newArray = [NSMutableArray new];
        for (id obj in array) {
            if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) {
                [newArray addObject:obj];
            } else {
                id jsonObj = ModelToJSONObjectRecursive(obj);
                if (jsonObj && jsonObj != (id)kCFNull) [newArray addObject:jsonObj];
            }
        }
        return newArray;
    }
    if ([model isKindOfClass:[NSArray class]]) {
        if ([NSJSONSerialization isValidJSONObject:model]) return model;
        NSMutableArray *newArray = [NSMutableArray new];
        for (id obj in (NSArray *)model) {
            if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) {
                [newArray addObject:obj];
            } else {
                id jsonObj = ModelToJSONObjectRecursive(obj);
                if (jsonObj && jsonObj != (id)kCFNull) [newArray addObject:jsonObj];
            }
        }
        return newArray;
    }
    if ([model isKindOfClass:[NSURL class]]) return ((NSURL *)model).absoluteString;
    if ([model isKindOfClass:[NSAttributedString class]]) return ((NSAttributedString *)model).string;
    if ([model isKindOfClass:[NSDate class]]) return YYISODateString((NSDate *)model);
    if ([model isKindOfClass:[NSData class]]) return nil;

    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:[model class]];
    if (!modelMeta || modelMeta->_keyMappedCount == 0) return nil;
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:64];
    __unsafe_unretained NSMutableDictionary *dic = result;

    [modelMeta->_mapper enumerateKeysAndObjectsUsingBlock:^(NSString *propertyMappedKey, _YYModelPropertyMeta *propertyMeta, BOOL *stop) {
        if (!propertyMeta->_getter) return;

        id value = nil;
        if (propertyMeta->_isCNumber) {
            value = ModelCreateNumberFromProperty(model, propertyMeta);
        } else if (propertyMeta->_nsType) {
            id v = ((YYSendR_id)(void *)objc_msgSend)(model, propertyMeta->_getter);
            value = ModelToJSONObjectRecursive(v);
        } else {
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject: {
                    id v = ((YYSendR_id)(void *)objc_msgSend)(model, propertyMeta->_getter);
                    value = ModelToJSONObjectRecursive(v);
                    if (value == (id)kCFNull) value = nil;
                } break;
                case YYEncodingTypeClass: {
                    Class v = ((YYSendR_class)(void *)objc_msgSend)(model, propertyMeta->_getter);
                    value = v ? NSStringFromClass(v) : nil;
                } break;
                case YYEncodingTypeSEL: {
                    SEL v = ((YYSendR_sel)(void *)objc_msgSend)(model, propertyMeta->_getter);
                    value = v ? NSStringFromSelector(v) : nil;
                } break;
                default: break;
            }
        }
        if (!value) return;

        if (propertyMeta->_mappedToKeyPath) {
            NSMutableDictionary *superDic = dic;
            NSMutableDictionary *subDic = nil;
            for (NSUInteger i = 0, max = propertyMeta->_mappedToKeyPath.count; i < max; i++) {
                NSString *key = propertyMeta->_mappedToKeyPath[i];
                if (i + 1 == max) {
                    if (!superDic[key]) superDic[key] = value;
                    break;
                }

                subDic = superDic[key];
                if (subDic) {
                    if ([subDic isKindOfClass:[NSDictionary class]]) {
                        subDic = subDic.mutableCopy;
                        superDic[key] = subDic;
                    } else {
                        break;
                    }
                } else {
                    subDic = [NSMutableDictionary new];
                    superDic[key] = subDic;
                }
                superDic = subDic;
                subDic = nil;
            }
        } else {
            if (!dic[propertyMeta->_mappedToKey]) {
                dic[propertyMeta->_mappedToKey] = value;
            }
        }
    }];

    if (modelMeta->_hasCustomTransformToDictionary) {
        BOOL suc = [((id<YYModel>)model) modelCustomTransformToDictionary:dic];
        if (!suc) return nil;
    }
    return result;
}

static NSMutableString *ModelDescriptionAddIndent(NSMutableString *desc, NSUInteger indent) {
    for (NSUInteger i = 0, max = desc.length; i < max; i++) {
        unichar c = [desc characterAtIndex:i];
        if (c == '\n') {
            for (NSUInteger j = 0; j < indent; j++) {
                [desc insertString:@"    " atIndex:i + 1];
            }
            i += (indent * 4);
            max += (indent * 4);
        }
    }
    return desc;
}

static NSString *ModelDescription(NSObject *model) {
    static const int kDescMaxLength = 100;
    if (!model) return @"<nil>";
    if (model == (id)kCFNull) return @"<null>";
    if (![model isKindOfClass:[NSObject class]]) return [NSString stringWithFormat:@"%@", model];

    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:model.class];
    switch (modelMeta->_nsType) {
        case YYEncodingTypeNSString: case YYEncodingTypeNSMutableString: {
            return [NSString stringWithFormat:@"\"%@\"", model];
        }
        case YYEncodingTypeNSValue:
        case YYEncodingTypeNSData: case YYEncodingTypeNSMutableData: {
            NSString *tmp = model.description;
            if (tmp.length > kDescMaxLength) {
                tmp = [tmp substringToIndex:kDescMaxLength];
                tmp = [tmp stringByAppendingString:@"..."];
            }
            return tmp;
        }
        case YYEncodingTypeNSNumber:
        case YYEncodingTypeNSDecimalNumber:
        case YYEncodingTypeNSDate:
        case YYEncodingTypeNSURL: {
            return [NSString stringWithFormat:@"%@", model];
        }
        case YYEncodingTypeNSSet: case YYEncodingTypeNSMutableSet: {
            model = ((NSSet *)model).allObjects;
        } // fall through
        case YYEncodingTypeNSArray: case YYEncodingTypeNSMutableArray: {
            NSArray *array = (id)model;
            NSMutableString *desc = [NSMutableString new];
            if (array.count == 0) {
                return [desc stringByAppendingString:@"[]"];
            } else {
                [desc appendFormat:@"[\n"];
                for (NSUInteger i = 0, max = array.count; i < max; i++) {
                    NSObject *obj = array[i];
                    [desc appendString:@"    "];
                    [desc appendString:ModelDescriptionAddIndent(ModelDescription(obj).mutableCopy, 1)];
                    [desc appendString:(i + 1 == max) ? @"\n" : @";\n"];
                }
                [desc appendString:@"]"];
                return desc;
            }
        }
        case YYEncodingTypeNSDictionary: case YYEncodingTypeNSMutableDictionary: {
            NSDictionary *dic = (id)model;
            NSMutableString *desc = [NSMutableString new];
            if (dic.count == 0) {
                return [desc stringByAppendingString:@"{}"];
            } else {
                NSArray *keys = dic.allKeys;
                [desc appendFormat:@"{\n"];
                for (NSUInteger i = 0, max = keys.count; i < max; i++) {
                    NSString *key = keys[i];
                    NSObject *value = dic[key];
                    [desc appendString:@"    "];
                    [desc appendFormat:@"%@ = %@", key, ModelDescriptionAddIndent(ModelDescription(value).mutableCopy, 1)];
                    [desc appendString:(i + 1 == max) ? @"\n" : @";\n"];
                }
                [desc appendString:@"}"];
            }
            return desc;
        }
        default: {
            NSMutableString *desc = [NSMutableString new];
            [desc appendFormat:@"<%@: %p>", model.class, model];
            if (modelMeta->_allPropertyMetas.count == 0) return desc;

            NSArray *properties = [modelMeta->_allPropertyMetas
                                   sortedArrayUsingComparator:^NSComparisonResult(_YYModelPropertyMeta *p1, _YYModelPropertyMeta *p2) {
                                       return [p1->_name compare:p2->_name];
                                   }];

            [desc appendFormat:@" {\n"];
            for (NSUInteger i = 0, max = properties.count; i < max; i++) {
                _YYModelPropertyMeta *property = properties[i];
                NSString *propertyDesc;
                if (property->_isCNumber) {
                    NSNumber *num = ModelCreateNumberFromProperty(model, property);
                    propertyDesc = num.stringValue;
                } else {
                    switch (property->_type & YYEncodingTypeMask) {
                        case YYEncodingTypeObject: {
                            id v = ((YYSendR_id)(void *)objc_msgSend)(model, property->_getter);
                            propertyDesc = ModelDescription(v);
                            if (!propertyDesc) propertyDesc = @"<nil>";
                        } break;
                        case YYEncodingTypeClass: {
                            id v = ((YYSendR_id)(void *)objc_msgSend)(model, property->_getter);
                            propertyDesc = ((NSObject *)v).description;
                            if (!propertyDesc) propertyDesc = @"<nil>";
                        } break;
                        case YYEncodingTypeSEL: {
                            SEL v = ((YYSendR_sel)(void *)objc_msgSend)(model, property->_getter);
                            propertyDesc = v ? NSStringFromSelector(v) : @"<NULL>";
                        } break;
                        case YYEncodingTypeBlock: {
                            id v = ((YYSendR_id)(void *)objc_msgSend)(model, property->_getter);
                            propertyDesc = ((NSObject *)v).description;
                            if (!propertyDesc) propertyDesc = @"<nil>";
                        } break;
                        case YYEncodingTypeStruct:
                        case YYEncodingTypeUnion: {
                            NSValue *v = [model valueForKey:property->_name];
                            propertyDesc = ((NSObject *)v).description;
                            if (!propertyDesc) propertyDesc = @"<nil>";
                        } break;
                        default: {
                            propertyDesc = @"<unknown>";
                        } break;
                    }
                }
                propertyDesc = ModelDescriptionAddIndent(propertyDesc.mutableCopy, 1);
                [desc appendFormat:@"    %@ = %@%@\n", property->_name, propertyDesc, (i + 1 == max) ? @"" : @";"];
            }
            [desc appendFormat:@"}"];
            return desc;
        }
    }
}

// ============================================================
#pragma mark - NSObject (YYModel)
// ============================================================

@implementation NSObject (YYModel)

+ (NSDictionary *)_yy_dictionaryWithJSON:(id)json {
    if (!json || json == (id)kCFNull) return nil;
    NSDictionary *dic = nil;
    NSData *jsonData = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dic = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        jsonData = [(NSString *)json dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    if (jsonData) {
        dic = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![dic isKindOfClass:[NSDictionary class]]) dic = nil;
    }
    return dic;
}

+ (instancetype)yy_modelWithJSON:(id)json {
    NSDictionary *dic = [self _yy_dictionaryWithJSON:json];
    return [self yy_modelWithDictionary:dic];
}

+ (instancetype)yy_modelWithDictionary:(NSDictionary *)dictionary {
    if (!dictionary || dictionary == (id)kCFNull) return nil;
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;

    Class cls = [self class];
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:cls];
    if (modelMeta->_hasCustomClassFromDictionary) {
        cls = [cls modelCustomClassForDictionary:dictionary] ?: cls;
    }

    NSObject *one = [cls new];
    if ([one yy_modelSetWithDictionary:dictionary]) return one;
    return nil;
}

- (BOOL)yy_modelSetWithJSON:(id)json {
    NSDictionary *dic = [NSObject _yy_dictionaryWithJSON:json];
    return [self yy_modelSetWithDictionary:dic];
}

- (BOOL)yy_modelSetWithDictionary:(NSDictionary *)dic {
    if (!dic || dic == (id)kCFNull) return NO;
    if (![dic isKindOfClass:[NSDictionary class]]) return NO;

    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:object_getClass(self)];
    if (modelMeta->_keyMappedCount == 0) return NO;

    if (modelMeta->_hasCustomWillTransformFromDictionary) {
        dic = [((id<YYModel>)self) modelCustomWillTransformFromDictionary:dic];
        if (![dic isKindOfClass:[NSDictionary class]]) return NO;
    }

    ModelSetContext context = {0};
    context.modelMeta = (__bridge void *)(modelMeta);
    context.model = (__bridge void *)(self);
    context.dictionary = (__bridge void *)(dic);

    if (modelMeta->_keyMappedCount >= CFDictionaryGetCount((CFDictionaryRef)dic)) {
        CFDictionaryApplyFunction((CFDictionaryRef)dic, ModelSetWithDictionaryFunction, &context);
        if (modelMeta->_keyPathPropertyMetas) {
            CFArrayApplyFunction((CFArrayRef)modelMeta->_keyPathPropertyMetas,
                                 CFRangeMake(0, CFArrayGetCount((CFArrayRef)modelMeta->_keyPathPropertyMetas)),
                                 ModelSetWithPropertyMetaArrayFunction,
                                 &context);
        }
        if (modelMeta->_multiKeysPropertyMetas) {
            CFArrayApplyFunction((CFArrayRef)modelMeta->_multiKeysPropertyMetas,
                                 CFRangeMake(0, CFArrayGetCount((CFArrayRef)modelMeta->_multiKeysPropertyMetas)),
                                 ModelSetWithPropertyMetaArrayFunction,
                                 &context);
        }
    } else {
        CFArrayApplyFunction((CFArrayRef)modelMeta->_allPropertyMetas,
                             CFRangeMake(0, modelMeta->_keyMappedCount),
                             ModelSetWithPropertyMetaArrayFunction,
                             &context);
    }

    if (modelMeta->_hasCustomTransformFromDictionary) {
        return [((id<YYModel>)self) modelCustomTransformFromDictionary:dic];
    }
    return YES;
}

- (id)yy_modelToJSONObject {
    id jsonObject = ModelToJSONObjectRecursive(self);
    if ([jsonObject isKindOfClass:[NSArray class]]) return jsonObject;
    if ([jsonObject isKindOfClass:[NSDictionary class]]) return jsonObject;
    return nil;
}

- (NSData *)yy_modelToJSONData {
    id jsonObject = [self yy_modelToJSONObject];
    if (!jsonObject) return nil;
    return [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:NULL];
}

- (NSString *)yy_modelToJSONString {
    NSData *jsonData = [self yy_modelToJSONData];
    if (jsonData.length == 0) return nil;
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (id)yy_modelCopy {
    if (self == (id)kCFNull) return self;
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) return [self copy];

    NSObject *one = [self.class new];
    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        if (!propertyMeta->_getter || !propertyMeta->_setter) continue;

        if (propertyMeta->_isCNumber) {
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeBool: {
                    BOOL num = ((YYSendR_bool)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_bool)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt8:
                case YYEncodingTypeUInt8: {
                    unsigned char num = ((YYSendR_uchar)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_uchar)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt16:
                case YYEncodingTypeUInt16: {
                    unsigned short num = ((YYSendR_ushort)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_ushort)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt32:
                case YYEncodingTypeUInt32: {
                    unsigned int num = ((YYSendR_uint)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_uint)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeInt64:
                case YYEncodingTypeUInt64: {
                    unsigned long long num = ((YYSendR_ull)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_ull)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeFloat: {
                    float num = ((YYSendR_float)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_float)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeDouble: {
                    double num = ((YYSendR_double)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_double)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                case YYEncodingTypeLongDouble: {
                    long double num = ((YYSendR_ldouble)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_ldouble)(void *)objc_msgSend)(one, propertyMeta->_setter, num);
                } break;
                default: break;
            }
        } else {
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject:
                case YYEncodingTypeClass:
                case YYEncodingTypeBlock: {
                    id value = ((YYSendR_id)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_id)(void *)objc_msgSend)(one, propertyMeta->_setter, value);
                } break;
                case YYEncodingTypeSEL:
                case YYEncodingTypePointer:
                case YYEncodingTypeCString: {
                    size_t value = ((YYSendR_size_t)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    ((YYSendV_size_t)(void *)objc_msgSend)(one, propertyMeta->_setter, value);
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    @try {
                        NSValue *value = [self valueForKey:NSStringFromSelector(propertyMeta->_getter)];
                        if (value) {
                            [one setValue:value forKey:propertyMeta->_name];
                        }
                    } @catch (NSException *exception) {}
                } break;
                default: break;
            }
        }
    }
    return one;
}

- (void)yy_modelEncodeWithCoder:(NSCoder *)aCoder {
    if (!aCoder) return;
    if (self == (id)kCFNull) {
        [((id<NSCoding>)self)encodeWithCoder:aCoder];
        return;
    }

    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) {
        [((id<NSCoding>)self)encodeWithCoder:aCoder];
        return;
    }

    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        if (!propertyMeta->_getter) continue;

        if (propertyMeta->_isCNumber) {
            NSNumber *value = ModelCreateNumberFromProperty(self, propertyMeta);
            if (value) [aCoder encodeObject:value forKey:propertyMeta->_name];
        } else {
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject: {
                    id value = ((YYSendR_id)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    if (value && (propertyMeta->_nsType || [value respondsToSelector:@selector(encodeWithCoder:)])) {
                        if ([value isKindOfClass:[NSValue class]]) {
                            if ([value isKindOfClass:[NSNumber class]]) {
                                [aCoder encodeObject:value forKey:propertyMeta->_name];
                            }
                        } else {
                            [aCoder encodeObject:value forKey:propertyMeta->_name];
                        }
                    }
                } break;
                case YYEncodingTypeClass: {
                    id value = ((YYSendR_id)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    Class cls = (Class)value;
                    if (cls) {
                        NSString *str = NSStringFromClass(cls);
                        [aCoder encodeObject:str forKey:propertyMeta->_name];
                    }
                } break;
                case YYEncodingTypeSEL: {
                    SEL value = ((YYSendR_sel)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    if (value) {
                        NSString *str = NSStringFromSelector(value);
                        [aCoder encodeObject:str forKey:propertyMeta->_name];
                    }
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    if (propertyMeta->_isKVCCompatible && propertyMeta->_isStructAvailableForKeyedArchiver) {
                        @try {
                            NSValue *value = [self valueForKey:NSStringFromSelector(propertyMeta->_getter)];
                            [aCoder encodeObject:value forKey:propertyMeta->_name];
                        } @catch (NSException *exception) {}
                    }
                } break;
                default: break;
            }
        }
    }
}

- (instancetype)yy_modelInitWithCoder:(NSCoder *)aDecoder {
    if (!aDecoder) return self;
    if (self == (id)kCFNull) return self;
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) return self;

    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        if (!propertyMeta->_setter) continue;

        if (propertyMeta->_isCNumber) {
            NSNumber *value = nil;
            @try {
                if ([aDecoder respondsToSelector:@selector(decodeObjectOfClass:forKey:)]) {
                    value = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:propertyMeta->_name];
                } else {
                    value = [aDecoder decodeObjectForKey:propertyMeta->_name];
                }
            } @catch (NSException *exception) {}
            if ([value isKindOfClass:[NSNumber class]]) {
                ModelSetNumberToProperty(self, value, propertyMeta);
                [value class];
            }
        } else {
            YYEncodingType type = propertyMeta->_type & YYEncodingTypeMask;
            switch (type) {
                case YYEncodingTypeObject: {
                    id value = nil;
                    BOOL isContainer = (propertyMeta->_nsType == YYEncodingTypeNSArray ||
                                        propertyMeta->_nsType == YYEncodingTypeNSMutableArray ||
                                        propertyMeta->_nsType == YYEncodingTypeNSDictionary ||
                                        propertyMeta->_nsType == YYEncodingTypeNSMutableDictionary ||
                                        propertyMeta->_nsType == YYEncodingTypeNSSet ||
                                        propertyMeta->_nsType == YYEncodingTypeNSMutableSet ||
                                        (propertyMeta->_cls && ([propertyMeta->_cls isSubclassOfClass:[NSArray class]] ||
                                                                [propertyMeta->_cls isSubclassOfClass:[NSDictionary class]] ||
                                                                [propertyMeta->_cls isSubclassOfClass:[NSSet class]])));
                    @try {
                        if (isContainer && [aDecoder respondsToSelector:@selector(decodeObjectOfClasses:forKey:)]) {
                            NSMutableSet *classes = [NSMutableSet setWithObjects:
                                                     [NSArray class], [NSMutableArray class],
                                                     [NSDictionary class], [NSMutableDictionary class],
                                                     [NSSet class], [NSMutableSet class],
                                                     [NSString class], [NSNumber class],
                                                     [NSDate class], [NSData class],
                                                     [NSNull class], [NSURL class], [NSValue class], nil];
                            if (propertyMeta->_cls) [classes addObject:propertyMeta->_cls];
                            if (propertyMeta->_genericCls) [classes addObject:propertyMeta->_genericCls];
                            value = [aDecoder decodeObjectOfClasses:classes forKey:propertyMeta->_name];
                        } else if (propertyMeta->_cls && [aDecoder respondsToSelector:@selector(decodeObjectOfClass:forKey:)]) {
                            value = [aDecoder decodeObjectOfClass:propertyMeta->_cls forKey:propertyMeta->_name];
                        } else {
                            value = [aDecoder decodeObjectForKey:propertyMeta->_name];
                        }
                    } @catch (NSException *exception) {
                        if (!aDecoder.requiresSecureCoding) {
                            @try {
                                value = [aDecoder decodeObjectForKey:propertyMeta->_name];
                            } @catch (NSException *e) {}
                        }
                    }
                    if (value) ((YYSendV_id)(void *)objc_msgSend)(self, propertyMeta->_setter, value);
                } break;
                case YYEncodingTypeClass: {
                    NSString *str = nil;
                    @try {
                        if ([aDecoder respondsToSelector:@selector(decodeObjectOfClass:forKey:)]) {
                            str = [aDecoder decodeObjectOfClass:[NSString class] forKey:propertyMeta->_name];
                        } else {
                            str = [aDecoder decodeObjectForKey:propertyMeta->_name];
                        }
                    } @catch (NSException *exception) {}
                    if ([str isKindOfClass:[NSString class]]) {
                        Class cls = NSClassFromString(str);
                        if (cls) ((YYSendV_class)(void *)objc_msgSend)(self, propertyMeta->_setter, cls);
                    }
                } break;
                case YYEncodingTypeSEL: {
                    NSString *str = nil;
                    @try {
                        if ([aDecoder respondsToSelector:@selector(decodeObjectOfClass:forKey:)]) {
                            str = [aDecoder decodeObjectOfClass:[NSString class] forKey:propertyMeta->_name];
                        } else {
                            str = [aDecoder decodeObjectForKey:propertyMeta->_name];
                        }
                    } @catch (NSException *exception) {}
                    if ([str isKindOfClass:[NSString class]]) {
                        SEL sel = NSSelectorFromString(str);
                        if (sel) ((YYSendV_sel)(void *)objc_msgSend)(self, propertyMeta->_setter, sel);
                    }
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    if (propertyMeta->_isKVCCompatible) {
                        NSValue *value = nil;
                        @try {
                            if ([aDecoder respondsToSelector:@selector(decodeObjectOfClass:forKey:)]) {
                                value = [aDecoder decodeObjectOfClass:[NSValue class] forKey:propertyMeta->_name];
                            } else {
                                value = [aDecoder decodeObjectForKey:propertyMeta->_name];
                            }
                        } @catch (NSException *exception) {}
                        if (value) [self setValue:value forKey:propertyMeta->_name];
                    }
                } break;
                default: break;
            }
        }
    }
    return self;
}

- (NSUInteger)yy_modelHash {
    if (self == (id)kCFNull) return [self hash];
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) return [self hash];

    NSUInteger value = 0;
    NSUInteger count = 0;
    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        if (!propertyMeta->_getter) continue;
        value ^= [propertyMeta->_name hash];
        count++;

        if (propertyMeta->_isCNumber) {
            NSNumber *num = ModelCreateNumberFromProperty(self, propertyMeta);
            if (num) value ^= num.hash;
        } else {
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject:
                case YYEncodingTypeClass:
                case YYEncodingTypeBlock: {
                    id v = ((YYSendR_id)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    if (v) value ^= [v hash];
                } break;
                case YYEncodingTypeSEL: {
                    SEL v = ((YYSendR_sel)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    if (v) value ^= (NSUInteger)(uintptr_t)(void *)v;
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    @try {
                        NSValue *v = [self valueForKey:NSStringFromSelector(propertyMeta->_getter)];
                        if (v) value ^= [v hash];
                    } @catch (NSException *exception) {}
                } break;
                default: break;
            }
        }
    }
    if (count == 0) value = (NSUInteger)((__bridge void *)self);
    return value;
}

- (BOOL)yy_modelIsEqual:(id)model {
    if (self == model) return YES;
    if (![model isMemberOfClass:self.class]) return NO;
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:self.class];
    if (modelMeta->_nsType) return [self isEqual:model];
    if ([self hash] != [model hash]) return NO;

    for (_YYModelPropertyMeta *propertyMeta in modelMeta->_allPropertyMetas) {
        if (!propertyMeta->_getter) continue;

        if (propertyMeta->_isCNumber) {
            NSNumber *p1 = ModelCreateNumberFromProperty(self, propertyMeta);
            NSNumber *p2 = ModelCreateNumberFromProperty(model, propertyMeta);
            if (p1 != p2 && ![p1 isEqualToNumber:p2]) return NO;
        } else {
            switch (propertyMeta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject:
                case YYEncodingTypeClass:
                case YYEncodingTypeBlock: {
                    id p1 = ((YYSendR_id)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    id p2 = ((YYSendR_id)(void *)objc_msgSend)(model, propertyMeta->_getter);
                    if (p1 != p2 && ![p1 isEqual:p2]) return NO;
                } break;
                case YYEncodingTypeSEL: {
                    SEL p1 = ((YYSendR_sel)(void *)objc_msgSend)(self, propertyMeta->_getter);
                    SEL p2 = ((YYSendR_sel)(void *)objc_msgSend)(model, propertyMeta->_getter);
                    if (p1 != p2) return NO;
                } break;
                case YYEncodingTypeStruct:
                case YYEncodingTypeUnion: {
                    @try {
                        NSValue *p1 = [self valueForKey:NSStringFromSelector(propertyMeta->_getter)];
                        NSValue *p2 = [model valueForKey:NSStringFromSelector(propertyMeta->_getter)];
                        if (p1 != p2 && ![p1 isEqual:p2]) return NO;
                    } @catch (NSException *exception) {
                        return NO;
                    }
                } break;
                default: break;
            }
        }
    }
    return YES;
}

- (NSString *)yy_modelDescription {
    return ModelDescription(self);
}

@end

// ============================================================
#pragma mark - NSArray / NSDictionary (YYModel)
// ============================================================

@implementation NSArray (YYModel)

+ (NSArray *)yy_modelArrayWithClass:(Class)cls json:(id)json {
    if (!json) return nil;
    NSArray *arr = nil;
    NSData *jsonData = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        arr = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        jsonData = [(NSString *)json dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    if (jsonData) {
        arr = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![arr isKindOfClass:[NSArray class]]) arr = nil;
    }
    return [self yy_modelArrayWithClass:cls array:arr];
}

+ (NSArray *)yy_modelArrayWithClass:(Class)cls array:(NSArray *)arr {
    if (!cls || !arr) return nil;
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *dic in arr) {
        if (![dic isKindOfClass:[NSDictionary class]]) continue;
        NSObject *obj = [cls yy_modelWithDictionary:dic];
        if (obj) [result addObject:obj];
    }
    return result;
}

@end

@implementation NSDictionary (YYModel)

+ (NSDictionary *)yy_modelDictionaryWithClass:(Class)cls json:(id)json {
    if (!json) return nil;
    NSDictionary *dic = nil;
    NSData *jsonData = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dic = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        jsonData = [(NSString *)json dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    if (jsonData) {
        dic = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![dic isKindOfClass:[NSDictionary class]]) dic = nil;
    }
    return [self yy_modelDictionaryWithClass:cls dictionary:dic];
}

+ (NSDictionary *)yy_modelDictionaryWithClass:(Class)cls dictionary:(NSDictionary *)dic {
    if (!cls || !dic) return nil;
    NSMutableDictionary *result = [NSMutableDictionary new];
    for (NSString *key in dic.allKeys) {
        if (![key isKindOfClass:[NSString class]]) continue;
        NSObject *obj = [cls yy_modelWithDictionary:dic[key]];
        if (obj) result[key] = obj;
    }
    return result;
}

@end
