//
//  B2TrackPad.m
//  BasiliskII
//
//  Created by Jesús A. Álvarez on 18/04/2016.
//  Copyright © 2016 namedfork. All rights reserved.
//

#import "B2TrackPad.h"
#import "B2AppDelegate.h"
#include "sysdeps.h"
#include "adb.h"
#import <AudioToolbox/AudioToolbox.h>

#define TRACKPAD_ACCEL_N 1
#define TRACKPAD_ACCEL_T 0.2
#define TRACKPAD_ACCEL_D 20

@implementation B2TrackPad
{
    NSTimeInterval touchTimeThreshold;
    NSTimeInterval mouseClickDelay;
    NSTimeInterval previousClickTime, previousTouchTime, currentTouchStartTime;
    CGFloat touchDistanceThreshold;
    CGPoint previousTouchLoc, previousClickLoc, currentTouchStartLoc;
    NSUInteger queuedClickCount;
    BOOL shouldClick;
    BOOL isDragging;
    BOOL isSecondTap;
    BOOL clickInProgress;
    BOOL pendingDragStart;
    BOOL supportsForceTouch, didForceClick;
    BOOL ignoresMultiTouchSequence;
    NSMutableSet *currentTouches;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        touchTimeThreshold = 0.25;
        mouseClickDelay = 0.15;
        touchDistanceThreshold = 16;
        currentTouches = [NSMutableSet setWithCapacity:4];
        self.multipleTouchEnabled = YES;
    }
    return self;
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];
    if (newSuperview == nil) {
        [self cancelSecondTapDragHold];
        [self cancelQueuedClicks];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(beginPendingDrag) object:nil];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishQueuedClick) object:nil];
        if (isDragging || clickInProgress) {
            [self mouseUp];
        }
        isDragging = NO;
        clickInProgress = NO;
        pendingDragStart = NO;
        return;
    }
    @try {
        supportsForceTouch = (newSuperview.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable);
    } @catch (NSException *exception) {
        supportsForceTouch = NO;
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [currentTouches unionSet:touches];
    if (currentTouches.count > 1) {
        [self cancelActiveTouchSequence];
        return;
    }
    if (ignoresMultiTouchSequence) return;
    if (currentTouches.count == 1) {
        [self firstTouchBegan:touches.anyObject withEvent:event];
    }
}

- (void)firstTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint touchLoc = [touch locationInView:self];
    shouldClick = YES;
    currentTouchStartTime = event.timestamp;
    currentTouchStartLoc = touchLoc;
    isSecondTap = (event.timestamp - previousClickTime < touchTimeThreshold) &&
                  fabs(previousClickLoc.x - touchLoc.x) < touchDistanceThreshold &&
                  fabs(previousClickLoc.y - touchLoc.y) < touchDistanceThreshold;
    if (isSecondTap) {
        // A quick second tap is a click; only a hold or a larger move begins dragging.
        [self performSelector:@selector(beginDraggingFromSecondTap) withObject:nil afterDelay:touchTimeThreshold];
    }
    previousTouchTime = event.timestamp;
    previousTouchLoc = touchLoc;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (![B2AppDelegate sharedInstance].emulatorRunning) return;
    if (ignoresMultiTouchSequence) return;
    
    UITouch *touch = touches.anyObject;
    CGPoint touchLoc = [touch locationInView:self];
    previousTouchLoc = [touch previousLocationInView:self];
    if (isSecondTap && !isDragging && !pendingDragStart) {
        if (fabs(currentTouchStartLoc.x - touchLoc.x) < touchDistanceThreshold &&
            fabs(currentTouchStartLoc.y - touchLoc.y) < touchDistanceThreshold) {
            previousTouchTime = event.timestamp;
            previousTouchLoc = touchLoc;
            return;
        }
        [self cancelSecondTapDragHold];
        isSecondTap = NO;
        [self startDragging];
    }
    // acceleration
    CGPoint locDiff = CGPointMake(touchLoc.x - previousTouchLoc.x, touchLoc.y - previousTouchLoc.y);
    NSTimeInterval timeDiff = 100 * (event.timestamp - previousTouchTime);
    NSTimeInterval accel = TRACKPAD_ACCEL_N / (TRACKPAD_ACCEL_T + ((timeDiff * timeDiff)/TRACKPAD_ACCEL_D));
    locDiff.x *= accel;
    locDiff.y *= accel;

    if (!CGPointEqualToPoint(touchLoc, previousTouchLoc)) {
        shouldClick = NO;
        ADBSetRelMouseMode(true);
        ADBMouseMoved((int)locDiff.x, (int)locDiff.y);
    }
    
    previousTouchTime = event.timestamp;
    previousTouchLoc = touchLoc;
    
    if (supportsForceTouch) {
        [self handleForceClick:touch];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [currentTouches minusSet:touches];
    [self cancelSecondTapDragHold];
    if (ignoresMultiTouchSequence) {
        if (currentTouches.count == 0) {
            ignoresMultiTouchSequence = NO;
        }
        shouldClick = NO;
        return;
    }
    if (currentTouches.count > 0) {
        return;
    } else if (didForceClick) {
        AudioServicesPlaySystemSound(1519);
        didForceClick = NO;
        [self cancelQueuedClicks];
        pendingDragStart = NO;
        if (isDragging) {
            [self stopDragging];
        }
        previousClickTime = 0;
        return;
    }
    
    CGPoint touchLoc = [touches.anyObject locationInView:self];
    if (shouldClick && (event.timestamp - currentTouchStartTime < touchTimeThreshold)) {
        [self queueClickWithDelay:(isSecondTap ? 0 : mouseClickDelay)];
        previousClickTime = event.timestamp;
        previousClickLoc = touchLoc;
    } else {
        previousClickTime = 0;
    }
    shouldClick = NO;
    if (isDragging) {
        [self stopDragging];
    }
    pendingDragStart = NO;
    isSecondTap = NO;
    
    previousTouchLoc = touchLoc;
    previousTouchTime = event.timestamp;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [currentTouches minusSet:touches];
    [self cancelSecondTapDragHold];
    [self cancelQueuedClicks];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(beginPendingDrag) object:nil];
    if (isDragging) {
        [self stopDragging];
    }
    shouldClick = NO;
    isSecondTap = NO;
    pendingDragStart = NO;
    previousClickTime = 0;
    didForceClick = NO;
    if (currentTouches.count == 0) {
        ignoresMultiTouchSequence = NO;
    }
}

