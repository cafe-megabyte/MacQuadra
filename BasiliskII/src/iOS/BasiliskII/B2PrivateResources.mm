//
//  B2PrivateResources.mm
//  BasiliskII
//

#import "B2PrivateResources.h"
#import "B2AppDelegate.h"

#import <QuartzCore/QuartzCore.h>

#include <zlib.h>

#if __has_include("B2PrivateResourceURLs.h")
#import "B2PrivateResourceURLs.h"
#endif

#ifndef B2_PRIVATE_ROM_ZIP_URL
#define B2_PRIVATE_ROM_ZIP_URL nil
#endif

#ifndef B2_PRIVATE_DISK_ZIP_URL
#define B2_PRIVATE_DISK_ZIP_URL nil
#endif

typedef void (^B2ZipProgressHandler)(int64_t receivedBytes, int64_t expectedBytes);

typedef NS_ENUM(NSInteger, B2PrivateResourceKind) {
    B2PrivateResourceKindROM,
    B2PrivateResourceKindDisk,
};

static uint16_t B2ReadUInt16LE(const uint8_t *bytes)
{
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint32_t B2ReadUInt32LE(const uint8_t *bytes)
{
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

@interface B2ZipDownload : NSObject <NSURLSessionDataDelegate>

- (instancetype)initWithURL:(NSURL *)url destinationPath:(NSString *)destinationPath progressHandler:(B2ZipProgressHandler)progressHandler;
- (BOOL)run:(NSError **)error;

@end

@implementation B2ZipDownload
{
    NSURL *_url;
    NSString *_destinationPath;
    NSString *_temporaryPath;
    NSFileHandle *_outputFile;
    NSMutableData *_headerData;
    B2ZipProgressHandler _progressHandler;
    z_stream _zstream;
    dispatch_semaphore_t _semaphore;
    NSError *_error;
    int64_t _receivedBytes;
    int64_t _expectedBytes;
    uint16_t _method;
    uint16_t _flags;
    uint32_t _compressedSize;
    uint32_t _remainingStoredBytes;
    NSUInteger _bytesToSkip;
    BOOL _headerRead;
    BOOL _inflateInitialized;
    BOOL _finishedEntry;
}

- (instancetype)initWithURL:(NSURL *)url destinationPath:(NSString *)destinationPath progressHandler:(B2ZipProgressHandler)progressHandler
{
    self = [super init];
    if (self) {
        _url = url;
        _destinationPath = destinationPath;
        _temporaryPath = [destinationPath stringByAppendingString:@".download"];
        _headerData = [NSMutableData dataWithCapacity:30];
        _progressHandler = [progressHandler copy];
        _expectedBytes = NSURLSessionTransferSizeUnknown;
    }
    return self;
}

- (BOOL)run:(NSError **)error
{
    [[NSFileManager defaultManager] removeItemAtPath:_temporaryPath error:nil];
    [[NSFileManager defaultManager] createFileAtPath:_temporaryPath contents:nil attributes:nil];
    _outputFile = [NSFileHandle fileHandleForWritingAtPath:_temporaryPath];
    if (_outputFile == nil) {
        [self failWithMessage:L(@"privateResources.error.destinationFile")];
        if (error) *error = _error;
        return NO;
    }

    _semaphore = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    [[session dataTaskWithURL:_url] resume];
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];

    if (_inflateInitialized) {
        inflateEnd(&_zstream);
        _inflateInitialized = NO;
    }
    [_outputFile closeFile];
    _outputFile = nil;

    if (_error != nil || !_finishedEntry) {
        [[NSFileManager defaultManager] removeItemAtPath:_temporaryPath error:nil];
        if (_error == nil) {
            [self failWithMessage:L(@"privateResources.error.zipIncomplete")];
        }
        if (error) *error = _error;
        return NO;
    }

    [[NSFileManager defaultManager] removeItemAtPath:_destinationPath error:nil];
    BOOL moved = [[NSFileManager defaultManager] moveItemAtPath:_temporaryPath toPath:_destinationPath error:error];
    if (!moved) {
        [[NSFileManager defaultManager] removeItemAtPath:_temporaryPath error:nil];
    }
    return moved;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    NSHTTPURLResponse *httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    if (httpResponse != nil && (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300)) {
        [self failWithMessage:LX(@"privateResources.error.httpStatus", (long)httpResponse.statusCode)];
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    _expectedBytes = response.expectedContentLength;
    [self reportProgress];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    if (_error != nil || _finishedEntry) {
        return;
    }
    _receivedBytes += (int64_t)data.length;
    [self reportProgress];
    [self processBytes:(const uint8_t *)data.bytes length:data.length];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error != nil && _error == nil) {
        _error = error;
    }
    dispatch_semaphore_signal(_semaphore);
}

- (void)reportProgress
{
    if (_progressHandler != nil) {
        _progressHandler(_receivedBytes, _expectedBytes);
    }
}

- (void)processBytes:(const uint8_t *)bytes length:(NSUInteger)length
{
    NSUInteger offset = 0;
    while (offset < length && _error == nil && !_finishedEntry) {
        if (!_headerRead) {
            NSUInteger needed = 30 - _headerData.length;
            NSUInteger count = MIN(needed, length - offset);
            [_headerData appendBytes:bytes + offset length:count];
            offset += count;
            if (_headerData.length == 30 && ![self readHeader]) {
                return;
            }
        } else if (_bytesToSkip > 0) {
            NSUInteger count = MIN(_bytesToSkip, length - offset);
            offset += count;
            _bytesToSkip -= count;
        } else if (_method == 0) {
            NSUInteger count = MIN((NSUInteger)_remainingStoredBytes, length - offset);
            [_outputFile writeData:[NSData dataWithBytes:bytes + offset length:count]];
            offset += count;
            _remainingStoredBytes -= (uint32_t)count;
            if (_remainingStoredBytes == 0) {
                _finishedEntry = YES;
            }
        } else if (_method == 8) {
            [self inflateBytes:bytes + offset length:(uint32_t)(length - offset)];
            offset = length;
        } else {
            [self failWithMessage:L(@"privateResources.error.zipMethod")];
        }
    }
}

- (BOOL)readHeader
{
    const uint8_t *bytes = (const uint8_t *)_headerData.bytes;
    if (B2ReadUInt32LE(bytes) != 0x04034b50) {
        [self failWithMessage:L(@"privateResources.error.notZip")];
        return NO;
    }

    _flags = B2ReadUInt16LE(bytes + 6);
    _method = B2ReadUInt16LE(bytes + 8);
    _compressedSize = B2ReadUInt32LE(bytes + 18);
    uint16_t fileNameLength = B2ReadUInt16LE(bytes + 26);
    uint16_t extraLength = B2ReadUInt16LE(bytes + 28);
    _bytesToSkip = (NSUInteger)fileNameLength + (NSUInteger)extraLength;

    if ((_flags & 0x0001) != 0) {
        [self failWithMessage:L(@"privateResources.error.zipEncrypted")];
        return NO;
    }
    if (_method != 0 && _method != 8) {
        [self failWithMessage:L(@"privateResources.error.zipMethod")];
        return NO;
    }
    if (_method == 0 && (_flags & 0x0008) != 0) {
        [self failWithMessage:L(@"privateResources.error.zipStoredSize")];
        return NO;
    }
    if (_method == 0) {
        _remainingStoredBytes = _compressedSize;
    } else {
        memset(&_zstream, 0, sizeof(_zstream));
        int result = inflateInit2(&_zstream, -MAX_WBITS);
        if (result != Z_OK) {
            [self failWithMessage:L(@"privateResources.error.zipInit")];
            return NO;
        }
        _inflateInitialized = YES;
    }
    _headerRead = YES;
    return YES;
}

- (void)inflateBytes:(const uint8_t *)bytes length:(uint32_t)length
{
    uint8_t output[64 * 1024];
    _zstream.next_in = (Bytef *)bytes;
    _zstream.avail_in = length;

    while (_zstream.avail_in > 0 && _error == nil && !_finishedEntry) {
        _zstream.next_out = output;
        _zstream.avail_out = sizeof(output);
        int result = inflate(&_zstream, Z_NO_FLUSH);
        NSUInteger produced = sizeof(output) - _zstream.avail_out;
        if (produced > 0) {
            [_outputFile writeData:[NSData dataWithBytes:output length:produced]];
        }
        if (result == Z_STREAM_END) {
            _finishedEntry = YES;
            break;
        }
        if (result != Z_OK) {
            [self failWithMessage:L(@"privateResources.error.zipDecompress")];
            break;
        }
        if (produced == 0 && _zstream.avail_in == 0) {
            break;
        }
    }
}

- (void)failWithMessage:(NSString *)message
{
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: message};
    _error = [NSError errorWithDomain:@"B2PrivateResources" code:1 userInfo:userInfo];
}

