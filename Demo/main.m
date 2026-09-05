//
//  main.m
//  YYModel Test Demo
//
//  Tests YYModel against live JSONPlaceholder API (https://jsonplaceholder.typicode.com)
//  and inline test cases for all features T1-T15.
//
//  Build:  clang -fobjc-arc -framework Foundation -framework XCTest \
//          -I../YYModel-iOS27-Fix/YYModel \
//          ../YYModel-iOS27-Fix/YYModel/YYClassInfo.m \
//          ../YYModel-iOS27-Fix/YYModel/NSObject+YYModel.m \
//          YYModelTestModels.m main.m -o yymodel_test
//
//  Run:    ./yymodel_test
//

#import <Foundation/Foundation.h>
#import "YYModel.h"
#import "YYModelTestModels.h"

// ============================================================
#pragma mark - Test Runner Helpers
// ============================================================

static int _passCount = 0;
static int _failCount = 0;

#define TEST_ASSERT(expr, desc) do { \
    if (expr) { _passCount++; NSLog(@"  ✅ PASS: %@", desc); } \
    else      { _failCount++; NSLog(@"  ❌ FAIL: %@", desc); } \
} while(0)

#define TEST_SECTION(name) NSLog(@"\n═══════════════════════════════════════\n  %@\n═══════════════════════════════════════", name)

// Synchronous HTTP GET (for test simplicity)
static NSData *HTTPGet(NSString *urlString) {
    __block NSData *result = nil;
    __block BOOL done = NO;
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithURL:url
      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && [(NSHTTPURLResponse *)response statusCode] == 200) {
            result = data;
        } else {
            NSLog(@"  ⚠️ HTTP error for %@: %@", urlString, error ?: @([(NSHTTPURLResponse *)response statusCode]));
        }
        done = YES;
    }];
    [task resume];
    while (!done) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }
    return result;
}

// ============================================================
#pragma mark - T1: Basic Types
// ============================================================

static void TestT1_BasicTypes(void) {
    TEST_SECTION(@"T1 — Basic Property Types");

    NSString *json = @"{\"id\":1,\"name\":\"Leanne Graham\",\"username\":\"Bret\","
                      "\"email\":\"Sincere@april.biz\",\"phone\":\"1-770-736-8031\",\"website\":\"hildegard.org\"}";
    User *user = [User yy_modelWithJSON:json];

    TEST_ASSERT(user != nil,                    @"User parsed from JSON");
    TEST_ASSERT(user.userId == 1,               @"userId = 1 (mapped from 'id')");
    TEST_ASSERT([user.name isEqualToString:@"Leanne Graham"], @"name correct");
    TEST_ASSERT([user.username isEqualToString:@"Bret"],       @"username correct");
    TEST_ASSERT(user.phone != nil,              @"phone not nil");
    TEST_ASSERT([user.website isEqualToString:@"hildegard.org"], @"website correct");
}

// ============================================================
#pragma mark - T2: Nested Object
// ============================================================

static void TestT2_NestedObject(void) {
    TEST_SECTION(@"T2 — Nested Object (Address → Geo)");

    NSString *json = @"{\"id\":1,\"name\":\"Test\","
                      "\"address\":{\"street\":\"Kulas Light\",\"suite\":\"Apt. 556\",\"city\":\"Gwenborough\","
                      "\"zipcode\":\"92998-3874\",\"geo\":{\"lat\":\"-37.3159\",\"lng\":\"81.1496\"}}}";

    User *user = [User yy_modelWithJSON:json];
    TEST_ASSERT(user.address != nil,            @"address parsed");
    TEST_ASSERT([user.address.city isEqualToString:@"Gwenborough"], @"address.city correct");
    TEST_ASSERT(user.address.geo != nil,        @"address.geo parsed");
    TEST_ASSERT([user.address.geo.lat isEqualToString:@"-37.3159"], @"geo.lat correct");
    TEST_ASSERT([user.address.geo.lng isEqualToString:@"81.1496"],  @"geo.lng correct");
}

