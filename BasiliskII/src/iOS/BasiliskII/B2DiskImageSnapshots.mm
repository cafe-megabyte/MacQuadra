//
//  B2DiskImageSnapshots.mm
//  BasiliskII
//

#import "B2DiskImageSnapshots.h"

#import <copyfile.h>

NSString * const B2DiskImageSnapshotsDirectoryName = @"Disk Image Snaphots";

static NSString * const B2DiskImageSnapshotsErrorDomain = @"B2DiskImageSnapshots";

@implementation B2DiskImageSnapshots

+ (NSString *)snapshotsPathInDocumentsPath:(NSString *)documentsPath
{
    return [documentsPath stringByAppendingPathComponent:B2DiskImageSnapshotsDirectoryName];
}

+ (BOOL)isPathInSnapshotsDirectory:(NSString *)path documentsPath:(NSString *)documentsPath
{
    NSString *standardPath = [self absolutePathForVolumePath:path documentsPath:documentsPath].stringByStandardizingPath;
    NSString *snapshotsPath = [self snapshotsPathInDocumentsPath:documentsPath].stringByStandardizingPath;
    return [standardPath isEqualToString:snapshotsPath] || [standardPath hasPrefix:[snapshotsPath stringByAppendingString:@"/"]];
}

+ (BOOL)snapshotExistsForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath
{
    NSString *snapshotPath = [self snapshotPathForVolumePath:volumePath documentsPath:documentsPath];
    BOOL isDirectory = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:snapshotPath isDirectory:&isDirectory] && !isDirectory;
}

+ (void)ensureSnapshotsForConfiguredVolumesInDocumentsPath:(NSString *)documentsPath completion:(B2DiskImageSnapshotCompletion)completion
{
    [self performFileOperation:^{
        NSError *error = nil;
        BOOL success = [self ensureSnapshotsForConfiguredVolumesInDocumentsPath:documentsPath error:&error];
        [self finishWithSuccess:success error:error completion:completion];
    }];
}

+ (void)restoreSnapshotForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath completion:(B2DiskImageSnapshotCompletion)completion
{
    [self performFileOperation:^{
        NSError *error = nil;
        BOOL success = [self restoreSnapshotForVolumePath:volumePath documentsPath:documentsPath error:&error];
        [self finishWithSuccess:success error:error completion:completion];
    }];
}