@end

@implementation B2PrivateResources
{
    BOOL _didPrepare;
    BOOL _busy;
    BOOL _preparationActive;
}

+ (instancetype)sharedInstance
{
    static B2PrivateResources *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [B2PrivateResources new];
    });
    return sharedInstance;
}

- (BOOL)prepareResourcesIfNeededFromViewController:(UIViewController *)viewController completion:(dispatch_block_t)completion
{
    if (_preparationActive || _busy || viewController.presentedViewController != nil) {
        return YES;
    }
    if (_didPrepare) {
        return NO;
    }
    _didPrepare = YES;
    dispatch_block_t finish = ^{
        self->_preparationActive = NO;
        if (completion) completion();
    };
    if ([self configureExistingResourceForKind:B2PrivateResourceKindROM]) {
        if ([self configureExistingResourceForKind:B2PrivateResourceKindDisk]) {
            return NO;
        }
        _preparationActive = YES;
        [self prepareKind:B2PrivateResourceKindDisk fromViewController:viewController completion:finish];
        return YES;
    }

    _preparationActive = YES;
    [self prepareKind:B2PrivateResourceKindROM fromViewController:viewController completion:^{
        [self prepareKind:B2PrivateResourceKindDisk fromViewController:viewController completion:finish];
    }];
    return YES;
}