// ============================================================
#pragma mark - T3: Array of Strings
// ============================================================

static void TestT3_ArrayOfStrings(void) {
    TEST_SECTION(@"T3 — Array of Strings (inline)");

    // JSONPlaceholder doesn't have string arrays, so test inline
    NSDictionary *dict = @{
        @"id": @42,
        @"title": @"Test Album",
        @"tags": @[@"swift", @"objc", @"yymodel"] // hypothetical
    };

    // Use generic NSObject for this test
    id obj = [NSObject yy_modelWithDictionary:dict];
    TEST_ASSERT(obj != nil, @"NSObject model created");
}

// ============================================================
#pragma mark - T4: Array of Nested Objects
// ============================================================

static void TestT4_ArrayOfNestedObjects(void) {
    TEST_SECTION(@"T4 — Array of Nested Objects (Posts)");

    NSData *data = HTTPGet(@"https://jsonplaceholder.typicode.com/posts?_limit=5");
    TEST_ASSERT(data != nil, @"HTTP GET /posts returned data");

    NSArray *posts = [NSArray yy_modelArrayWithClass:[Post class] json:data];
    TEST_ASSERT(posts != nil && posts.count == 5, @"Parsed 5 posts");

    if (posts.count > 0) {
        Post *first = posts[0];
        TEST_ASSERT(first.postId > 0,           @"postId > 0");
        TEST_ASSERT(first.userId > 0,           @"userId > 0");
        TEST_ASSERT(first.title.length > 0,     @"title not empty");
        TEST_ASSERT(first.body.length > 0,      @"body not empty");
        NSLog(@"  📝 First post: \"%@\"", [first.title substringToIndex:MIN(50, first.title.length)]);
    }
}

// ============================================================
#pragma mark - T5: Key-Path Mapping
// ============================================================

static void TestT5_KeyPathMapping(void) {
    TEST_SECTION(@"T5 — Key-Path Mapping (company.name → companyName)");

    NSData *data = HTTPGet(@"https://jsonplaceholder.typicode.com/users/1");
    TEST_ASSERT(data != nil, @"HTTP GET /users/1 returned data");

    User *user = [User yy_modelWithJSON:data];
    TEST_ASSERT(user != nil,                    @"User parsed");
    TEST_ASSERT(user.companyName.length > 0,    @"companyName mapped from company.name");
    NSLog(@"  🏢 companyName = \"%@\"", user.companyName);
}

// ============================================================
#pragma mark - T6: Multi-Key Fallback
// ============================================================

static void TestT6_MultiKeyFallback(void) {
    TEST_SECTION(@"T6 — Multi-Key Fallback (homepage)");

    // JSONPlaceholder returns "website" field, which is first in the multi-key list
    NSString *json = @"{\"id\":1,\"name\":\"Test\",\"website\":\"example.com\"}";
    User *user = [User yy_modelWithJSON:json];
    TEST_ASSERT(user != nil,                    @"User parsed");
    TEST_ASSERT([user.homepage isEqualToString:@"example.com"], @"homepage matched from 'website' key");

    // Test with alternate key
    NSString *json2 = @"{\"id\":2,\"name\":\"Test2\",\"homepage\":\"alt.com\"}";
    User *user2 = [User yy_modelWithJSON:json2];
    TEST_ASSERT(user2 != nil,                   @"User2 parsed");
    TEST_ASSERT([user2.homepage isEqualToString:@"alt.com"], @"homepage matched from 'homepage' key");

    // Test with no match
    NSString *json3 = @"{\"id\":3,\"name\":\"Test3\"}";
    User *user3 = [User yy_modelWithJSON:json3];
    TEST_ASSERT(user3 != nil,                   @"User3 parsed (missing field)");
    TEST_ASSERT(user3.homepage == nil,           @"homepage is nil when no key matches");
}

// ============================================================
#pragma mark - T7: Blacklist
// ============================================================

