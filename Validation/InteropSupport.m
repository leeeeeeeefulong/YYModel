#import "InteropSupport.h"

NSDictionary *ValidationModelResult(NSObject *model) {
    if (!model) return @{@"error":@"nil OC model"};
    NSDictionary *exported = [model yy_modelToJSONObject];
    NSObject *roundTrip = [model.class yy_modelWithDictionary:exported];
    if (!exported || !roundTrip) return @{@"error":@"OC export/round trip failed"};
    return @{@"modelJSON":exported, @"roundTripModelJSON":[roundTrip yy_modelToJSONObject] ?: @{}};
}

BOOL ValidationTouchObjC(void) { return WeatherEnvelope.class != Nil; }

NSDictionary *ValidationOCResult(NSData *data, id object, NSString *channel, NSUInteger iterations) {
    @try {
        BOOL dictionaryInput = [channel isEqualToString:@"object"];
        BOOL encode = [channel isEqualToString:@"encode"];
        WeatherEnvelope *(^parse)(void) = ^{
            return dictionaryInput ? [WeatherEnvelope yy_modelWithDictionary:object]
                                   : [WeatherEnvelope yy_modelWithJSON:data];
        };
        NSTimeInterval first = NSProcessInfo.processInfo.systemUptime;
        WeatherEnvelope *model = parse();
        double firstMS = (NSProcessInfo.processInfo.systemUptime - first) * 1000;
        NSMutableDictionary *result = [ValidationModelResult(model) mutableCopy];
        result[@"firstDecodeMilliseconds"] = @(firstMS);
        if (encode && !result[@"error"]) {
            NSData *encoded = [model yy_modelToJSONData];
            id json = encoded ? [NSJSONSerialization JSONObjectWithData:encoded options:0 error:NULL] : nil;
            if (!json) return @{@"error":@"OC JSON Data export failed"};
            result[@"encodedModelJSON"] = json;
            result[@"encodedBytes"] = @(encoded.length);
        }
        if (result[@"error"] || iterations == 0) return result;
        for (NSUInteger i = 0; i < 5; i++) {
            @autoreleasepool {
                if (encode) (void)[model yy_modelToJSONData];
                else (void)parse();
            }
        }
        NSMutableArray *samples = [NSMutableArray new];
        double consumed = 0;
        for (NSUInteger r = 0; r < 7; r++) {
            NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
            for (NSUInteger i = 0; i < iterations; i++) {
                @autoreleasepool {
                    if (encode) consumed += [model yy_modelToJSONData].length;
                    else consumed += parse().forecasts.firstObject.current.temperature_2m;
                }
            }
            [samples addObject:@((NSProcessInfo.processInfo.systemUptime - start) * 1000)];
        }
        result[@"sampleMilliseconds"] = samples;
        result[@"consumed"] = @(consumed);
        result[@"iterationsPerSample"] = @(iterations);
        return result;
    } @catch (NSException *exception) {
        return @{@"error":exception.description};
    }
}
