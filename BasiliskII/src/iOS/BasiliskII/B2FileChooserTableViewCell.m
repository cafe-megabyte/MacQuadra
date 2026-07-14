//
//  B2FileChooserTableViewCell.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 29/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2FileChooserTableViewCell.h"
#import "B2FileChooser.h"

@interface B2FileChooser (Private)
- (NSArray*)filteredContentsOfDirectory:(NSString*)path;
- (void)askDeleteFile:(NSString*)filePath;
- (void)askRenameFile:(NSString*)filePath;
- (void)shareFile:(NSString*)filePath;
@end

@implementation B2FileChooserTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.textLabel.minimumScaleFactor = 0.75;
        self.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.imageView.image = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
}

- (void)setFilePath:(NSString *)filePath {
    _filePath = filePath.copy;
    
    NSString *fileName = filePath.lastPathComponent;
    self.textLabel.text = fileName;
    NSDictionary *attributes = [[NSURL fileURLWithPath:filePath] resourceValuesForKeys:@[NSURLIsDirectoryKey, NSURLTotalFileSizeKey] error:NULL];
    if (attributes == nil) {
        self.accessoryType = UITableViewCellAccessoryNone;
        self.detailTextLabel.text = L(@"misc.error");
        return;
    }
    BOOL isDirectory = [attributes[NSURLIsDirectoryKey] boolValue];
    if (isDirectory) {
        NSUInteger count = [self.fileChooser filteredContentsOfDirectory:filePath].count;
        NSString *sizeString = count == 1 ? L(@"dir.items.1") : LX(@"dir.items.n", @(count));
        self.detailTextLabel.text = sizeString;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSString *sizeString = [NSByteCountFormatter stringFromByteCount:[attributes[NSURLTotalFileSizeKey] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
        self.detailTextLabel.text = sizeString;
        self.accessoryType = UITableViewCellAccessoryNone;
    }
    
    if ([self.fileChooser.delegate respondsToSelector:@selector(fileChooser:iconForFile:isDirectory:)]) {
        self.imageView.image = [self.fileChooser.delegate fileChooser:self.fileChooser iconForFile:filePath isDirectory:isDirectory];
    }
}

- (void)share:(id)sender {
    [self.fileChooser shareFile:self.filePath];
}

- (void)rename:(id)sender {
    [self.fileChooser askRenameFile:self.filePath];

}

- (void)delete:(id)sender {
    [self.fileChooser askDeleteFile:self.filePath];
}

@end
