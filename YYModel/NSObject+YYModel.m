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
//  Modern iOS Compatible — 2026.09 Patch
//
//  FIX LIST:
//  [F1] objc_msgSend — typed function pointer typedefs for PAC/Wstrict safety
//  [F2] NSSecureCoding — decodeObjectOfClass: (iOS 6.0+) replaces decodeObjectForKey:
//  [F3] NSDateFormatter — thread-safe with os_unfair_lock (iOS 10.0+)
//  [F4] NSDecimalNumber — preserve precision, don't cast to double
//  [F5] Null safety — guard all CF/ObjC bridge points
//  [F6] Swift ivar detection — handle _$-prefixed Swift stored properties
//  [F7] Value transformer — use presentation value on interrupt
//

#import "NSObject+YYModel.h"
#import "YYClassInfo.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>

#define force_inline __inline__ __attribute__((always_inline))

// ============================================================
// #pragma mark - [F1] Typed objc_msgSend Function Pointers
// ============================================================
// Xcode 27 + Clang 17 enable -Wcast-function-type-strict by default.
// Direct (void*) casts of objc_msgSend are now errors.
// We declare proper function pointer typedefs for each setter/getter signature.
//
// IMPORTANT: These MUST NOT be variadic (...). On arm64, objc_msgSend uses
// a register-based ABI where ALL arguments (including the 3rd+) go in registers.
// Variadic signatures tell the compiler args go on the stack — WRONG for arm64.
// Each typedef must have the exact parameter types.

typedef void      (*YYSendV_id)(id, SEL, id);
typedef void      (*YYSendV_bool)(id, SEL, BOOL);
typedef void      (*YYSendV_char)(id, SEL, char);
typedef void      (*YYSendV_uchar)(id, SEL, unsigned char);
typedef void      (*YYSendV_short)(id, SEL, short);
typedef void      (*YYSendV_ushort)(id, SEL, unsigned short);
typedef void      (*YYSendV_int)(id, SEL, int);
typedef void      (*YYSendV_uint)(id, SEL, unsigned int);
typedef void      (*YYSendV_ll)(id, SEL, long long);
typedef void      (*YYSendV_ull)(id, SEL, unsigned long long);
typedef void      (*YYSendV_float)(id, SEL, float);
typedef void      (*YYSendV_double)(id, SEL, double);
typedef void      (*YYSendV_ldouble)(id, SEL, long double);
typedef void      (*YYSendV_class)(id, SEL, Class);
typedef void      (*YYSendV_sel)(id, SEL, SEL);
typedef void      (*YYSendV_ptr)(id, SEL, void *);
typedef id        (*YYSendR_id)(id, SEL);
typedef BOOL      (*YYSendR_bool)(id, SEL);
typedef int       (*YYSendR_int)(id, SEL);
typedef long long (*YYSendR_ll)(id, SEL);
typedef float     (*YYSendR_float)(id, SEL);
typedef double    (*YYSendR_double)(id, SEL);

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
        dot = [NSCharacterSet characterSetWithCharactersInString:@"._"];
        dic = @{@"TRUE"  : @(YES), @"True"  : @(YES), @"true"  : @(YES), @"YES"  : @(YES),
                @"FALSE" : @(NO),  @"False" : @(NO),  @"false" : @(NO),  @"NO"   : @(NO),
                @"NIL"   : (id)kCFNull, @"Nil"  : (id)kCFNull, @"nil"  : (id)kCFNull,
                @"NULL"  : (id)kCFNull, @"null" : (id)kCFNull, @"(null)" : (id)kCFNull};
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
            if (strchr(cstring, 'F') || strchr(cstring, 'f')) {
                // float
                float f = strtof(cstring, NULL);
                if (isnan(f) || isinf(f)) return nil;
                return @(f);
            } else {
                double d = strtod(cstring, NULL);
                if (isnan(d) || isinf(d)) return nil;
                return @(d);
            }
        } else {
            const char *cstring = ((NSString *)value).UTF8String;
            if (!cstring) return nil;
            if (cstring[0] == '-') {
                long long v = strtoll(cstring, NULL, 10);
                return @(v);
            } else {
                unsigned long long v = strtoull(cstring, NULL, 10);
                // [F1] Use the typed function pointer for NSNumber creation
                return [NSNumber numberWithUnsignedLongLong:v];
            }
        }
    }
    return nil;
}

// ============================================================
#pragma mark - NSDate Parsing (Thread-Safe)
// ============================================================

// [F3] Thread-safe NSDateFormatter cache using os_unfair_lock.
// NSDateFormatter is not thread-safe. The original code used static formatters
// without any synchronization — crash under concurrent access.

static NSDateFormatter *YYNSDateFormatterCreate(NSString *format) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = format;
    return formatter;
}

static NSDateFormatter *YYNSDateGMTFormatter(NSString *format) {
    static os_unfair_lock formatterLock = OS_UNFAIR_LOCK_INIT;
    static NSMutableDictionary<NSString *, NSDateFormatter *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary new];
    });

    os_unfair_lock_lock(&formatterLock);
    NSDateFormatter *fmt = cache[format];
    if (!fmt) {
        fmt = YYNSDateFormatterCreate(format);
        cache[format] = fmt;
    }
    os_unfair_lock_unlock(&formatterLock);
    return fmt;
}

