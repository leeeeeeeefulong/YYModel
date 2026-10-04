#import "InteropSupport.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 6) return 2;
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSString *channel = [NSString stringWithUTF8String:argv[4]];
        NSDictionary *result = ValidationOCResult(data, object, channel, strtoull(argv[5], NULL, 10));
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        if (!json) return 3;
        return [json writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES] ? 0 : 4;
    }
}