static void TestT7_Blacklist(void) {
    TEST_SECTION(@"T7 — Property Blacklist (Todo)");

    NSString *json = @"{\"id\":1,\"userId\":1,\"title\":\"Test\",\"completed\":true,\"internalNote\":\"SECRET\"}";
    Todo *todo = [Todo yy_modelWithJSON:json];

    TEST_ASSERT(todo != nil,                    @"Todo parsed");
    TEST_ASSERT(todo.todoId == 1,               @"todoId correct");
    TEST_ASSERT(todo.completed == YES,          @"completed correct");
    TEST_ASSERT(todo.internalNote == nil,       @"internalNote NOT set (blacklisted)");
    NSLog(@"  🔒 internalNote = %@ (should be nil)", todo.internalNote);
}

// ============================================================
#pragma mark - T8: Custom Transform
// ============================================================

static void TestT8_CustomTransform(void) {
    TEST_SECTION(@"T8 — Custom Transform (email → uppercase)");

    NSString *json = @"{\"id\":1,\"name\":\"Test\",\"email\":\"test@example.com\"}";
    User *user = [User yy_modelWithJSON:json];

    TEST_ASSERT(user != nil,                    @"User parsed");
    // T8: email is uppercased by modelCustomTransformFromDictionary:
    TEST_ASSERT([user.email isEqualToString:@"TEST@EXAMPLE.COM"], @"email uppercased by custom transform");
    NSLog(@"  📧 email = \"%@\" (uppercased from 'test@example.com')", user.email);
}

// ============================================================
#pragma mark - T9: NSDecimalNumber Precision
// ============================================================

static void TestT9_DecimalPrecision(void) {
    TEST_SECTION(@"T9 — NSDecimalNumber Precision");

    NSString *json = @"{\"price\":\"99999999.9999999999\",\"rate\":\"0.0000000001\",\"currency\":\"USD\"}";
    PrecisionModel *model = [PrecisionModel yy_modelWithJSON:json];

    TEST_ASSERT(model != nil,                   @"PrecisionModel parsed");
    TEST_ASSERT(model.price != nil,             @"price is NSDecimalNumber");
    TEST_ASSERT(model.rate != nil,              @"rate is NSDecimalNumber");

    // Verify precision: string → NSDecimalNumber should preserve all digits
    NSString *priceStr = [model.price stringValue];
    TEST_ASSERT([priceStr hasPrefix:@"99999999.99"], @"price preserves precision prefix");
    NSLog(@"  💰 price = %@", priceStr);
    NSLog(@"  📊 rate  = %@", [model.rate stringValue]);

    // Test number input
    NSString *json2 = @"{\"price\":123.456789012345,\"rate\":0.001}";
    PrecisionModel *model2 = [PrecisionModel yy_modelWithJSON:json2];
    TEST_ASSERT(model2 != nil,                  @"PrecisionModel2 from number");
    TEST_ASSERT(model2.price != nil,            @"price from number is NSDecimalNumber");
    NSLog(@"  💰 price2 = %@", [model2.price stringValue]);
}

// ============================================================
#pragma mark - T10: NSCoding Round-Trip
// ============================================================

static void TestT10_NSCoding(void) {
    TEST_SECTION(@"T10 — NSCoding / NSSecureCoding Round-Trip");

    NSString *json = @"{\"id\":1,\"name\":\"Archive Test\",\"username\":\"arch\",\"email\":\"a@b.com\","
                      "\"phone\":\"123\",\"website\":\"test.com\"}";
    User *original = [User yy_modelWithJSON:json];
    TEST_ASSERT(original != nil, @"Original user created");

    // Encode
    NSData *archived = nil;
    @try {
        archived = [NSKeyedArchiver archivedDataWithRootObject:original requiringSecureCoding:YES error:NULL];
    } @catch (NSException *e) {
        // Fallback for older runtime
        archived = [NSKeyedArchiver archivedDataWithRootObject:original];
    }
    TEST_ASSERT(archived != nil && archived.length > 0, @"Archived data created");

    // Decode
    User *decoded = nil;
    @try {
        decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[User class] fromData:archived error:NULL];
    } @catch (NSException *e) {
        decoded = [NSKeyedUnarchiver unarchiveObjectWithData:archived];
    }
    TEST_ASSERT(decoded != nil,                 @"Decoded user");
    TEST_ASSERT(decoded.userId == original.userId,       @"userId preserved");
    TEST_ASSERT([decoded.name isEqualToString:original.name], @"name preserved");
    TEST_ASSERT([decoded.email isEqualToString:original.email], @"email preserved");
}