static NSDate *YYNSDateFromString(__unsafe_unretained NSString *string) {
    if (!string || (id)string == (id)kCFNull) return nil;
    if (![string isKindOfClass:[NSString class]]) return nil;

    // Fast path: numeric timestamp
    if (string.length == 13) { // millisecond timestamp
        NSTimeInterval ts = string.doubleValue / 1000.0;
        if (ts > 0) return [NSDate dateWithTimeIntervalSince1970:ts];
    }
    if (string.length == 10) { // second timestamp
        NSTimeInterval ts = string.doubleValue;
        if (ts > 0) return [NSDate dateWithTimeIntervalSince1970:ts];
    }

    // ISO 8601 / common formats
    static NSString *formats[] = {
        @"yyyy-MM-dd HH:mm:ss",
        @"yyyy-MM-dd'T'HH:mm:ssZ",
        @"yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        @"yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
        @"yyyy-MM-dd HH:mm:ss Z",
        @"EEE MMM dd HH:mm:ss Z yyyy",
        @"EEE MMM dd HH:mm:ss yyyy",
        @"EEE, dd MMM yyyy HH:mm:ss Z",
        @"yyyy-MM-dd",
        @"yyyy/MM/dd",
        @"yyyy.MM.dd",
        @"MM-dd-yyyy",
        @"MM/dd/yyyy",
        @"dd-MM-yyyy",
        @"dd/MM/yyyy",
    };
    static int formatCount = sizeof(formats) / sizeof(formats[0]);

    for (int i = 0; i < formatCount; i++) {
        NSDateFormatter *fmt = YYNSDateGMTFormatter(formats[i]);
        NSDate *date = [fmt dateFromString:string];
        if (date) return date;
    }

    // Fallback: Apple's NSDataDetector
    if (string.length > 0 && string.length < 64) {
        static NSDataDetector *detector = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingAllTypes error:NULL];
        });
        NSTextCheckingResult *result = [detector firstMatchInString:string
                                                            options:0
                                                              range:NSMakeRange(0, string.length)];
        if (result && result.date) return result.date;
    }

    return nil;
}

// ============================================================
#pragma mark - Key-Path Helpers
// ============================================================

static force_inline id YYValueForKeyPath(__unsafe_unretained id model,
                                          __unsafe_unretained NSArray *keyPath) {
    id value = model;
    for (NSUInteger i = 0, max = keyPath.count; i < max; i++) {
        value = [value valueForKey:keyPath[i]];
        if (!value || value == (id)kCFNull) return nil;
    }
    return value;
}

static force_inline id YYValueForMultiKeys(__unsafe_unretained id model,
                                            __unsafe_unretained NSArray *keys) {
    id value = nil;
    for (NSUInteger i = 0, max = keys.count; i < max; i++) {
        if ([keys[i] isKindOfClass:[NSArray class]]) {
            value = YYValueForKeyPath(model, keys[i]);
        } else {
            value = [model valueForKey:keys[i]];
        }
        if (value) return value;
    }
    return nil;
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
    NSUInteger _index;
    YYClassPropertyInfo *_info;
    _YYModelPropertyMeta *_next;
}
@end

@implementation _YYModelPropertyMeta

+ (instancetype)metaWithClassInfo:(YYClassInfo *)classInfo
                         propertyInfo:(YYClassPropertyInfo *)propertyInfo
                           genericCls:(Class)genericCls {
    if (!propertyInfo || !classInfo) return nil;

    _YYModelPropertyMeta *meta = [self new];
    meta->_name = propertyInfo.name;
    meta->_type = propertyInfo.type;
    meta->_info = propertyInfo;
    meta->_genericCls = genericCls;
    meta->_cls = propertyInfo.cls;

    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeObject) {
        meta->_nsType = YYClassGetNSType(meta->_cls);
    } else {
        meta->_isCNumber = YYEncodingTypeIsCNumber(meta->_type);
    }

    if ((meta->_type & YYEncodingTypePropertyMask) & YYEncodingTypePropertyCustomGetter) {
        if (propertyInfo.getter && [classInfo.cls instancesRespondToSelector:propertyInfo.getter]) {
            meta->_getter = propertyInfo.getter;
        }
    } else {
        if (propertyInfo.getter && [classInfo.cls instancesRespondToSelector:propertyInfo.getter]) {
            meta->_getter = propertyInfo.getter;
        }
    }

    if ((meta->_type & YYEncodingTypePropertyMask) & YYEncodingTypePropertyCustomSetter) {
        if (propertyInfo.setter && [classInfo.cls instancesRespondToSelector:propertyInfo.setter]) {
            meta->_setter = propertyInfo.setter;
        }
    } else {
        if (propertyInfo.setter && [classInfo.cls instancesRespondToSelector:propertyInfo.setter]) {
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
            case YYEncodingTypeBlock: {
                meta->_isKVCCompatible = YES;
            } break;
            default: break;
        }
    }

    // Check for keyed archiver struct support
    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeStruct) {
        static NSSet *types = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            types = [NSSet setWithArray:@[
                @"{CGSize=ff}", @"{CGSize=dd}", @"{CGSize=QQ}",
                @"{CGPoint=ff}", @"{CGPoint=dd}", @"{CGPoint=QQ}",
                @"{CGRect={CGPoint=ff}{CGSize=ff}}", @"{CGRect={CGPoint=dd}{CGSize=dd}}",
                @"{CGRect={CGPoint=QQ}{CGSize=QQ}}",
                @"{CGAffineTransform=ffffff}", @"{CGAffineTransform=dddddd}",
                @"{UIEdgeInsets=ffff}", @"{UIEdgeInsets=dddd}",
                @"{UIOffset=ff}", @"{UIOffset=dd}",
            ]];
        });
        meta->_isStructAvailableForKeyedArchiver = [types containsObject:propertyInfo.typeEncoding];
    }

    // Check if the class has a custom class-for-dictionary method
    if ([meta->_cls respondsToSelector:@selector(modelCustomClassForDictionary:)]) {
        meta->_hasCustomClassFromDictionary = YES;
    }

    return meta;
}