- (BOOL)allRequiredResourcesConfigured
{
    return [self configuredResourceExistsForKind:B2PrivateResourceKindROM] && [self configuredResourceExistsForKind:B2PrivateResourceKindDisk];
}

- (void)prepareKind:(B2PrivateResourceKind)kind fromViewController:(UIViewController *)viewController completion:(dispatch_block_t)completion
{
    if ([self configureExistingResourceForKind:kind]) {
        if (completion) completion();
        return;
    }

    NSString *urlString = [self urlStringForKind:kind];
    if (urlString.length == 0) {
        [self showMissingURLAlertForKind:kind fromViewController:viewController completion:completion];
        return;
    }

    [self downloadKind:kind urlString:urlString fromViewController:viewController completion:completion];
}

- (BOOL)configureExistingResourceForKind:(B2PrivateResourceKind)kind
{
    if ([self configuredResourceExistsForKind:kind]) {
        return YES;
    }

    NSString *fileName = [self firstFileNameInDocumentsWithExtensions:[self extensionsForKind:kind]];
    if (fileName == nil) {
        return NO;
    }

    [self configureFileName:fileName forKind:kind];
    return YES;
}

- (BOOL)configuredResourceExistsForKind:(B2PrivateResourceKind)kind
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:(kind == B2PrivateResourceKindROM) ? @"rom" : @"disk"];
    NSArray *values = [value isKindOfClass:[NSArray class]] ? value : (value ? @[value] : @[]);
    for (NSString *path in values) {
        if (![path isKindOfClass:[NSString class]] || path.length == 0) {
            continue;
        }
        NSString *cleanPath = [path hasPrefix:@"*"] ? [path substringFromIndex:1] : path;
        NSString *fullPath = [cleanPath hasPrefix:@"/"] ? cleanPath : [[[B2AppDelegate sharedInstance] documentsPath] stringByAppendingPathComponent:cleanPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)firstFileNameInDocumentsWithExtensions:(NSSet<NSString *> *)extensions
{
    NSArray<NSString *> *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[B2AppDelegate sharedInstance] documentsPath] error:nil];
    for (NSString *fileName in fileNames) {
        if ([extensions containsObject:fileName.pathExtension.lowercaseString]) {
            NSString *fullPath = [[[B2AppDelegate sharedInstance] documentsPath] stringByAppendingPathComponent:fileName];
            BOOL isDirectory = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory] && !isDirectory) {
                return fileName;
            }
        }
    }
    return nil;
}

- (NSSet<NSString *> *)extensionsForKind:(B2PrivateResourceKind)kind
{
    if (kind == B2PrivateResourceKindROM) {
        return [NSSet setWithObject:@"rom"];
    }
    return [NSSet setWithArray:@[@"img", @"dsk", @"hd", @"disk"]];
}

- (NSString *)urlStringForKind:(B2PrivateResourceKind)kind
{
    return (kind == B2PrivateResourceKindROM) ? B2_PRIVATE_ROM_ZIP_URL : B2_PRIVATE_DISK_ZIP_URL;
}

- (NSString *)displayNameForKind:(B2PrivateResourceKind)kind
{
    return (kind == B2PrivateResourceKindROM) ? L(@"privateResources.romFile") : L(@"privateResources.diskImage");
}

