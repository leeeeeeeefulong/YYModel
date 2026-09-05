//
//  YYModel.h
//  YYModel <https://github.com/ibireme/YYModel>
//
//  iOS 27 Compatible — 2026.09 Patch
//

#import <Foundation/Foundation.h>

#if __has_include(<YYModel/YYModel.h>)
FOUNDATION_EXPORT double YYModelVersionNumber;
FOUNDATION_EXPORT const unsigned char YYModelVersionString[];
#import <YYModel/NSObject+YYModel.h>
#import <YYModel/YYClassInfo.h>
#else
#import "NSObject+YYModel.h"
#import "YYClassInfo.h"
#endif