- (void)startDragging {
    [self cancelQueuedClicks];
    shouldClick = NO;
    previousClickTime = 0;
    if (clickInProgress) {
        pendingDragStart = YES;
        return;
    }
    pendingDragStart = NO;
    isDragging = YES;
    ADBMouseDown(0);
}

- (void)beginDraggingFromSecondTap {
    if (isSecondTap && shouldClick && currentTouches.count > 0 && !ignoresMultiTouchSequence) {
        [self startDragging];
    }
}

- (void)cancelSecondTapDragHold {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(beginDraggingFromSecondTap) object:nil];
}

- (void)beginPendingDrag {
    if (pendingDragStart && currentTouches.count > 0 && !ignoresMultiTouchSequence) {
        [self startDragging];
    }
    pendingDragStart = NO;
}

- (void)cancelActiveTouchSequence {
    [self cancelSecondTapDragHold];
    [self cancelQueuedClicks];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(beginPendingDrag) object:nil];
    if (isDragging) {
        [self stopDragging];
    }
    shouldClick = NO;
    isSecondTap = NO;
    pendingDragStart = NO;
    previousClickTime = 0;
    didForceClick = NO;
    ignoresMultiTouchSequence = YES;
}

- (void)stopDragging {
    isDragging = NO;
    shouldClick = NO;
    ADBMouseUp(0);
}

- (void)handleForceClick:(UITouch *)touch {
    if (touch.force > 3.0 && !didForceClick) {
        AudioServicesPlaySystemSound(1519);
        didForceClick = YES;
        [self startDragging];
    }
}

- (void)queueClickWithDelay:(NSTimeInterval)delay {
    // Keep both taps even when the second one arrives before the first click is sent.
    BOOL queueWasIdle = (queuedClickCount == 0 && !clickInProgress);
    queuedClickCount++;
    if (queueWasIdle) {
        [self performSelector:@selector(sendNextQueuedClick) withObject:nil afterDelay:delay];
    }
}

- (void)sendNextQueuedClick {
    if (queuedClickCount == 0 || isDragging || pendingDragStart) return;
    queuedClickCount--;
    clickInProgress = YES;
    ADBMouseDown(0);
    [self performSelector:@selector(finishQueuedClick) withObject:nil afterDelay:2.0/60.0];
}

- (void)finishQueuedClick {
    ADBMouseUp(0);
    clickInProgress = NO;
    if (pendingDragStart) {
        [self performSelector:@selector(beginPendingDrag) withObject:nil afterDelay:2.0/60.0];
    } else if (queuedClickCount > 0) {
        [self performSelector:@selector(sendNextQueuedClick) withObject:nil afterDelay:2.0/60.0];
    }
}

- (void)cancelQueuedClicks {
    queuedClickCount = 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendNextQueuedClick) object:nil];
}

- (void)mouseUp {
    ADBMouseUp(0);
}

@end
