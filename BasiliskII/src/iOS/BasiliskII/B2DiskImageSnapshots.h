//
//  B2DiskImageSnapshots.h
//  BasiliskII
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const B2DiskImageSnapshotsDirectoryName;

typedef void (^B2DiskImageSnapshotCompletion)(BOOL success, NSError * _Nullable error);

@interface B2DiskImageSnapshots : NSObject

+ (NSString *)snapshotsPathInDocumentsPath:(NSString *)documentsPath;
+ (BOOL)isPathInSnapshotsDirectory:(NSString *)path documentsPath:(NSString *)documentsPath;
+ (BOOL)snapshotExistsForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath;
+ (void)ensureSnapshotsForConfiguredVolumesInDocumentsPath:(NSString *)documentsPath completion:(B2DiskImageSnapshotCompletion)completion;
+ (void)restoreSnapshotForVolumePath:(NSString *)volumePath documentsPath:(NSString *)documentsPath completion:(B2DiskImageSnapshotCompletion)completion;

@end

NS_ASSUME_NONNULL_END