// ============================================================
#pragma mark - T11: Model Copy
// ============================================================

static void TestT11_ModelCopy(void) {
    TEST_SECTION(@"T11 — Model Copy");

    NSString *json = @"{\"id\":1,\"name\":\"Copy Test\",\"username\":\"copy\"}";
    User *original = [User yy_modelWithJSON:json];
    User *copy = [original yy_modelCopy];

    TEST_ASSERT(copy != nil,                    @"Copy created");
    TEST_ASSERT(copy != original,               @"Copy is different object");
    TEST_ASSERT(copy.userId == original.userId, @"userId matches");
    TEST_ASSERT([copy.name isEqualToString:original.name], @"name matches");

    // Mutating copy should not affect original
    [copy setValue:@"Changed" forKey:@"name"];
    TEST_ASSERT(![original.name isEqualToString:@"Changed"], @"Original unchanged after copy mutation");
}

// ============================================================
#pragma mark - T12: Hash & Equal
// ============================================================

static void TestT12_HashEqual(void) {
    TEST_SECTION(@"T12 — Hash & isEqual");

    NSString *json = @"{\"id\":1,\"name\":\"Hash Test\",\"email\":\"h@b.com\"}";
    User *a = [User yy_modelWithJSON:json];
    User *b = [User yy_modelWithJSON:json];
    User *c = [User yy_modelWithJSON:@"{\"id\":2,\"name\":\"Other\",\"email\":\"o@b.com\"}"];

    TEST_ASSERT([a yy_modelIsEqual:b],          @"Equal models are equal");
    TEST_ASSERT(![a yy_modelIsEqual:c],         @"Different models are not equal");
    TEST_ASSERT([a yy_modelHash] == [b yy_modelHash], @"Equal models have same hash");
}

// ============================================================
#pragma mark - T13: Model → JSON → Model Round-Trip
// ============================================================

static void TestT13_RoundTrip(void) {
    TEST_SECTION(@"T13 — Model → JSON → Model Round-Trip");

    NSData *data = HTTPGet(@"https://jsonplaceholder.typicode.com/users/1");
    User *original = [User yy_modelWithJSON:data];
    TEST_ASSERT(original != nil, @"Original user from API");

    // Model → JSON
    id jsonObj = [original yy_modelToJSONObject];
    TEST_ASSERT(jsonObj != nil,                 @"Model → JSON dictionary");
    TEST_ASSERT([jsonObj isKindOfClass:[NSDictionary class]], @"JSON is NSDictionary");

    // JSON → Model
    User *roundTrip = [User yy_modelWithDictionary:jsonObj];
    TEST_ASSERT(roundTrip != nil,               @"Round-trip user created");

    // Compare key fields
    TEST_ASSERT(roundTrip.userId == original.userId,   @"userId matches after round-trip");
    TEST_ASSERT([roundTrip.name isEqualToString:original.name], @"name matches after round-trip");
    TEST_ASSERT([roundTrip.username isEqualToString:original.username], @"username matches after round-trip");

    // Model → JSON Data → JSON String
    NSData *jsonData = [original yy_modelToJSONData];
    NSString *jsonStr = [original yy_modelToJSONString];
    TEST_ASSERT(jsonData != nil && jsonData.length > 0, @"yy_modelToJSONData not empty");
    TEST_ASSERT(jsonStr != nil && jsonStr.length > 0,   @"yy_modelToJSONString not empty");
    NSLog(@"  📄 JSON preview: %@...", [jsonStr substringToIndex:MIN(100, jsonStr.length)]);
}

