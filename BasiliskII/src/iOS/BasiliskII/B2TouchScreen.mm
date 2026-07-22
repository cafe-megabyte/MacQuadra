//
//  B2TouchScreen.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 18/04/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2TouchScreen.h"
#import "B2ScreenView.h"
#import "B2AppDelegate.h"
#include "sysdeps.h"
#include "adb.h"

@implementation B2TouchScreen
{
    // when using absolute mouse mode, button events are processed before the position is updated
    NSTimeInterval mouseButtonDelay;
    CGPoint previousTouchLoc;
    CGPoint initialTouchLoc;
    NSTimeInterval previousTouchTime;
    NSTimeInterval touchTimeThreshold;
    CGFloat touchDistanceThreshold;
    BOOL shouldClick;
    BOOL isDragging;
    BOOL ignoresMultiTouchSequence;
    NSMutableSet *currentTouches;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        mouseButtonDelay = 0.05;
        touchTimeThreshold = 0.25;
        touchDistanceThreshold = 16;
        currentTouches = [NSMutableSet setWithCapacity:4];
    }
    return self;
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    ADBSetRelMouseMode(false);
}

- (Point)mouseLocForCGPoint:(CGPoint)point {
    Point mouseLoc;
    CGRect screenBounds = sharedScreenView.screenBounds;
    CGSize screenSize = sharedScreenView.screenSize;
    mouseLoc.h = (point.x - screenBounds.origin.x) * (screenSize.width/screenBounds.size.width);
    mouseLoc.v = (point.y - screenBounds.origin.y) * (screenSize.height/screenBounds.size.height);
    return mouseLoc;
}

- (void)mouseDown {
    ADBMouseDown(0);
}

- (void)mouseUp {
    ADBMouseUp(0);
}

- (void)mouseClick {
    if (isDragging) {
        return;
    }
    ADBMouseDown(0);
    [self performSelector:@selector(mouseUp) withObject:nil afterDelay:2.0/60.0];
}

- (void)cancelScheduledClickEvents {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(mouseClick) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(mouseDown) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(mouseUp) object:nil];
}

- (void)cancelScheduledHoldDrag {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(beginDraggingFromInitialTouch) object:nil];
}

- (void)cancelActiveTouchSequence {
    [self cancelScheduledHoldDrag];
    [self cancelScheduledClickEvents];
    if (isDragging) {
        [self stopDragging];
    }
    shouldClick = NO;
    ignoresMultiTouchSequence = YES;
}

- (CGPoint)touchPointForTouches:(NSSet *)touches fallbackEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject ?: [event touchesForView:self].anyObject;
    return [touch locationInView:self];
}

- (BOOL)touchPointExceedsDragThreshold:(CGPoint)touchLoc {
    return fabs(initialTouchLoc.x - touchLoc.x) >= touchDistanceThreshold ||
           fabs(initialTouchLoc.y - touchLoc.y) >= touchDistanceThreshold;
}

- (void)moveMouseToTouchPoint:(CGPoint)touchLoc {
    Point mouseLoc = [self mouseLocForCGPoint:touchLoc];
    ADBMouseMoved(mouseLoc.h, mouseLoc.v);
}

- (void)startDraggingAtTouchPoint:(CGPoint)touchLoc {
    [self cancelScheduledHoldDrag];
    isDragging = YES;
    shouldClick = NO;
    ADBMouseDown(0);
    [self moveMouseToTouchPoint:touchLoc];
}

- (void)beginDraggingFromInitialTouch {
    if (shouldClick && currentTouches.count > 0 && !isDragging) {
        [self startDraggingAtTouchPoint:initialTouchLoc];
    }
}

- (void)stopDragging {
    isDragging = NO;
    shouldClick = NO;
    ADBMouseUp(0);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [currentTouches unionSet:touches];
    if (![B2AppDelegate sharedInstance].emulatorRunning) return;
    if (currentTouches.count > 1) {
        [self cancelActiveTouchSequence];
        return;
    }
    if (ignoresMultiTouchSequence) return;
    CGPoint touchLoc = [self touchPointForTouches:touches fallbackEvent:event];
    [self cancelScheduledHoldDrag];
    shouldClick = YES;
    isDragging = NO;
    initialTouchLoc = touchLoc;
    [self moveMouseToTouchPoint:touchLoc];
    [self performSelector:@selector(beginDraggingFromInitialTouch) withObject:nil afterDelay:touchTimeThreshold];
    previousTouchLoc = touchLoc;
    previousTouchTime = event.timestamp;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (![B2AppDelegate sharedInstance].emulatorRunning) return;
    if (ignoresMultiTouchSequence) return;
    CGPoint touchLoc = [self touchPointForTouches:touches fallbackEvent:event];
    if (isDragging) {
        [self moveMouseToTouchPoint:touchLoc];
    } else if (shouldClick && [self touchPointExceedsDragThreshold:touchLoc]) {
        [self startDraggingAtTouchPoint:touchLoc];
    }
    previousTouchLoc = touchLoc;
    previousTouchTime = event.timestamp;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [currentTouches minusSet:touches];
    if (![B2AppDelegate sharedInstance].emulatorRunning) return;
    if (ignoresMultiTouchSequence) {
        if (currentTouches.count == 0) {
            ignoresMultiTouchSequence = NO;
        }
        shouldClick = NO;
        return;
    }
    if (currentTouches.count > 0) return;
    [self cancelScheduledHoldDrag];
    CGPoint touchLoc = [self touchPointForTouches:touches fallbackEvent:event];
    if (isDragging) {
        [self moveMouseToTouchPoint:touchLoc];
        [self stopDragging];
    } else if (shouldClick) {
        [self moveMouseToTouchPoint:initialTouchLoc];
        [self mouseClick];
    }
    shouldClick = NO;
    previousTouchLoc = touchLoc;
    previousTouchTime = event.timestamp;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [currentTouches minusSet:touches];
    [self cancelScheduledHoldDrag];
    [self cancelScheduledClickEvents];
    if (isDragging) {
        [self stopDragging];
    }
    shouldClick = NO;
    if (currentTouches.count == 0) {
        ignoresMultiTouchSequence = NO;
    }
}

@end
