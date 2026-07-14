//
//  B2DesktopDatabase.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 12/04/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2DesktopDatabase.h"
#import "res.h"
#import "NSString+OSType.h"
#import <sys/xattr.h>


// Macintosh 1 bit palette
static uint32_t ctb1[2] = {0xFFFFFF, 0x000000};

// Macintosh 4 bit palette
static uint32_t ctb4[16] = {
    0xFFFFFF, 0xFFFF00, 0xFF6600, 0xDD0000, 0xFF0099, 0x330099, 0x0000DD, 0x0099FF,
    0x00BB00, 0x006600, 0x663300, 0x996633, 0xCCCCCC, 0x888888, 0x444444, 0x000000
};
// Macintosh 8 bit palette
static uint32_t ctb8[256] = {
    0xFFFFFF, 0xFFFFCC, 0xFFFF99, 0xFFFF66, 0xFFFF33, 0xFFFF00, 0xFFCCFF, 0xFFCCCC,
    0xFFCC99, 0xFFCC66, 0xFFCC33, 0xFFCC00, 0xFF99FF, 0xFF99CC, 0xFF9999, 0xFF9966,
    0xFF9933, 0xFF9900, 0xFF66FF, 0xFF66CC, 0xFF6699, 0xFF6666, 0xFF6633, 0xFF6600,
    0xFF33FF, 0xFF33CC, 0xFF3399, 0xFF3366, 0xFF3333, 0xFF3300, 0xFF00FF, 0xFF00CC,
    0xFF0099, 0xFF0066, 0xFF0033, 0xFF0000, 0xCCFFFF, 0xCCFFCC, 0xCCFF99, 0xCCFF66,
    0xCCFF33, 0xCCFF00, 0xCCCCFF, 0xCCCCCC, 0xCCCC99, 0xCCCC66, 0xCCCC33, 0xCCCC00,
    0xCC99FF, 0xCC99CC, 0xCC9999, 0xCC9966, 0xCC9933, 0xCC9900, 0xCC66FF, 0xCC66CC,
    0xCC6699, 0xCC6666, 0xCC6633, 0xCC6600, 0xCC33FF, 0xCC33CC, 0xCC3399, 0xCC3366,
    0xCC3333, 0xCC3300, 0xCC00FF, 0xCC00CC, 0xCC0099, 0xCC0066, 0xCC0033, 0xCC0000,
    0x99FFFF, 0x99FFCC, 0x99FF99, 0x99FF66, 0x99FF33, 0x99FF00, 0x99CCFF, 0x99CCCC,
    0x99CC99, 0x99CC66, 0x99CC33, 0x99CC00, 0x9999FF, 0x9999CC, 0x999999, 0x999966,
    0x999933, 0x999900, 0x9966FF, 0x9966CC, 0x996699, 0x996666, 0x996633, 0x996600,
    0x9933FF, 0x9933CC, 0x993399, 0x993366, 0x993333, 0x993300, 0x9900FF, 0x9900CC,
    0x990099, 0x990066, 0x990033, 0x990000, 0x66FFFF, 0x66FFCC, 0x66FF99, 0x66FF66,
    0x66FF33, 0x66FF00, 0x66CCFF, 0x66CCCC, 0x66CC99, 0x66CC66, 0x66CC33, 0x66CC00,
    0x6699FF, 0x6699CC, 0x669999, 0x669966, 0x669933, 0x669900, 0x6666FF, 0x6666CC,
    0x666699, 0x666666, 0x666633, 0x666600, 0x6633FF, 0x6633CC, 0x663399, 0x663366,
    0x663333, 0x663300, 0x6600FF, 0x6600CC, 0x660099, 0x660066, 0x660033, 0x660000,
    0x33FFFF, 0x33FFCC, 0x33FF99, 0x33FF66, 0x33FF33, 0x33FF00, 0x33CCFF, 0x33CCCC,
    0x33CC99, 0x33CC66, 0x33CC33, 0x33CC00, 0x3399FF, 0x3399CC, 0x339999, 0x339966,
    0x339933, 0x339900, 0x3366FF, 0x3366CC, 0x336699, 0x336666, 0x336633, 0x336600,
    0x3333FF, 0x3333CC, 0x333399, 0x333366, 0x333333, 0x333300, 0x3300FF, 0x3300CC,
    0x330099, 0x330066, 0x330033, 0x330000, 0x00FFFF, 0x00FFCC, 0x00FF99, 0x00FF66,
    0x00FF33, 0x00FF00, 0x00CCFF, 0x00CCCC, 0x00CC99, 0x00CC66, 0x00CC33, 0x00CC00,
    0x0099FF, 0x0099CC, 0x009999, 0x009966, 0x009933, 0x009900, 0x0066FF, 0x0066CC,
    0x006699, 0x006666, 0x006633, 0x006600, 0x0033FF, 0x0033CC, 0x003399, 0x003366,
    0x003333, 0x003300, 0x0000FF, 0x0000CC, 0x000099, 0x000066, 0x000033, 0xEE0000,
    0xDD0000, 0xBB0000, 0xAA0000, 0x880000, 0x770000, 0x550000, 0x440000, 0x220000,
    0x110000, 0x00EE00, 0x00DD00, 0x00BB00, 0x00AA00, 0x008800, 0x007700, 0x005500,
    0x004400, 0x002200, 0x001100, 0x0000EE, 0x0000DD, 0x0000BB, 0x0000AA, 0x000088,
    0x000077, 0x000055, 0x000044, 0x000022, 0x000011, 0xEEEEEE, 0xDDDDDD, 0xBBBBBB,
    0xAAAAAA, 0x888888, 0x777777, 0x555555, 0x444444, 0x222222, 0x111111, 0x000000
};

