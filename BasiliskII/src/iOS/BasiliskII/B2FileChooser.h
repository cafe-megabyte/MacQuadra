//
//  B2FileChooser.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 14/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol B2FileChooserDelegate;

@interface B2FileChooser : UITableViewController

@property (nonatomic, copy) NSString *path;
@property (weak, nullable) id<B2FileChooserDelegate> delegate;
@property (nonatomic, assign) BOOL showDirectories;
@property (nonatomic, assign) BOOL showHiddenFiles;
@property (nonatomic, assign) NSStringCompareOptions sortOptions;

- (void)refresh:(id)sender;
- (void)selectItem:(NSString*)path;

@end

@protocol B2FileChooserDelegate <NSObject>

@optional

- (void)fileChooser:(B2FileChooser*)fileChooser didChooseFile:(NSString *)path;
- (void)fileChooser:(B2FileChooser*)fileChooser didChooseDirectory:(NSString*)path;
- (BOOL)fileChooser:(B2FileChooser*)fileChooser shouldShowFile:(NSString *)path;
- (BOOL)fileChooser:(B2FileChooser*)fileChooser canDeletePath:(NSString *)path;
- (BOOL)fileChooser:(B2FileChooser*)fileChooser canMovePath:(NSString *)path;
- (void)fileChooserWillRefresh:(B2FileChooser *)fileChooser;
- (void)fileChooserDidRefresh:(B2FileChooser *)fileChooser;
- (UIImage*)fileChooser:(B2FileChooser *)fileChooser iconForFile:(NSString *)path isDirectory:(BOOL)isDirectory;

@end

NS_ASSUME_NONNULL_END