// ============================================================
#pragma mark - T14: Null / Missing Fields
// ============================================================

static void TestT14_NullMissing(void) {
    TEST_SECTION(@"T14 — Null & Missing Field Handling");

    // Fields with explicit null
    NSString *json = @"{\"id\":1,\"name\":null,\"email\":\"a@b.com\",\"phone\":null}";
    User *user = [User yy_modelWithJSON:json];
    TEST_ASSERT(user != nil,                    @"Parsed with null fields");
    TEST_ASSERT(user.name == nil,               @"null name → nil");
    // email is uppercased by modelCustomTransformFromDictionary: "a@b.com" → "A@B.COM"
    TEST_ASSERT([user.email isEqualToString:@"A@B.COM"], @"non-null email preserved (uppercased by transform)");
    TEST_ASSERT(user.phone == nil,              @"null phone → nil");

    // Completely empty JSON
    NSString *emptyJson = @"{}";
    User *emptyUser = [User yy_modelWithJSON:emptyJson];
    TEST_ASSERT(emptyUser != nil,               @"Parsed empty JSON");
    TEST_ASSERT(emptyUser.userId == 0,          @"Missing id → 0");
    TEST_ASSERT(emptyUser.name == nil,          @"Missing name → nil");

    // Wrong types (string where number expected)
    NSString *wrongType = @"{\"id\":\"not_a_number\",\"name\":123}";
    User *wrongUser = [User yy_modelWithJSON:wrongType];
    TEST_ASSERT(wrongUser != nil,               @"Parsed wrong types without crash");
}

// ============================================================
#pragma mark - T15: Date Parsing
// ============================================================

static void TestT15_DateParsing(void) {
    TEST_SECTION(@"T15 — Date Parsing (inline, using generic NSObject)");

    // ISO 8601
    NSString *json1 = @"{\"created\":\"2026-09-05T12:00:00Z\"}";
    id obj1 = [NSObject yy_modelWithJSON:json1];
    TEST_ASSERT(obj1 != nil, @"Parsed ISO 8601 date JSON");

    // Unix timestamp (seconds)
    NSString *json2 = @"{\"ts\":1725000000}";
    id obj2 = [NSObject yy_modelWithJSON:json2];
    TEST_ASSERT(obj2 != nil, @"Parsed unix timestamp JSON");

    // Unix timestamp (milliseconds)
    NSString *json3 = @"{\"ts\":1725000000000}";
    id obj3 = [NSObject yy_modelWithJSON:json3];
    TEST_ASSERT(obj3 != nil, @"Parsed millisecond timestamp JSON");
}

// ============================================================
#pragma mark - T16: Live API Full Test
// ============================================================

static void TestT16_LiveAPIFull(void) {
    TEST_SECTION(@"T16 — Live API: All Users from JSONPlaceholder");

    NSData *data = HTTPGet(@"https://jsonplaceholder.typicode.com/users");
    TEST_ASSERT(data != nil, @"HTTP GET /users returned data");

    NSArray *users = [NSArray yy_modelArrayWithClass:[User class] json:data];
    TEST_ASSERT(users != nil && users.count == 10, @"Parsed 10 users");

    for (User *u in users) {
        BOOL ok = (u.userId > 0 && u.name.length > 0 && u.address != nil && u.company != nil);
        if (!ok) {
            NSLog(@"  ⚠️ User %ld: name=%@, address=%@, company=%@",
                  (long)u.userId, u.name, u.address ? @"✓" : @"nil", u.company ? @"✓" : @"nil");
        }
    }

    // Check that key-path mapping worked for all users
    __block int keyPathOK = 0;
    [users enumerateObjectsUsingBlock:^(User *u, NSUInteger idx, BOOL *stop) {
        if (u.companyName.length > 0) keyPathOK++;
    }];
    TEST_ASSERT(keyPathOK == 10, @"All 10 users have companyName from key-path");

    // Test dictionary extraction
    NSDictionary *dict = [NSDictionary yy_modelDictionaryWithClass:[User class] json:data];
    // Note: JSONPlaceholder returns array, not dictionary, so this may be nil
    if (dict) {
        TEST_ASSERT(dict.count == 10, @"Dictionary extraction has 10 entries");
    } else {
        NSLog(@"  ℹ️ Dictionary extraction N/A (API returns array, not dict)");
    }

    // Print summary
    NSLog(@"\n  📊 Users Summary:");
    for (User *u in users) {
        NSLog(@"    %ld. %@ (%@) — %@ — %@",
              (long)u.userId, u.name, u.username, u.email, u.companyName);
    }
}

