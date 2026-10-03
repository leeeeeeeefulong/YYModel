#import <Foundation/Foundation.h>
#import "YYModel.h"

@interface WeatherCurrent : NSObject
@property(nonatomic,copy) NSString *time;
@property(nonatomic) NSInteger interval, relative_humidity_2m, is_day, weather_code;
@property(nonatomic) double temperature_2m, precipitation, wind_speed_10m;
@end
@implementation WeatherCurrent
@end
@interface WeatherHourly : NSObject
@property(nonatomic,strong) NSArray *time, *temperature_2m, *relative_humidity_2m, *precipitation_probability, *precipitation, *weather_code, *wind_speed_10m;
@end
@implementation WeatherHourly
@end
@interface WeatherDaily : NSObject
@property(nonatomic,strong) NSArray *time, *temperature_2m_max, *temperature_2m_min, *precipitation_sum, *sunrise, *sunset;
@end
@implementation WeatherDaily
@end
@interface WeatherForecast : NSObject
@property(nonatomic) double latitude, longitude, generationtime_ms, elevation;
@property(nonatomic) NSInteger utc_offset_seconds;
@property(nonatomic,copy) NSString *timezone, *timezone_abbreviation;
@property(nonatomic,strong) NSDictionary *current_units, *hourly_units, *daily_units;
@property(nonatomic,strong) WeatherCurrent *current;
@property(nonatomic,strong) WeatherHourly *hourly;
@property(nonatomic,strong) WeatherDaily *daily;
@end
@implementation WeatherForecast
@end
@interface WeatherEnvelope : NSObject
@property(nonatomic,copy) NSString *trace;
@property(nonatomic) BOOL ok;
@property(nonatomic,strong) NSArray<WeatherForecast *> *forecasts;
@property(nonatomic,strong) NSArray *warnings;
@end
@implementation WeatherEnvelope
+ (NSDictionary *)modelCustomPropertyMapper { return @{@"trace":@"request.trace_id",@"forecasts":@"payload.locations"}; }
+ (NSDictionary *)modelContainerPropertyGenericClass { return @{@"forecasts":WeatherForecast.class}; }
@end

static NSDictionary *Summary(WeatherEnvelope *model) {
    NSUInteger hours=0, days=0, temperatureCount=0, unitKeys=0, nullWarnings=0;
    double latitudeSum=0, currentTemperatureSum=0, hourlyTemperatureSum=0;
    for (WeatherForecast *f in model.forecasts) {
        hours += f.hourly.time.count; days += f.daily.time.count;
        latitudeSum += f.latitude; currentTemperatureSum += f.current.temperature_2m;
        temperatureCount += f.hourly.temperature_2m.count;
        for (id value in f.hourly.temperature_2m) {
            if ([value respondsToSelector:@selector(doubleValue)]) hourlyTemperatureSum += [value doubleValue];
        }
        unitKeys += f.current_units.count+f.hourly_units.count+f.daily_units.count;
    }
    for (id value in model.warnings) if (value == NSNull.null) nullWarnings++;
    return @{@"locations":@(model.forecasts.count),@"hours":@(hours),@"days":@(days),@"latitudeSum":@(latitudeSum),
             @"currentTemperatureSum":@(currentTemperatureSum),@"hourlyTemperatureSum":@(hourlyTemperatureSum),
             @"hourlyTemperatureCount":@(temperatureCount),@"unitKeys":@(unitKeys),@"trace":model.trace ?: @"",
             @"ok":@(model.ok),@"warnings":@(model.warnings.count),@"nullWarnings":@(nullWarnings),
             @"firstTime":model.forecasts.firstObject.hourly.time.firstObject ?: @""};
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSUInteger iterations=strtoull(argv[3],NULL,10);
        NSMutableDictionary *result=[@{@"bytes":@(data.length),@"iterationsPerSample":@(iterations)} mutableCopy];
        @try {
            WeatherEnvelope *model=[WeatherEnvelope yy_modelWithJSON:data];
            if (!model) @throw [NSException exceptionWithName:@"Validation" reason:@"Root model is nil" userInfo:nil];
            result[@"summary"]=Summary(model);
            NSDictionary *exported=[model yy_modelToJSONObject];
            result[@"modelJSON"]=exported;
            BOOL nested=[exported[@"payload"] isKindOfClass:NSDictionary.class] &&
                [exported[@"payload"][@"locations"] isKindOfClass:NSArray.class] &&
                [exported[@"request"][@"trace_id"] isEqual:model.trace];
            result[@"nestedExport"]=@(nested);
            WeatherEnvelope *roundtrip=[WeatherEnvelope yy_modelWithDictionary:exported];
            result[@"roundTripSummary"]=Summary(roundtrip);
            result[@"roundTripModelJSON"]=[roundtrip yy_modelToJSONObject];
            if (iterations > 0) {
            for (NSUInteger i=0;i<5;i++) { @autoreleasepool { (void)[WeatherEnvelope yy_modelWithJSON:data]; } }
            NSMutableArray *samples=[NSMutableArray new]; double consumed=0;
            for (NSUInteger r=0;r<7;r++) {
                NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
                for (NSUInteger i=0;i<iterations;i++) {
                    @autoreleasepool {
                        WeatherEnvelope *parsed=[WeatherEnvelope yy_modelWithJSON:data];
                        consumed += parsed.forecasts.firstObject.current.temperature_2m;
                    }
                }
                [samples addObject:@((NSProcessInfo.processInfo.systemUptime-start)*1000)];
            }
            result[@"sampleMilliseconds"]=samples; result[@"consumed"]=@(consumed);
            }
        } @catch(NSException *e) { result[@"error"]=e.description; }
        NSData *output=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
        if (!output) return 2;
        return [output writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES] ? 0 : 3;
    }
}
