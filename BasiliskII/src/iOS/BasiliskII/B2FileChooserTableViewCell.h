//
//  B2FileChooserTableViewCell.h
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 29/03/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import <UIKit/UIKit.h>

@class B2FileChooser;

@interface B2FileChooserTableViewCell : UITableViewCell

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, weak) B2FileChooser *fileChooser;

- (void)share:(id)sender;
- (void)rename:(id)sender;

@end