- (NSString *)downloadFileNameForKind:(B2PrivateResourceKind)kind url:(NSURL *)url
{
    NSString *fileName = url.lastPathComponent.stringByRemovingPercentEncoding;
    if ([fileName.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        fileName = fileName.stringByDeletingPathExtension;
    }
    if (fileName.length == 0) {
        fileName = (kind == B2PrivateResourceKindROM) ? @"Quadra.ROM" : @"System 7.6.1.img";
    }
    return fileName;
}

- (void)configureFileName:(NSString *)fileName forKind:(B2PrivateResourceKind)kind
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (kind == B2PrivateResourceKindROM) {
        [defaults setObject:fileName forKey:@"rom"];
    } else {
        [defaults setObject:@[fileName] forKey:@"disk"];
    }
}

- (void)showMissingURLAlertForKind:(B2PrivateResourceKind)kind fromViewController:(UIViewController *)viewController completion:(dispatch_block_t)completion
{
    NSString *message = LX(@"privateResources.missingURL.message", [self displayNameForKind:kind]);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:L(@"privateResources.missingURL.title") message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:L(@"misc.ok") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        if (completion) completion();
    }]];
    [viewController presentViewController:alert animated:YES completion:nil];
}

- (void)downloadKind:(B2PrivateResourceKind)kind urlString:(NSString *)urlString fromViewController:(UIViewController *)viewController completion:(dispatch_block_t)completion
{
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        [[B2AppDelegate sharedInstance] showAlertWithTitle:L(@"privateResources.invalidURL.title") message:urlString];
        if (completion) completion();
        return;
    }

    NSString *fileName = [self downloadFileNameForKind:kind url:url];
    NSString *destinationPath = [[[B2AppDelegate sharedInstance] documentsPath] stringByAppendingPathComponent:fileName];
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:LX(@"privateResources.progress.title", fileName) message:L(@"privateResources.progress.starting") preferredStyle:UIAlertControllerStyleAlert];
    [self updateProgressAlert:progress message:L(@"privateResources.progress.starting")];
    _busy = YES;
    [viewController presentViewController:progress animated:YES completion:^{
        __block int64_t lastProgressUpdate = 0;
        B2ZipProgressHandler progressHandler = ^(int64_t receivedBytes, int64_t expectedBytes) {
            int64_t now = (int64_t)(CACurrentMediaTime() * 10.0);
            if (now == lastProgressUpdate) {
                return;
            }
            lastProgressUpdate = now;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateProgressAlert:progress message:[self progressMessageWithReceivedBytes:receivedBytes expectedBytes:expectedBytes]];
            });
        };

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            BOOL success = [[[B2ZipDownload alloc] initWithURL:url destinationPath:destinationPath progressHandler:progressHandler] run:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_busy = NO;
                [progress dismissViewControllerAnimated:YES completion:^{
                    if (success) {
                        [self configureFileName:fileName forKind:kind];
                    } else {
                        [[B2AppDelegate sharedInstance] showAlertWithTitle:LX(@"privateResources.download.error.title", [self displayNameForKind:kind]) message:error.localizedDescription];
                    }
                    if (completion) completion();
                }];
            });
        });
    }];
}

- (void)updateProgressAlert:(UIAlertController *)alert message:(NSString *)message
{
    NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
    paragraphStyle.alignment = NSTextAlignmentLeft;

    UIFont *font = [UIFont monospacedDigitSystemFontOfSize:UIFont.labelFontSize weight:UIFontWeightRegular];
    NSDictionary *attributes = @{NSFontAttributeName: font,
                                 NSParagraphStyleAttributeName: paragraphStyle};
    NSAttributedString *attributedMessage = [[NSAttributedString alloc] initWithString:message attributes:attributes];
    [alert setValue:attributedMessage forKey:@"attributedMessage"];
}

- (NSString *)progressMessageWithReceivedBytes:(int64_t)receivedBytes expectedBytes:(int64_t)expectedBytes
{
    NSString *received = [self progressByteCountStringForBytes:receivedBytes];
    if (expectedBytes > 0) {
        NSString *expected = [self progressByteCountStringForBytes:expectedBytes];
        double percent = ((double)receivedBytes / (double)expectedBytes) * 100.0;
        return LX(@"privateResources.progress.withExpected", received, expected, [self progressPercentString:percent]);
    }
    return LX(@"privateResources.progress.downloaded", received);
}

- (NSString *)progressByteCountStringForBytes:(int64_t)bytes
{
    double megabytes = (double)bytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%@ MB", [self progressDecimalString:megabytes]];
}

- (NSString *)progressPercentString:(double)percent
{
    return [NSString stringWithFormat:@"%@%%", [self progressDecimalString:percent]];
}

- (NSString *)progressDecimalString:(double)value
{
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 1;
    formatter.maximumFractionDigits = 1;
    return [formatter stringFromNumber:@(value)] ?: @"0.0";
}

@end
