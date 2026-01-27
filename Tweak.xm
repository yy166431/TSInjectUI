// Tweak.xm - socket report version without LOG_TOKEN (test mode)
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

#pragma mark - ====== Raw socket report (NO TOKEN) ======

static NSString * const TS_REPORT_HOST  = @"159.75.14.193";
static const int        TS_REPORT_PORT  = 8099;
static NSString * const TS_REPORT_PATH  = @"/api/mjlog";

static NSString *TSNowISO8601(void) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    return [f stringFromDate:[NSDate date]];
}

static void TSAppendLocal(NSString *line) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject ?: NSTemporaryDirectory();
    NSString *path = [dir stringByAppendingPathComponent:@"tsinject_report.log"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (!fh) return;
    [fh seekToEndOfFile];
    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    [fh writeData:d];
    [fh closeFile];
}

static BOOL TSSendRawHTTPPost(NSData *jsonBody) {
    if (!jsonBody || jsonBody.length == 0) return NO;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        TSAppendLocal([NSString stringWithFormat:@"[%@] socket() fail", TSNowISO8601()]);
        return NO;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)TS_REPORT_PORT);

    if (inet_pton(AF_INET, TS_REPORT_HOST.UTF8String, &addr.sin_addr) != 1) {
        close(fd);
        TSAppendLocal([NSString stringWithFormat:@"[%@] inet_pton fail", TSNowISO8601()]);
        return NO;
    }

    struct timeval tv; tv.tv_sec = 3; tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        TSAppendLocal([NSString stringWithFormat:@"[%@] connect fail", TSNowISO8601()]);
        return NO;
    }

    NSMutableString *req = [NSMutableString string];
    [req appendFormat:@"POST %@ HTTP/1.1\r\n", TS_REPORT_PATH];
    [req appendFormat:@"Host: %@:%d\r\n", TS_REPORT_HOST, TS_REPORT_PORT];
    [req appendString:@"Content-Type: application/json\r\n"];
    [req appendFormat:@"Content-Length: %lu\r\n", (unsigned long)jsonBody.length];
    [req appendString:@"Connection: close\r\n\r\n"];

    NSData *head = [req dataUsingEncoding:NSUTF8StringEncoding];
    if (send(fd, head.bytes, (int)head.length, 0) < 0 ||
        send(fd, jsonBody.bytes, (int)jsonBody.length, 0) < 0) {
        close(fd);
        TSAppendLocal([NSString stringWithFormat:@"[%@] send fail", TSNowISO8601()]);
        return NO;
    }

    char buf[128] = {0};
    recv(fd, buf, sizeof(buf)-1, 0);
    close(fd);
    TSAppendLocal([NSString stringWithFormat:@"[%@] POST OK", TSNowISO8601()]);
    return YES;
}

static void TSReport(NSString *type, NSDictionary *payload) {
    NSMutableDictionary *obj = [NSMutableDictionary dictionary];
    obj[@"t"] = TSNowISO8601();
    obj[@"type"] = type ?: @"unknown";
    obj[@"payload"] = payload ?: @{};
    obj[@"device"] = UIDevice.currentDevice.model ?: @"";
    obj[@"sys"] = UIDevice.currentDevice.systemVersion ?: @"";
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&err];
    if (!data || err) {
        TSAppendLocal([NSString stringWithFormat:@"[%@] json encode fail", TSNowISO8601()]);
        return;
    }
    TSSendRawHTTPPost(data);
}

#pragma mark - ====== Minimal entry test ======

__attribute__((constructor))
static void Entry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(1519);
        TSReport(@"dylib_loaded", @{});
    });
}
