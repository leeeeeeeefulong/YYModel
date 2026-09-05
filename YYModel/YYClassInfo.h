//
//  YYClassInfo.h
//  YYModel <https://github.com/ibireme/YYModel>
//
//  Created by ibireme on 15/5/9.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//
//  Modern iOS Compatible — 2026.09 Patch
//  Changes:
//  - Added NS_ASSUME_NONNULL annotations
//  - Fixed YYEncodingType enum for 64-bit correctness
//  - Added YYClassPropertyInfo.isSwift property
//  - Thread-safe cache using os_unfair_lock (iOS 10.0+)
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Type encoding's type.
 */
typedef NS_OPTIONS(NSUInteger, YYEncodingType) {
    YYEncodingTypeMask       = 0xFF,
    YYEncodingTypeUnknown    = 0,
    YYEncodingTypeVoid       = 1,
    YYEncodingTypeBool       = 2,
    YYEncodingTypeInt8       = 3,   // char / BOOL (legacy)
    YYEncodingTypeUInt8      = 4,   // unsigned char
    YYEncodingTypeInt16      = 5,   // short
    YYEncodingTypeUInt16     = 6,   // unsigned short
    YYEncodingTypeInt32      = 7,   // int
    YYEncodingTypeUInt32     = 8,   // unsigned int
    YYEncodingTypeInt64      = 9,   // long long (also long on arm64)
    YYEncodingTypeUInt64     = 10,  // unsigned long long
    YYEncodingTypeFloat      = 11,  // float
    YYEncodingTypeDouble     = 12,  // double
    YYEncodingTypeLongDouble = 13,  // long double
    YYEncodingTypeObject     = 14,  // id
    YYEncodingTypeClass      = 15,  // Class
    YYEncodingTypeSEL        = 16,  // SEL
    YYEncodingTypeBlock      = 17,  // block
    YYEncodingTypePointer    = 18,  // void*
    YYEncodingTypeStruct     = 19,  // struct
    YYEncodingTypeUnion      = 20,  // union
    YYEncodingTypeCString    = 21,  // char*
    YYEncodingTypeCArray     = 22,  // char[10] (for example)

    YYEncodingTypeQualifierMask   = 0xFF00,
    YYEncodingTypeQualifierConst  = 1 << 8,
    YYEncodingTypeQualifierIn     = 1 << 9,
    YYEncodingTypeQualifierInout  = 1 << 10,
    YYEncodingTypeQualifierOut    = 1 << 11,
    YYEncodingTypeQualifierBycopy = 1 << 12,
    YYEncodingTypeQualifierByref  = 1 << 13,
    YYEncodingTypeQualifierOneway = 1 << 14,

    YYEncodingTypePropertyMask         = 0xFF0000,
    YYEncodingTypePropertyReadonly     = 1 << 16,
    YYEncodingTypePropertyCopy         = 1 << 17,
    YYEncodingTypePropertyRetain       = 1 << 18,
    YYEncodingTypePropertyNonatomic    = 1 << 19,
    YYEncodingTypePropertyWeak         = 1 << 20,
    YYEncodingTypePropertyCustomGetter = 1 << 21,
    YYEncodingTypePropertyCustomSetter = 1 << 22,
    YYEncodingTypePropertyDynamic      = 1 << 23,
};

/**
 Get the type from a Type-Encoding string.
 Uses NSGetSizeAndAlignment for correct 64-bit size handling.

 @param typeEncoding  A Type-Encoding string.
 @return The encoding type.
 */
YYEncodingType YYEncodingGetType(const char * _Nullable typeEncoding);


/**
 Instance variable information.
 */
@interface YYClassIvarInfo : NSObject
@property (nonatomic, assign, readonly) Ivar ivar;
@property (nonatomic, strong, readonly) NSString *name;
@property (nonatomic, assign, readonly) ptrdiff_t offset;
@property (nonatomic, strong, readonly, nullable) NSString *typeEncoding;
@property (nonatomic, assign, readonly) YYEncodingType type;

- (nullable instancetype)initWithIvar:(Ivar)ivar;
@end


/**
 Method information.
 */
@interface YYClassMethodInfo : NSObject
@property (nonatomic, assign, readonly) Method method;
@property (nonatomic, strong, readonly) NSString *name;
@property (nonatomic, assign, readonly) SEL sel;
@property (nonatomic, assign, readonly) IMP imp;
@property (nonatomic, strong, readonly, nullable) NSString *typeEncoding;
@property (nonatomic, strong, readonly, nullable) NSString *returnTypeEncoding;
@property (nullable, nonatomic, strong, readonly) NSArray<NSString *> *argumentTypeEncodings;

- (nullable instancetype)initWithMethod:(Method)method;
@end


/**
 Property information.
 */
@interface YYClassPropertyInfo : NSObject
@property (nonatomic, assign, readonly) objc_property_t property;
@property (nonatomic, strong, readonly) NSString *name;
@property (nonatomic, assign, readonly) YYEncodingType type;
@property (nonatomic, strong, readonly, nullable) NSString *typeEncoding;
@property (nonatomic, strong, readonly, nullable) NSString *ivarName;
@property (nullable, nonatomic, assign, readonly) Class cls;
@property (nullable, nonatomic, strong, readonly) NSArray<NSString *> *protocols;
@property (nonatomic, assign, readonly) SEL getter;
@property (nonatomic, assign, readonly) SEL setter;
@property (nonatomic, assign, readonly) BOOL isSwiftDynamic; // @objc dynamic in Swift

- (nullable instancetype)initWithProperty:(objc_property_t)property;
@end


/**
 Class information for a class.
 */
@interface YYClassInfo : NSObject
@property (nonatomic, assign, readonly) Class cls;
@property (nullable, nonatomic, assign, readonly) Class superCls;
@property (nullable, nonatomic, assign, readonly) Class metaCls;
@property (nonatomic, readonly) BOOL isMeta;
@property (nonatomic, strong, readonly) NSString *name;
@property (nullable, nonatomic, strong, readonly) YYClassInfo *superClassInfo;
@property (nullable, nonatomic, strong, readonly) NSDictionary<NSString *, YYClassIvarInfo *> *ivarInfos;
@property (nullable, nonatomic, strong, readonly) NSDictionary<NSString *, YYClassMethodInfo *> *methodInfos;
@property (nullable, nonatomic, strong, readonly) NSDictionary<NSString *, YYClassPropertyInfo *> *propertyInfos;

- (void)setNeedUpdate;
- (BOOL)needUpdate;

+ (nullable instancetype)classInfoWithClass:(Class)cls;
+ (nullable instancetype)classInfoWithClassName:(NSString *)className;

@end

NS_ASSUME_NONNULL_END