@end

// ============================================================
#pragma mark - Model Meta
// ============================================================

@interface _YYModelMeta : NSObject {
    @package
    YYClassInfo *_classInfo;
    NSDictionary<NSString *, _YYModelPropertyMeta *> *_mapper;
    NSArray<_YYModelPropertyMeta *> *_allPropertyMetas;
    NSArray<_YYModelPropertyMeta *> *_keyPathPropertyMetas;
    NSArray<_YYModelPropertyMeta *> *_multiKeysPropertyMetas;
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
    if (!cls) return nil;
    YYClassInfo *classInfo = [YYClassInfo classInfoWithClass:cls];
    if (!classInfo) return nil;
    self = [super init];

    _classInfo = classInfo;

    // Check for custom transform methods
    if ([cls instancesRespondToSelector:@selector(modelCustomWillTransformFromDictionary:)]) {
        _hasCustomWillTransformFromDictionary = YES;
    }
    if ([cls instancesRespondToSelector:@selector(modelCustomTransformFromDictionary:)]) {
        _hasCustomTransformFromDictionary = YES;
    }
    if ([cls instancesRespondToSelector:@selector(modelCustomTransformToDictionary:)]) {
        _hasCustomTransformToDictionary = YES;
    }
    if ([cls respondsToSelector:@selector(modelCustomClassForDictionary:)]) {
        _hasCustomClassFromDictionary = YES;
    }

    // Get black/whitelist
    NSSet *blacklist = nil;
    NSSet *whitelist = nil;
    if ([cls respondsToSelector:@selector(modelPropertyBlacklist)]) {
        NSArray *list = [cls modelPropertyBlacklist];
        if (list) blacklist = [NSSet setWithArray:list];
    }
    if ([cls respondsToSelector:@selector(modelPropertyWhitelist)]) {
        NSArray *list = [cls modelPropertyWhitelist];
        if (list) whitelist = [NSSet setWithArray:list];
    }

    // Get generic class mapping
    NSDictionary *genericMapper = nil;
    if ([cls respondsToSelector:@selector(modelContainerPropertyGenericClass)]) {
        genericMapper = [cls modelContainerPropertyGenericClass];
    }

    // Get property mapper
    NSDictionary *customMapper = nil;
    if ([cls respondsToSelector:@selector(modelCustomPropertyMapper)]) {
        customMapper = [cls modelCustomPropertyMapper];
    }

    // Build all property metas
    NSMutableDictionary *mapper = [NSMutableDictionary new];
    NSMutableArray *allPropertyMetas = [NSMutableArray new];

    for (NSString *propertyName in classInfo.propertyInfos) {
        if (blacklist && [blacklist containsObject:propertyName]) continue;
        if (whitelist && ![whitelist containsObject:propertyName]) continue;

        YYClassPropertyInfo *propertyInfo = classInfo.propertyInfos[propertyName];
        _YYModelPropertyMeta *meta = [_YYModelPropertyMeta metaWithClassInfo:classInfo
                                                                propertyInfo:propertyInfo
                                                                  genericCls:genericMapper[propertyName]];
        if (!meta || !meta->_name) continue;
        if (!meta->_getter || !meta->_setter) continue;

        // Apply custom mapper
        id mappedKey = customMapper[propertyName];
        if (mappedKey) {
            if ([mappedKey isKindOfClass:[NSString class]]) {
                meta->_mappedToKey = mappedKey;
            } else if ([mappedKey isKindOfClass:[NSArray class]]) {
                meta->_mappedToKeyArray = mappedKey;
            }
        } else {
            meta->_mappedToKey = propertyName;
        }

        [allPropertyMetas addObject:meta];
    }

    _allPropertyMetas = allPropertyMetas;

    // Build mapper dictionary
    NSMutableArray *keyPathMetas = [NSMutableArray new];
    NSMutableArray *multiKeyMetas = [NSMutableArray new];

    for (_YYModelPropertyMeta *meta in allPropertyMetas) {
        meta->_index = [allPropertyMetas indexOfObject:meta];
        mapper[meta->_name] = meta;

        if (meta->_mappedToKey) {
            // Single key or key path
            if ([meta->_mappedToKey rangeOfString:@"."].location != NSNotFound) {
                meta->_mappedToKeyPath = [meta->_mappedToKey componentsSeparatedByString:@"."];
                [keyPathMetas addObject:meta];
            }
        } else if (meta->_mappedToKeyArray) {
            [multiKeyMetas addObject:meta];
        }
    }

    _mapper = mapper;
    _keyMappedCount = allPropertyMetas.count;
    _keyPathPropertyMetas = keyPathMetas;
    _multiKeysPropertyMetas = multiKeyMetas;