@implementation B2DesktopDatabase
{
    RFILE *desktopFile;
    NSMutableDictionary<NSNumber*,NSMutableDictionary<NSNumber*,id>*> *desktopBundles;
    NSMutableDictionary<NSString*,UIImage*> *customIcons;
}

- (instancetype)initWithDesktopFile:(NSString *)path {
    if ((self = [super init])) {
        customIcons = [NSMutableDictionary dictionaryWithCapacity:4];
        size_t resSize;
        void *resData = [self _resourceForkForFile:path size:&resSize];
        desktopFile = res_open_mem(resData, resSize, 0);
        if (desktopFile == NULL) {
            return nil;
        }
        // read FREF to type mapping
        NSMutableDictionary<NSNumber*,NSNumber*> *frefType = [NSMutableDictionary dictionaryWithCapacity:res_count(desktopFile, 'FREF')];
        [[self resourcesOfType:'FREF'] enumerateKeysAndObjectsUsingBlock:^(NSNumber *rsrcID, NSData *data, BOOL *stop) {
            if (data.length >= 4) {
                frefType[rsrcID] = @(OSReadBigInt32(data.bytes, 0));
            }
        }];
        // read bundles
        desktopBundles = [NSMutableDictionary dictionaryWithCapacity:res_count(desktopFile, 'BNDL')];
        for (NSData *bundle in [self resourcesOfType:'BNDL'].allValues) {
            if (bundle.length < 8) {
                continue;
            }
            OSType signature = OSReadBigInt32(bundle.bytes, 0x00);
            int16_t numTypes = OSReadBigInt16(bundle.bytes, 0x06) + 1;
            int16_t typeBase = 0x08;
            NSDictionary<NSNumber*,NSNumber*> *frefMap, *iconMap; // local to resource ID
            for (int16_t t = 0; t < numTypes; t++) {
                if (bundle.length < typeBase + 6) {
                    break;
                }
                OSType type = OSReadBigInt32(bundle.bytes, typeBase);
                int16_t numOfType = OSReadBigInt16(bundle.bytes, typeBase + 4) + 1;
                if (bundle.length < typeBase + 6 + numOfType * 4) {
                    break;
                }
                NSMutableDictionary *typeMap = [NSMutableDictionary dictionaryWithCapacity:numOfType];
                for (int16_t i = 0; i < numOfType; i++) {
                    NSNumber *localID = @(OSReadBigInt16(bundle.bytes, typeBase + 6 + (4 * i)));
                    NSNumber *rsrcID = @(OSReadBigInt16(bundle.bytes, typeBase + 6 + (4 * i) + 2));
                    typeMap[localID] = rsrcID;
                }
                if (type == 'FREF') {
                    frefMap = typeMap;
                } else if (type == 'ICN#') {
                    iconMap = typeMap;
                }
                typeBase += 6 + numOfType * 4;
            }
            if (iconMap == NULL || frefMap == NULL) {
                continue;
            }
            NSMutableDictionary<NSNumber*,id> *typeToIcon = [NSMutableDictionary dictionaryWithCapacity:iconMap.count];
            [iconMap enumerateKeysAndObjectsUsingBlock:^(NSNumber *localID, NSNumber *iconID, BOOL *stop) {
                NSNumber *frefID = frefMap[localID];
                if (frefID == nil) {
                    return;
                }
                NSNumber *type = frefType[frefID];
                if (type == nil) {
                    return;
                }
                typeToIcon[type] = iconID;
            }];
            desktopBundles[@(signature)] = typeToIcon;
        }
    }
    return self;
}

