//
//  YYModelTestModels.m
//  YYModel Test Demo
//

#import "YYModelTestModels.h"

// ============================================================
#pragma mark - Geo
// ============================================================

@implementation Geo
@end

// ============================================================
#pragma mark - Address
// ============================================================

@implementation Address
@end

// ============================================================
#pragma mark - Company
// ============================================================

@implementation Company
@end

// ============================================================
#pragma mark - User
// ============================================================

@implementation User

// T5: Key-path mapping — map "companyName" to "company.name"
// T6: Multi-key fallback — try "homepage", then "website", then "url"
+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
        @"userId"      : @"id",
        @"companyName" : @"company.name",       // T5: key-path
        @"homepage"    : @[@"website", @"homepage", @"url"], // T6: multi-key
    };
}

// T8: Custom transform — uppercase the email
- (BOOL)modelCustomTransformFromDictionary:(NSDictionary *)dictionary {
    if ([self.email isKindOfClass:[NSString class]]) {
        _email = [self.email uppercaseString];
    }
    return YES;
}

// NSSecureCoding — delegates to YYModel's category methods
+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        [self yy_modelInitWithCoder:coder];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [self yy_modelEncodeWithCoder:coder];
}

@end

// ============================================================
#pragma mark - Post
// ============================================================

@implementation Post

+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
        @"postId" : @"id",
    };
}

@end

// ============================================================
#pragma mark - YYComment
// ============================================================

@implementation YYComment

+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
        @"commentId" : @"id",
    };
}

@end

// ============================================================
#pragma mark - Album
// ============================================================

@implementation Album

+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
        @"albumId" : @"id",
    };
}

@end

// ============================================================
#pragma mark - Photo
// ============================================================

@implementation Photo

+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
        @"photoId" : @"id",
    };
}

@end

// ============================================================
#pragma mark - Todo
// ============================================================

@implementation Todo

+ (NSDictionary *)modelCustomPropertyMapper {
    return @{
        @"todoId" : @"id",
    };
}

// T7: Blacklist internalNote from JSON parsing
+ (NSArray *)modelPropertyBlacklist {
    return @[@"internalNote"];
}

@end

// ============================================================
#pragma mark - PrecisionModel
// ============================================================

@implementation PrecisionModel
@end