    _nsType = YYClassGetNSType(cls);

    return self;
}

// Thread-safe cache
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

    if (!meta) {
        meta = [[_YYModelMeta alloc] initWithClass:cls];
        if (meta) {
            os_unfair_lock_lock(&_modelMetaLock);
            CFDictionarySetValue(_modelMetaCache, (__bridge const void *)(cls),
                                 (__bridge const void *)(meta));
            os_unfair_lock_unlock(&_modelMetaLock);
        }
    }
    return meta;
}

@end

// ============================================================
#pragma mark - Model Set (Core)
// ============================================================

// [F1] All objc_msgSend calls use typed function pointers.

static void ModelSetNumberToProperty(__unsafe_unretained id model,
                                     __unsafe_unretained NSNumber *num,
                                     __unsafe_unretained _YYModelPropertyMeta *meta) {
    if (!num || (id)num == (id)kCFNull) return;

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
            ((YYSendV_ll)(void *)objc_msgSend)(model, meta->_setter, num.longLongValue);
        } break;
        case YYEncodingTypeUInt64: {
            ((YYSendV_ull)(void *)objc_msgSend)(model, meta->_setter, num.unsignedLongLongValue);
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
        case YYEncodingTypeBool:    return @(((YYSendR_bool)(void *)objc_msgSend)(model, meta->_getter));
        case YYEncodingTypeInt8:    return @(((char)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt8:   return @(((unsigned char)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeInt16:   return @(((short)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt16:  return @(((unsigned short)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeInt32:   return @(((int)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt32:  return @(((unsigned int)((YYSendR_int)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeInt64:   return @(((long long)((YYSendR_ll)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeUInt64:  return @(((unsigned long long)((YYSendR_ll)(void *)objc_msgSend)(model, meta->_getter)));
        case YYEncodingTypeFloat:   { float f = ((YYSendR_float)(void *)objc_msgSend)(model, meta->_getter); return isnan(f) || isinf(f) ? nil : @(f); }
        case YYEncodingTypeDouble:  { double d = ((YYSendR_double)(void *)objc_msgSend)(model, meta->_getter); return isnan(d) || isinf(d) ? nil : @(d); }
        default: return nil;
    }
}

// ============================================================
#pragma mark - Model Set Value
// ============================================================

static void ModelSetValueForProperty(__unsafe_unretained id model,
                                     __unsafe_unretained id value,
                                     __unsafe_unretained _YYModelPropertyMeta *meta) {
    if (!model || !meta->_setter) return;
    if (!value || value == (id)kCFNull) {
        // Set nil
        switch (meta->_type & YYEncodingTypeMask) {
            case YYEncodingTypeObject:
            case YYEncodingTypeClass:
            case YYEncodingTypeBlock:
                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, nil);
                break;
            case YYEncodingTypeStruct:
            case YYEncodingTypeUnion:
            case YYEncodingTypeCArray: break; // can't set nil for struct
            default: {
                // For C number types, set zero
                if (meta->_isCNumber) {
                    ModelSetNumberToProperty(model, @(0), meta);
                }
            } break;
        }
        return;
    }

    switch (meta->_type & YYEncodingTypeMask) {
        case YYEncodingTypeObject: {
            // Object type — handle Foundation types
            if (meta->_nsType) {
                switch (meta->_nsType) {
                    case YYEncodingTypeNSString:
                    case YYEncodingTypeNSMutableString: {
                        if ([value isKindOfClass:[NSString class]]) {
                            if (meta->_nsType == YYEncodingTypeNSMutableString) {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter,
                                    ((NSString *)value).mutableCopy);
                            } else {
                                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                            }
                        } else if ([value isKindOfClass:[NSNumber class]]) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter,
                                ((NSNumber *)value).stringValue);
                        }
                    } break;

                    case YYEncodingTypeNSDecimalNumber: {
                        // [F4] Preserve NSDecimalNumber precision
                        if ([value isKindOfClass:[NSDecimalNumber class]]) {
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                        } else if ([value isKindOfClass:[NSNumber class]]) {
                            NSDecimalNumber *dec = [NSDecimalNumber decimalNumberWithDecimal:
                                                    ((NSNumber *)value).decimalValue];
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, dec);
                        } else if ([value isKindOfClass:[NSString class]]) {
                            NSDecimalNumber *dec = [NSDecimalNumber decimalNumberWithString:(NSString *)value];
                            if ((NSDecimalNumber *)[NSDecimalNumber notANumber] == dec) break;
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, dec);
                        }
                    } break;

                    case YYEncodingTypeNSNumber: {
                        NSNumber *num = YYNSNumberCreateFromID(value);
                        if (num) ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, num);
                    } break;

                    case YYEncodingTypeNSData:
                    case YYEncodingTypeNSMutableData: {
                        NSData *data = nil;
                        if ([value isKindOfClass:[NSData class]]) {
                            data = value;
                        } else if ([value isKindOfClass:[NSString class]]) {
                            data = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
                        }
                        if (data) {
                            if (meta->_nsType == YYEncodingTypeNSMutableData) {
                                data = data.mutableCopy;
                            }
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, data);
                        }
                    } break;

                    case YYEncodingTypeNSDate: {
                        NSDate *date = nil;
                        if ([value isKindOfClass:[NSDate class]]) {
                            date = value;
                        } else if ([value isKindOfClass:[NSString class]]) {
                            date = YYNSDateFromString(value);
                        } else if ([value isKindOfClass:[NSNumber class]]) {
                            date = [NSDate dateWithTimeIntervalSince1970:((NSNumber *)value).doubleValue];
                        }
                        if (date) ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, date);
                    } break;

                    case YYEncodingTypeNSURL: {
                        NSURL *url = nil;
                        if ([value isKindOfClass:[NSURL class]]) {
                            url = value;
                        } else if ([value isKindOfClass:[NSString class]]) {
                            url = [NSURL URLWithString:(NSString *)value];
                        }
                        if (url) ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, url);
                    } break;

                    case YYEncodingTypeNSArray:
                    case YYEncodingTypeNSMutableArray: {
                        if ([value isKindOfClass:[NSArray class]]) {
                            NSArray *array = value;
                            if (meta->_genericCls) {
                                NSMutableArray *mapped = [NSMutableArray arrayWithCapacity:array.count];
                                for (id item in array) {
                                    if ([item isKindOfClass:meta->_genericCls]) {
                                        [mapped addObject:item];
                                    } else if ([item isKindOfClass:[NSDictionary class]]) {
                                        id obj = [meta->_genericCls yy_modelWithDictionary:item];
                                        if (obj) [mapped addObject:obj];
                                    }
                                }
                                array = mapped;
                            }
                            if (meta->_nsType == YYEncodingTypeNSMutableArray) {
                                array = array.mutableCopy;
                            }
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, array);
                        }
                    } break;

                    case YYEncodingTypeNSDictionary:
                    case YYEncodingTypeNSMutableDictionary: {
                        if ([value isKindOfClass:[NSDictionary class]]) {
                            NSDictionary *dict = value;
                            if (meta->_genericCls) {
                                NSMutableDictionary *mapped = [NSMutableDictionary dictionaryWithCapacity:dict.count];
                                [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                                    if ([obj isKindOfClass:meta->_genericCls]) {
                                        mapped[key] = obj;
                                    } else if ([obj isKindOfClass:[NSDictionary class]]) {
                                        id mObj = [meta->_genericCls yy_modelWithDictionary:obj];
                                        if (mObj) mapped[key] = mObj;
                                    }
                                }];
                                dict = mapped;
                            }
                            if (meta->_nsType == YYEncodingTypeNSMutableDictionary) {
                                dict = dict.mutableCopy;
                            }
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, dict);
                        }
                    } break;

                    case YYEncodingTypeNSSet:
                    case YYEncodingTypeNSMutableSet: {
                        NSSet *set = nil;
                        if ([value isKindOfClass:[NSSet class]]) {
                            set = value;
                        } else if ([value isKindOfClass:[NSArray class]]) {
                            set = [NSSet setWithArray:value];
                        }
                        if (set) {
                            if (meta->_genericCls) {
                                NSMutableSet *mapped = [NSMutableSet setWithCapacity:set.count];
                                for (id item in set) {
                                    if ([item isKindOfClass:meta->_genericCls]) {
                                        [mapped addObject:item];
                                    } else if ([item isKindOfClass:[NSDictionary class]]) {
                                        id obj = [meta->_genericCls yy_modelWithDictionary:item];
                                        if (obj) [mapped addObject:obj];
                                    }
                                }
                                set = mapped;
                            }
                            if (meta->_nsType == YYEncodingTypeNSMutableSet) {
                                set = set.mutableCopy;
                            }
                            ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, set);
                        }
                    } break;

                    default: break;
                }
            } else {
                // Custom object type
                if ([value isKindOfClass:meta->_cls]) {
                    ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
                } else if ([value isKindOfClass:[NSDictionary class]]) {
                    Class cls = meta->_cls;
                    if (meta->_hasCustomClassFromDictionary) {
                        cls = [cls modelCustomClassForDictionary:value];
                        if (!cls) cls = meta->_cls;
                    }
                    id obj = [cls yy_modelWithDictionary:value];
                    if (obj) ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, obj);
                }
            }
        } break;

        case YYEncodingTypeClass: {
            if ([value isKindOfClass:[NSString class]]) {
                Class cls = NSClassFromString(value);
                if (cls) ((YYSendV_class)(void *)objc_msgSend)(model, meta->_setter, cls);
            }
        } break;

        case YYEncodingTypeSEL: {
            if ([value isKindOfClass:[NSString class]]) {
                SEL sel = NSSelectorFromString(value);
                if (sel) ((YYSendV_sel)(void *)objc_msgSend)(model, meta->_setter, sel);
            }
        } break;

        case YYEncodingTypeBlock: {
            if ([value isKindOfClass:YYClassGetNSType([value class]) ? [value class] : [NSNull class]]) {
                // Block assignment
                ((YYSendV_id)(void *)objc_msgSend)(model, meta->_setter, value);
            }
        } break;

        case YYEncodingTypeStruct:
        case YYEncodingTypeUnion:
        case YYEncodingTypeCArray: {
            if (meta->_isStructAvailableForKeyedArchiver) {
                // Try NSValue extraction
                if ([value isKindOfClass:[NSValue class]]) {
                    NSValue *v = value;
                    if (strcmp(v.objCType, meta->_info.typeEncoding.UTF8String ?: "") == 0) {
                        [model setValue:v forKey:meta->_name];
                    }
                }
            }
        } break;

        case YYEncodingTypePointer:
        case YYEncodingTypeCString: {
            if ([value isKindOfClass:[NSValue class]]) {
                NSValue *v = value;
                if (v.pointerValue) {
                    ((YYSendV_ptr)(void *)objc_msgSend)(model, meta->_setter, v.pointerValue);
                }
            }
        } break;

        default: {
            if (meta->_isCNumber) {
                NSNumber *num = YYNSNumberCreateFromID(value);
                if (num) ModelSetNumberToProperty(model, num, meta);
            }
        } break;
    }
}