- (void)dealloc {
    if (desktopFile) {
        res_close(desktopFile);
    }
}

- (NSDictionary<NSNumber*,NSData*>*)resourcesOfType:(OSType)type {
    size_t length;
    ResAttr *list = res_list(desktopFile, type, NULL, 0, 0, &length, NULL);
    if (list == NULL) {
        return nil;
    }
    NSMutableDictionary<NSNumber*,NSData*> *resources = [NSMutableDictionary dictionaryWithCapacity:length];
    for (size_t i=0; i < length; i++) {
        void *res = res_read(desktopFile, type, list[i].ID, NULL, 0, 0, NULL, NULL);
        resources[@(list[i].ID)] = [NSData dataWithBytesNoCopy:res length:list[i].size freeWhenDone:YES];
    }
    free(list);
    return resources;
}

- (NSDictionary*)iconFamilyID:(int16_t)famID inResourceFile:(RFILE*)rfile {
    if (rfile == NULL) {
        return nil;
    }
    NSMutableDictionary *iconFamily = [NSMutableDictionary dictionaryWithCapacity:6];
    NSData *iconData, *maskData;
    size_t resSize;
    
    const uint32_t iconResourceTypes[] = {'ICN#', 'icl4', 'icl8', 'ics#', 'ics4', 'ics8', 0};
    for(int i=0; iconResourceTypes[i]; i++) {
        void *iconRsrc = res_read(rfile, iconResourceTypes[i], famID, NULL, 0, 0, &resSize, NULL);
        if (iconRsrc == NULL) continue;
        [iconFamily setObject:[NSData dataWithBytes:iconRsrc length:resSize] forKey:[NSString stringWithFormat:@"%c%c%c%c", TYPECHARS(iconResourceTypes[i])]];
        free(iconRsrc);
    }
    
    // mask pseudo-resources
    if ((iconData = [iconFamily objectForKey:@"ICN#"])) {
        maskData = [iconData subdataWithRange:NSMakeRange(0x80, 0x80)];
        [iconFamily setObject:maskData forKey:@"IMK#"];
    }
    if ((iconData = [iconFamily objectForKey:@"ics#"])) {
        maskData = [iconData subdataWithRange:NSMakeRange(0x20, 0x20)];
        [iconFamily setObject:maskData forKey:@"imk#"];
    }
    
    return iconFamily;
}