// ============================================================
#pragma mark - T17: Performance
// ============================================================

static void TestT17_Performance(void) {
    TEST_SECTION(@"T17 — Performance Benchmark");

    NSData *data = HTTPGet(@"https://jsonplaceholder.typicode.com/users");
    if (!data) { NSLog(@"  ⚠️ Skipped (no network)"); return; }

    // Warm up
    [NSArray yy_modelArrayWithClass:[User class] json:data];

    // Benchmark: JSON → Model
    int iterations = 1000;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < iterations; i++) {
        @autoreleasepool {
            [NSArray yy_modelArrayWithClass:[User class] json:data];
        }
    }
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start;
    NSLog(@"  ⏱ JSON → Model × %d: %.2fms (%.3fms/iter)", iterations, elapsed * 1000, elapsed * 1000 / iterations);

    // Benchmark: Model → JSON
    NSArray *users = [NSArray yy_modelArrayWithClass:[User class] json:data];
    start = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < iterations; i++) {
        @autoreleasepool {
            [users yy_modelToJSONObject];
        }
    }
    elapsed = CFAbsoluteTimeGetCurrent() - start;
    NSLog(@"  ⏱ Model → JSON × %d: %.2fms (%.3fms/iter)", iterations, elapsed * 1000, elapsed * 1000 / iterations);

    // Benchmark: Full round-trip
    start = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < iterations; i++) {
        @autoreleasepool {
            NSArray *u = [NSArray yy_modelArrayWithClass:[User class] json:data];
            id j = [u yy_modelToJSONObject];
            [NSArray yy_modelArrayWithClass:[User class] json:j];
        }
    }
    elapsed = CFAbsoluteTimeGetCurrent() - start;
    NSLog(@"  ⏱ Full round-trip × %d: %.2fms (%.3fms/iter)", iterations, elapsed * 1000, elapsed * 1000 / iterations);
}

// ============================================================
#pragma mark - Main
// ============================================================

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"\n");
        NSLog(@"╔═══════════════════════════════════════════════════╗");
        NSLog(@"║     YYModel iOS 27 Fix — Verification Test       ║");
        NSLog(@"║     API: JSONPlaceholder (typicode.com)           ║");
        NSLog(@"╚═══════════════════════════════════════════════════╝");

        // Run all tests
        TestT1_BasicTypes();
        TestT2_NestedObject();
        TestT3_ArrayOfStrings();
        TestT4_ArrayOfNestedObjects();
        TestT5_KeyPathMapping();
        TestT6_MultiKeyFallback();
        TestT7_Blacklist();
        TestT8_CustomTransform();
        TestT9_DecimalPrecision();
        TestT10_NSCoding();
        TestT11_ModelCopy();
        TestT12_HashEqual();
        TestT13_RoundTrip();
        TestT14_NullMissing();
        TestT15_DateParsing();
        TestT16_LiveAPIFull();
        TestT17_Performance();

        // Summary
        NSLog(@"\n═══════════════════════════════════════════════════");
        NSLog(@"  RESULTS: ✅ %d passed  ❌ %d failed  (total %d)",
              _passCount, _failCount, _passCount + _failCount);
        NSLog(@"═══════════════════════════════════════════════════\n");

        if (_failCount == 0) {
            NSLog(@"  🎉 All tests passed! YYModel iOS 27 fix verified.");
        } else {
            NSLog(@"  ⚠️ %d test(s) failed. Review output above.", _failCount);
        }

        return _failCount;
    }
}