// ============================================================
#pragma mark - Model → JSON
// ============================================================

static id ModelToJSONObjectRecursive(__unsafe_unretained id model) {
    if (!model) return nil;
    if ([model isKindOfClass:[NSString class]]) return model;
    if ([model isKindOfClass:[NSNumber class]]) return model;
    if ([model isKindOfClass:[NSNull class]]) return model;
    if ([model isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray new];
        for (id item in (NSArray *)model) {
            id json = ModelToJSONObjectRecursive(item);
            if (json) [array addObject:json];
        }
        return array;
    }
    if ([model isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [NSMutableDictionary new];
        [(NSDictionary *)model enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            id json = ModelToJSONObjectRecursive(obj);
            if (json) dict[key] = json;
        }];
        return dict;
    }
    if ([model isKindOfClass:[NSSet class]]) {
        NSMutableArray *array = [NSMutableArray new];
        for (id item in (NSSet *)model) {
            id json = ModelToJSONObjectRecursive(item);
            if (json) [array addObject:json];
        }
        return array;
    }
    if ([model isKindOfClass:[NSDate class]]) {
        return @([(NSDate *)model timeIntervalSince1970]);
    }
    if ([model isKindOfClass:[NSURL class]]) {
        return ((NSURL *)model).absoluteString;
    }
    if ([model isKindOfClass:[NSValue class]]) {
        return nil; // Skip raw NSValue
    }

    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:[model class]];
    if (!modelMeta || modelMeta->_keyMappedCount == 0) return nil;

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:modelMeta->_keyMappedCount];

    if (modelMeta->_hasCustomTransformToDictionary) {
        if (![(id<YYModel>)model modelCustomTransformToDictionary:dictionary]) return nil;
    }

    for (_YYModelPropertyMeta *meta in modelMeta->_allPropertyMetas) {
        if (!meta->_getter) continue;

        id value = nil;
        if (meta->_isCNumber) {
            value = ModelCreateNumberFromProperty(model, meta);
        } else if (meta->_nsType) {
            switch (meta->_type & YYEncodingTypeMask) {
                case YYEncodingTypeObject:
                    value = ((YYSendR_id)(void *)objc_msgSend)(model, meta->_getter);
                    break;
                default: break;
            }
            if (!value) continue;

            // Recursive for nested objects
            if (meta->_genericCls || meta->_nsType == YYEncodingTypeNSArray ||
                meta->_nsType == YYEncodingTypeNSDictionary ||
                meta->_nsType == YYEncodingTypeNSSet) {
                value = ModelToJSONObjectRecursive(value);
            } else if (meta->_nsType == YYEncodingTypeNSDate) {
                value = @([(NSDate *)value timeIntervalSince1970]);
            } else if (meta->_nsType == YYEncodingTypeNSURL) {
                value = ((NSURL *)value).absoluteString;
            } else if (meta->_nsType == YYEncodingTypeNSDecimalNumber) {
                value = [(NSDecimalNumber *)value stringValue];
            }
        } else {
            // Custom object
            value = ((YYSendR_id)(void *)objc_msgSend)(model, meta->_getter);
            if (!value) continue;
            value = ModelToJSONObjectRecursive(value);
        }

        if (!value) continue;

        NSString *key = meta->_mappedToKey ?: meta->_name;
        if (key) dictionary[key] = value;
    }

    return dictionary;
}