- (UIImage*)iconImageFromFamily:(NSDictionary*)iconFamily {
    NSData *iconData, *iconMask;
    if ((iconMask = [iconFamily objectForKey:@"IMK#"])) {
        // has large mask, find best large icon
        if ((iconData = [iconFamily objectForKey:@"icl8"])) {
            return [self iconImageWithData:iconData mask:iconMask size:32 depth:8 scale:_imageScale];
        } else if ((iconData = [iconFamily objectForKey:@"icl4"])) {
            return [self iconImageWithData:iconData mask:iconMask size:32 depth:4 scale:_imageScale];
        } else {
            iconData = [iconFamily objectForKey:@"ICN#"];
            return [self iconImageWithData:iconData mask:iconMask size:32 depth:1 scale:_imageScale];
        }
    } else if ((iconMask = [iconFamily objectForKey:@"imk#"])) {
        // has small mask, find best small icon
        if ((iconData = [iconFamily objectForKey:@"ics8"])) {
            return [self iconImageWithData:iconData mask:iconMask size:32 depth:8 scale:_imageScale];
        } else if ((iconData = [iconFamily objectForKey:@"ics4"])) {
            return [self iconImageWithData:iconData mask:iconMask size:32 depth:4 scale:_imageScale];
        } else {
            iconData = [iconFamily objectForKey:@"ics#"];
            return [self iconImageWithData:iconData mask:iconMask size:32 depth:1 scale:_imageScale];
        }
    }
    return nil;
}