+ (BOOL)ensureSnapshotsForConfiguredVolumesInDocumentsPath:(NSString *)documentsPath error:(NSError **)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *snapshotsPath = [self snapshotsPathInDocumentsPath:documentsPath];
    if (![fileManager createDirectoryAtPath:snapshotsPath withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSArray<NSString *> *volumePaths = [self configuredVolumePaths];
    for (NSString *volumePath in volumePaths) {
        if (![self ensureSnapshotForVolumePath:volumePath documentsPath:documentsPath error:error]) {
            return NO;
        }
    }
    return YES;
}

+ (BOOL)ensureSnapshotForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath error:(NSError **)error
{
    NSString *sourcePath = [self absolutePathForVolumePath:volumePath documentsPath:documentsPath];
    if ([self isPathInSnapshotsDirectory:sourcePath documentsPath:documentsPath]) {
        return YES;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL sourceIsDirectory = NO;
    if (![fileManager fileExistsAtPath:sourcePath isDirectory:&sourceIsDirectory] || sourceIsDirectory) {
        return YES;
    }

    NSString *snapshotPath = [self snapshotPathForVolumePath:sourcePath documentsPath:documentsPath];
    BOOL snapshotIsDirectory = NO;
    if ([fileManager fileExistsAtPath:snapshotPath isDirectory:&snapshotIsDirectory]) {
        if (snapshotIsDirectory && error) {
            *error = [self errorWithDescription:L(@"settings.volumes.snapshot.prepare.error.directory") underlyingError:nil];
        }
        return !snapshotIsDirectory;
    }

    return [self cloneItemAtPath:sourcePath toPath:snapshotPath error:error];
}

+ (BOOL)restoreSnapshotForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath error:(NSError **)error
{
    NSString *destinationPath = [self absolutePathForVolumePath:volumePath documentsPath:documentsPath];
    if ([self isPathInSnapshotsDirectory:destinationPath documentsPath:documentsPath]) {
        if (error) {
            *error = [self errorWithDescription:L(@"settings.volumes.reset.error.snapshotSource") underlyingError:nil];
        }
        return NO;
    }

    NSString *snapshotPath = [self snapshotPathForVolumePath:destinationPath documentsPath:documentsPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL snapshotIsDirectory = NO;
    if (![fileManager fileExistsAtPath:snapshotPath isDirectory:&snapshotIsDirectory] || snapshotIsDirectory) {
        if (error) {
            *error = [self errorWithDescription:L(@"settings.volumes.reset.error.noSnapshot") underlyingError:nil];
        }
        return NO;
    }

    NSString *temporaryPath = [self temporaryPathForReplacingPath:destinationPath];
    [fileManager removeItemAtPath:temporaryPath error:nil];
    if (![self cloneItemAtPath:snapshotPath toPath:temporaryPath error:error]) {
        [fileManager removeItemAtPath:temporaryPath error:nil];
        return NO;
    }

    NSError *removeError = nil;
    if ([fileManager fileExistsAtPath:destinationPath] && ![fileManager removeItemAtPath:destinationPath error:&removeError]) {
        [fileManager removeItemAtPath:temporaryPath error:nil];
        if (error) *error = removeError;
        return NO;
    }

    NSError *moveError = nil;
    if (![fileManager moveItemAtPath:temporaryPath toPath:destinationPath error:&moveError]) {
        if (error) *error = moveError;
        return NO;
    }
    return YES;
}

+ (NSArray<NSString *> *)configuredVolumePaths
{
    NSMutableArray<NSString *> *volumePaths = [NSMutableArray array];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[@"disk", @"floppy", @"cdrom"]) {
        id value = [defaults objectForKey:key];
        NSArray *values = [value isKindOfClass:[NSArray class]] ? value : (value ? @[value] : @[]);
        for (id item in values) {
            if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
                [volumePaths addObject:item];
            }
        }
    }
    return volumePaths;
}

+ (NSString *)absolutePathForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath
{
    NSString *path = [volumePath hasPrefix:@"*"] ? [volumePath substringFromIndex:1] : volumePath;
    if (![path hasPrefix:@"/"]) {
        path = [documentsPath stringByAppendingPathComponent:path];
    }
    return path.stringByStandardizingPath;
}

+ (NSString *)snapshotPathForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath
{
    NSString *sourcePath = [self absolutePathForVolumePath:volumePath documentsPath:documentsPath];
    return [[self snapshotsPathInDocumentsPath:documentsPath] stringByAppendingPathComponent:sourcePath.lastPathComponent];
}

+ (NSString *)temporaryPathForReplacingPath:(NSString *)path
{
    NSString *fileName = [NSString stringWithFormat:@".%@.reset-%@", path.lastPathComponent, NSUUID.UUID.UUIDString];
    return [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:fileName];
}

+ (BOOL)cloneItemAtPath:(NSString *)sourcePath toPath:(NSString *)destinationPath error:(NSError **)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *destinationDirectory = destinationPath.stringByDeletingLastPathComponent;
    if (![fileManager createDirectoryAtPath:destinationDirectory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    if (copyfile(sourcePath.fileSystemRepresentation, destinationPath.fileSystemRepresentation, NULL, COPYFILE_CLONE_FORCE) == 0) {
        return YES;
    }

    if (error) {
        NSString *message = [[NSString alloc] initWithUTF8String:strerror(errno)] ?: L(@"misc.error");
        *error = [self errorWithDescription:message underlyingError:nil];
    }
    return NO;
}

+ (NSError *)errorWithDescription:(NSString *)description underlyingError:(NSError *)underlyingError
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:B2DiskImageSnapshotsErrorDomain code:1 userInfo:userInfo];
}

+ (void)performFileOperation:(dispatch_block_t)operation
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), operation);
}

+ (void)finishWithSuccess:(BOOL)success error:(NSError *)error completion:(B2DiskImageSnapshotCompletion)completion
{
    if (completion == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(success, error);
    });
}

@end