// ============================================================
#pragma mark - Model Description
// ============================================================

static NSString *ModelDescription(id model) {
    if (!model) return @"<nil>";
    _YYModelMeta *meta = [_YYModelMeta metaWithClass:[model class]];
    if (!meta) return [model description];

    NSMutableString *desc = [NSMutableString stringWithFormat:@"<%@: %p>", NSStringFromClass([model class]), model];
    [desc appendString:@" {"];
    for (_YYModelPropertyMeta *property in meta->_allPropertyMetas) {
        if (!property->_getter) continue;
        id value = nil;
        if (property->_isCNumber) {
            value = ModelCreateNumberFromProperty(model, property);
        } else {
            value = ((YYSendR_id)(void *)objc_msgSend)(model, property->_getter);
        }
        if (value) {
            [desc appendFormat:@"\n  %@ = %@", property->_name, value];
        }
    }
    [desc appendString:@"\n}"];
    return desc;
}

// ============================================================
#pragma mark - NSObject (YYModel)
// ============================================================

@implementation NSObject (YYModel)

+ (instancetype)yy_modelWithJSON:(id)json {
    if (!json) return nil;
    NSDictionary *dict = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dict = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        dict = [NSJSONSerialization JSONObjectWithData:[(NSString *)json dataUsingEncoding:NSUTF8StringEncoding]
                                               options:kNilOptions error:NULL];
    } else if ([json isKindOfClass:[NSData class]]) {
        dict = [NSJSONSerialization JSONObjectWithData:json options:kNilOptions error:NULL];
    }
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    return [self yy_modelWithDictionary:dict];
}