- (UIImage*)iconImageWithData:(NSData*)iconData mask:(NSData*)iconMask size:(int)size depth:(int)depth scale:(CGFloat)scale {
    if (iconData == nil || iconMask == nil) return NULL;
    
    // convert to ARGB
#define _iSETPIXELRGB(px,py,sa,srgb) data[(4*(px+(py*size)))+0] = sa;\
data[(4*(px+(py*size)))+1] = ((srgb >> 16) & 0xFF);\
data[(4*(px+(py*size)))+2] = ((srgb >> 8) & 0xFF);\
data[(4*(px+(py*size)))+3] = (srgb & 0xFF)
    
    CFMutableDataRef pixels = CFDataCreateMutable(kCFAllocatorDefault, 4 * size * size);
    CFDataSetLength(pixels, 4 * size * size);
    unsigned char * data = CFDataGetMutableBytePtr(pixels);
    const unsigned char * pixelData = [iconData bytes];
    const unsigned char * maskData = [iconMask bytes];
    int m, mxy, pxy, rgb;
    if (pixels == NULL) return NULL;
    switch(depth) {
        case 1:
            // 1-bit
            for(int y = 0; y < size; y++) for(int x = 0; x < size; x++) {
                mxy = pxy = (y*(size/8)) + (x/8);
                m = ((maskData[mxy] >> (7-(x%8))) & 0x01)?0xFF:0x00;
                rgb = ctb1[((pixelData[pxy] >> (7-(x%8))) & 0x01)];
                _iSETPIXELRGB(x, y, m, rgb);
            }
            break;
        case 4:
            // 4-bit
            for(int y = 0; y < size; y++) for(int x = 0; x < size; x++) {
                mxy = (y*(size/8)) + (x/8);
                pxy = (y*(size/2)) + (x/2);
                m = ((maskData[mxy] >> (7-(x%8))) & 0x01)?0xFF:0x00;
                rgb = ctb4[(pixelData[pxy] >> 4*(1-x%2)) & 0x0F];
                _iSETPIXELRGB(x, y, m, rgb);
            }
            break;
        case 8:
            // 8-bit
            for(int y = 0; y < size; y++) for(int x = 0; x < size; x++) {
                mxy = (y*(size/8)) + (x/8);
                pxy = (y*size) + x;
                m = ((maskData[mxy] >> (7-(x%8))) & 0x01)?0xFF:0x00;
                rgb = ctb8[pixelData[pxy]];
                _iSETPIXELRGB(x, y, m, rgb);
            }
            break;
    }
    
    // create image
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(pixels);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(size, size, 8, 32, size * 4, colorSpace, kCGImageAlphaFirst | kCGBitmapByteOrder32Big, provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    CFRelease(pixels);
    UIImage *uiImage = [UIImage imageWithCGImage:image scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(image);
    return uiImage;
}

- (UIImage*)iconForFile:(NSString*)path {
    UIImage *iconImage = nil;
    // get type and creator from file
    char attrBuf[32];
    OSType type = 0, creator = 0;
    UInt16 flags = 0;
    if (getxattr(path.fileSystemRepresentation, XATTR_FINDERINFO_NAME, &attrBuf, sizeof attrBuf, 0, 0) == 32) {
        type = OSReadBigInt32(attrBuf, 0);
        creator = OSReadBigInt32(attrBuf, 4);
        flags = OSReadBigInt16(attrBuf, 8);
    }
    
    // custom icon?
    if (flags & 0x0400) {
        iconImage = [self customIconForFile:path];
        if (iconImage != nil) {
            return iconImage;
        }
    }
    
    // resolve type and creator from name
    if (type == 0 && creator == 0 && [self.delegate respondsToSelector:@selector(getFileType:andCreator:forFileName:)]) {
        [self.delegate getFileType:&type andCreator:&creator forFileName:path];
    }
    
    // get icon corresponding to type and creator
    iconImage = [self iconForFileType:type creator:creator];
    if (iconImage != nil) {
        return iconImage;
    }
    
    // default icon
    BOOL isDirectory;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    return isDirectory ? [UIImage imageNamed:@"B2Folder"] : [UIImage imageNamed:@"B2File"];
}

- (UIImage*)iconForFileType:(OSType)type creator:(OSType)creator {
    if (desktopBundles[@(creator)]) {
        id icon = desktopBundles[@(creator)][@(type)];
        if (icon == nil) {
            return nil;
        } else if ([icon isKindOfClass:[UIImage class]]) {
            return icon;
        } else if ([icon isKindOfClass:[NSNumber class]]) {
            NSDictionary *iconFamily = [self iconFamilyID:[icon shortValue] inResourceFile:desktopFile];
            UIImage *iconImage = [self iconImageFromFamily:iconFamily];
            if (iconImage != nil) {
                desktopBundles[@(creator)][@(type)] = iconImage;
            }
            return iconImage;
        }
    }
    return nil;
}

- (UIImage*)customIconForFile:(NSString*)path {
    UIImage *iconImage = customIcons[path];
    if (iconImage) {
        return iconImage;
    }
    size_t resSize = 0;
    void *resFork = [self _resourceForkForFile:path size:&resSize] ?: [self _resourceForkForFile:[path stringByAppendingPathComponent:@"Icon\x0D"] size:&resSize];
    if (resFork == NULL) {
        return nil;
    }
    RFILE *file = res_open_mem(resFork, resSize, 0);
    NSDictionary *iconFamily = [self iconFamilyID:-16455 inResourceFile:file];
    res_close(file);
    iconImage = [self iconImageFromFamily:iconFamily];
    if (iconImage != nil) {
        customIcons[path] = iconImage;
        return iconImage;
    }
    return nil;
}

- (void*)_resourceForkForFile:(NSString*)path size:(size_t*)outResSize {
    ssize_t resSize = getxattr(path.fileSystemRepresentation, XATTR_RESOURCEFORK_NAME, NULL, 0, 0, 0);
    if (resSize <= 0) {
        return NULL;
    }
    void *attrBuf = malloc(resSize);
    getxattr(path.fileSystemRepresentation, XATTR_RESOURCEFORK_NAME, attrBuf, resSize, 0, 0);
    if (outResSize) {
        *outResSize = resSize;
    }
    return attrBuf;
}

@end
