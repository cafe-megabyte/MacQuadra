//
//  B2PrivateResources.h
//  BasiliskII
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface B2PrivateResources : NSObject

@property (class, readonly, strong) B2PrivateResources *sharedInstance NS_SWIFT_NAME(shared);
- (BOOL)prepareResourcesIfNeededFromViewController:(UIViewController *)viewController completion:(nullable dispatch_block_t)completion NS_SWIFT_NAME(prepareResourcesIfNeeded(from:completion:));

@end

NS_ASSUME_NONNULL_END