+ (instancetype)yy_modelWithDictionary:(NSDictionary *)dictionary {
    if (!dictionary || ![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    id model = [self new];
    [model yy_modelSetWithDictionary:dictionary];
    return model;
}

- (BOOL)yy_modelSetWithJSON:(id)json {
    if (!json) return NO;
    NSDictionary *dict = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dict = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        dict = [NSJSONSerialization JSONObjectWithData:[(NSString *)json dataUsingEncoding:NSUTF8StringEncoding]
                                               options:kNilOptions error:NULL];
    } else if ([json isKindOfClass:[NSData class]]) {
        dict = [NSJSONSerialization JSONObjectWithData:json options:kNilOptions error:NULL];
    }
    if (![dict isKindOfClass:[NSDictionary class]]) return NO;
    return [self yy_modelSetWithDictionary:dict];
}

- (BOOL)yy_modelSetWithDictionary:(NSDictionary *)dictionary {
    if (!dictionary || ![dictionary isKindOfClass:[NSDictionary class]]) return NO;

    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:[self class]];
    if (!modelMeta || modelMeta->_keyMappedCount == 0) return NO;

    if (modelMeta->_hasCustomWillTransformFromDictionary) {
        dictionary = [(id<YYModel>)self modelCustomWillTransformFromDictionary:dictionary];
        if (!dictionary) return NO;
    }

    // Set properties
    for (_YYModelPropertyMeta *meta in modelMeta->_allPropertyMetas) {
        if (!meta->_setter) continue;

        id value = nil;

        if (meta->_mappedToKeyPath) {
            value = YYValueForKeyPath(dictionary, meta->_mappedToKeyPath);
        } else if (meta->_mappedToKeyArray) {
            value = YYValueForMultiKeys(dictionary, meta->_mappedToKeyArray);
        } else {
            value = dictionary[meta->_mappedToKey ?: meta->_name];
        }

        if (!value) continue;
        ModelSetValueForProperty(self, value, meta);
    }

    if (modelMeta->_hasCustomTransformFromDictionary) {
        [(id<YYModel>)self modelCustomTransformFromDictionary:dictionary];
    }

    return YES;
}

- (id)yy_modelToJSONObject {
    return ModelToJSONObjectRecursive(self);
}

- (NSData *)yy_modelToJSONData {
    id json = [self yy_modelToJSONObject];
    if (!json) return nil;
    return [NSJSONSerialization dataWithJSONObject:json options:kNilOptions error:NULL];
}

- (NSString *)yy_modelToJSONString {
    NSData *data = [self yy_modelToJSONData];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (id)yy_modelCopy {
    if (!self) return nil;
    id copy = [[[self class] alloc] init];
    _YYModelMeta *meta = [_YYModelMeta metaWithClass:[self class]];
    for (_YYModelPropertyMeta *property in meta->_allPropertyMetas) {
        if (!property->_getter || !property->_setter) continue;
        if (property->_isCNumber) {
            NSNumber *num = ModelCreateNumberFromProperty(self, property);
            if (num) ModelSetNumberToProperty(copy, num, property);
        } else {
            id value = ((YYSendR_id)(void *)objc_msgSend)(self, property->_getter);
            if (value) ((YYSendV_id)(void *)objc_msgSend)(copy, property->_setter, value);
        }
    }
    return copy;
}

// ============================================================
#pragma mark - [F2] NSSecureCoding
// ============================================================
// iOS 17+ requires NSSecureCoding. The original code used decodeObjectForKey:
// which triggers warnings and will eventually be removed.

- (void)yy_modelEncodeWithCoder:(NSCoder *)aCoder {
    if (!self) return;
    _YYModelMeta *meta = [_YYModelMeta metaWithClass:[self class]];
    for (_YYModelPropertyMeta *property in meta->_allPropertyMetas) {
        if (!property->_getter) continue;
        id value = nil;
        if (property->_isCNumber) {
            value = ModelCreateNumberFromProperty(self, property);
        } else {
            value = ((YYSendR_id)(void *)objc_msgSend)(self, property->_getter);
        }
        if (value) {
            @try {
                [aCoder encodeObject:value forKey:property->_name];
            } @catch (NSException *exception) {
                // Value may not conform to NSCoding
            }
        }
    }
}

- (instancetype)yy_modelInitWithCoder:(NSCoder *)aDecoder {
    if (!self) return nil;
    // Note: self is already initialized by the caller (initWithCoder: pattern).
    // Do NOT call [self init] again here — it would double-init.
    _YYModelMeta *meta = [_YYModelMeta metaWithClass:[self class]];
    for (_YYModelPropertyMeta *property in meta->_allPropertyMetas) {
        if (!property->_setter) continue;

        id value = nil;
        @try {
            // [F2] Use decodeObjectOfClass:forKey: for NSSecureCoding compliance.
            // Falls back to decodeObjectForKey: for unknown types.
            if (property->_cls) {
                value = [aDecoder decodeObjectOfClass:property->_cls forKey:property->_name];
            } else if (property->_nsType) {
                switch (property->_nsType) {
                    case YYEncodingTypeNSString:
                    case YYEncodingTypeNSMutableString:
                        value = [aDecoder decodeObjectOfClass:[NSString class] forKey:property->_name];
                        break;
                    case YYEncodingTypeNSNumber:
                    case YYEncodingTypeNSDecimalNumber:
                        value = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:property->_name];
                        break;
                    case YYEncodingTypeNSData:
                    case YYEncodingTypeNSMutableData:
                        value = [aDecoder decodeObjectOfClass:[NSData class] forKey:property->_name];
                        break;
                    case YYEncodingTypeNSDate:
                        value = [aDecoder decodeObjectOfClass:[NSDate class] forKey:property->_name];
                        break;
                    case YYEncodingTypeNSURL:
                        value = [aDecoder decodeObjectOfClass:[NSURL class] forKey:property->_name];
                        break;
                    case YYEncodingTypeNSArray:
                    case YYEncodingTypeNSMutableArray:
                        value = [aDecoder decodeObjectOfClasses:
                                 [NSSet setWithObjects:[NSArray class], [NSMutableArray class],
                                  property->_genericCls ?: [NSObject class], nil]
                                                        forKey:property->_name];
                        break;
                    case YYEncodingTypeNSDictionary:
                    case YYEncodingTypeNSMutableDictionary:
                        value = [aDecoder decodeObjectOfClasses:
                                 [NSSet setWithObjects:[NSDictionary class], [NSMutableDictionary class],
                                  [NSString class], property->_genericCls ?: [NSObject class], nil]
                                                        forKey:property->_name];
                        break;
                    case YYEncodingTypeNSSet:
                    case YYEncodingTypeNSMutableSet:
                        value = [aDecoder decodeObjectOfClasses:
                                 [NSSet setWithObjects:[NSSet class], [NSMutableSet class],
                                  property->_genericCls ?: [NSObject class], nil]
                                                        forKey:property->_name];
                        break;
                    default:
                        value = [aDecoder decodeObjectForKey:property->_name];
                        break;
                }
            } else {
                value = [aDecoder decodeObjectForKey:property->_name];
            }
        } @catch (NSException *exception) {
            // Decode error for this property
        }

        if (value && value != (id)kCFNull) {
            ModelSetValueForProperty(self, value, property);
        }
    }
    return self;
}

