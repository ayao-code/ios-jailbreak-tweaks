#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

static void Require(BOOL condition, NSString *message) {
    if (!condition) @throw [NSException exceptionWithName:@"DeviceHTTPFetch" reason:message userInfo:nil];
}

static NSString *DigestString(unsigned char digest[CC_SHA256_DIGEST_LENGTH]) {
    NSMutableString *value = [NSMutableString string];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [value appendFormat:@"%02x", digest[index]];
    return value;
}

static NSString *FileHash(NSString *path, unsigned long long *byteCount) {
    FILE *file = fopen(path.fileSystemRepresentation, "rb");
    if (!file) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    unsigned char buffer[256 * 1024];
    size_t count = 0;
    unsigned long long total = 0;
    while ((count = fread(buffer, 1, sizeof(buffer), file)) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
        total += count;
    }
    BOOL failed = ferror(file) != 0;
    fclose(file);
    Require(!failed, @"Existing file read failed");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    if (byteCount) *byteCount = total;
    return DigestString(digest);
}

static void Fetch(NSString *host, uint16_t port, NSString *remoteName, NSString *destination,
                  unsigned long long expectedBytes, NSString *expectedHash) {
    unsigned long long existingBytes = 0;
    NSString *existingHash = FileHash(destination, &existingBytes);
    if (existingBytes == expectedBytes && [existingHash isEqual:expectedHash]) {
        printf("REUSED %s\n", destination.UTF8String);
        return;
    }
    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    Require(descriptor >= 0, @"Cannot create socket");
    struct timeval timeout = { .tv_sec = 60, .tv_usec = 0 };
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    Require(inet_pton(AF_INET, host.UTF8String, &address.sin_addr) == 1, @"Invalid host");
    Require(connect(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0, @"Cannot connect to server");
    NSString *request = [NSString stringWithFormat:@"GET /%@ HTTP/1.1\r\nHost: %@\r\nConnection: close\r\n\r\n",
                         remoteName, host];
    NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
    Require(send(descriptor, requestData.bytes, requestData.length, 0) == (ssize_t)requestData.length,
            @"Cannot send request");
    NSString *incoming = [destination stringByAppendingString:@".incoming"];
    FILE *output = fopen(incoming.fileSystemRepresentation, "wb");
    Require(output != NULL, @"Cannot create incoming file");
    NSMutableData *headers = [NSMutableData data];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    unsigned char buffer[256 * 1024];
    unsigned long long total = 0;
    BOOL headersComplete = NO;
    while (YES) {
        ssize_t count = recv(descriptor, buffer, sizeof(buffer), 0);
        if (count == 0) break;
        Require(count > 0, @"Network read failed");
        if (!headersComplete) {
            [headers appendBytes:buffer length:(NSUInteger)count];
            NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
            NSRange range = [headers rangeOfData:separator options:0 range:NSMakeRange(0, headers.length)];
            if (range.location == NSNotFound) {
                Require(headers.length < 64 * 1024, @"HTTP headers are too large");
                continue;
            }
            NSString *headerText = [[NSString alloc] initWithData:[headers subdataWithRange:NSMakeRange(0, range.location)]
                                                          encoding:NSASCIIStringEncoding];
            Require([headerText hasPrefix:@"HTTP/1.0 200"] || [headerText hasPrefix:@"HTTP/1.1 200"],
                    @"HTTP server returned non-200 status");
            NSUInteger bodyOffset = NSMaxRange(range);
            NSData *body = [headers subdataWithRange:NSMakeRange(bodyOffset, headers.length - bodyOffset)];
            if (body.length > 0) {
                Require(fwrite(body.bytes, 1, body.length, output) == body.length, @"File write failed");
                CC_SHA256_Update(&context, body.bytes, (CC_LONG)body.length);
                total += body.length;
            }
            headersComplete = YES;
            [headers setLength:0];
            continue;
        }
        Require(fwrite(buffer, 1, (size_t)count, output) == (size_t)count, @"File write failed");
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
        total += (unsigned long long)count;
    }
    fclose(output);
    close(descriptor);
    Require(headersComplete, @"HTTP response is incomplete");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    Require(total == expectedBytes, @"Downloaded size differs");
    Require([DigestString(digest) isEqual:expectedHash], @"Downloaded hash differs");
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
    Require([[NSFileManager defaultManager] moveItemAtPath:incoming toPath:destination error:&error],
            error.localizedDescription ?: @"Cannot finalize file");
    printf("DOWNLOADED %s\n", destination.UTF8String);
}

int main(int argumentCount, const char *arguments[]) {
    @autoreleasepool {
        @try {
            if (argumentCount != 7) {
                fprintf(stderr, "Usage: DeviceHTTPFetch HOST PORT REMOTE_NAME DESTINATION BYTES SHA256\n");
                return 1;
            }
            Fetch(@(arguments[1]), (uint16_t)strtoul(arguments[2], NULL, 10), @(arguments[3]), @(arguments[4]),
                  strtoull(arguments[5], NULL, 10), @(arguments[6]));
            return 0;
        } @catch (NSException *exception) {
            fprintf(stderr, "ERROR: %s\n", exception.reason.UTF8String);
            return 2;
        }
    }
}