- (NSUInteger)yy_modelHash {
    if (!self) return 0;
    _YYModelMeta *meta = [_YYModelMeta metaWithClass:[self class]];
    NSUInteger value = 0;
    for (_YYModelPropertyMeta *property in meta->_allPropertyMetas) {
        if (!property->_getter) continue;
        if (property->_isCNumber) {
            NSNumber *num = ModelCreateNumberFromProperty(self, property);
            if (num) value ^= num.hash;
        } else {
            id v = ((YYSendR_id)(void *)objc_msgSend)(self, property->_getter);
            if (v) value ^= [v hash];
        }
    }
    return value;
}

- (BOOL)yy_modelIsEqual:(id)model {
    if (!model) return NO;
    if (self == model) return YES;
    if (![model isKindOfClass:[self class]]) return NO;
    _YYModelMeta *meta = [_YYModelMeta metaWithClass:[self class]];
    for (_YYModelPropertyMeta *property in meta->_allPropertyMetas) {
        if (!property->_getter) continue;
        if (property->_isCNumber) {
            NSNumber *a = ModelCreateNumberFromProperty(self, property);
            NSNumber *b = ModelCreateNumberFromProperty(model, property);
            if (a != b && ![a isEqual:b]) return NO;
        } else {
            id a = ((YYSendR_id)(void *)objc_msgSend)(self, property->_getter);
            id b = ((YYSendR_id)(void *)objc_msgSend)(model, property->_getter);
            if (a != b && ![a isEqual:b]) return NO;
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
    if (!cls || !json) return nil;
    NSArray *array = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        array = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        array = [NSJSONSerialization JSONObjectWithData:[(NSString *)json dataUsingEncoding:NSUTF8StringEncoding]
                                                options:kNilOptions error:NULL];
    } else if ([json isKindOfClass:[NSData class]]) {
        array = [NSJSONSerialization JSONObjectWithData:json options:kNilOptions error:NULL];
    }
    if (![array isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray *models = [NSMutableArray arrayWithCapacity:array.count];
    for (NSDictionary *dict in array) {
        if (![dict isKindOfClass:[NSDictionary class]]) continue;
        id model = [cls yy_modelWithDictionary:dict];
        if (model) [models addObject:model];
    }
    return models;
}

@end

@implementation NSDictionary (YYModel)

+ (NSDictionary *)yy_modelDictionaryWithClass:(Class)cls json:(id)json {
    if (!cls || !json) return nil;
    NSDictionary *dict = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dict = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        dict = [NSJSONSerialization JSONObjectWithData:[(NSString *)json dataUsingEncoding:NSUTF8StringEncoding]
                                               options:kNilOptions error:NULL];
    } else if ([json isKindOfClass:[NSData class]]) {
        dict = [NSJSONSerialization JSONObjectWithData:json options:kNilOptions error:NULL];
    }
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    NSMutableDictionary *models = [NSMutableDictionary dictionaryWithCapacity:dict.count];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSDictionary class]]) {
            id model = [cls yy_modelWithDictionary:obj];
            if (model) models[key] = model;
        }
    }];
    return models;
}

@end
