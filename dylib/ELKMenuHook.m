//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（单手势方案）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

@interface ELKMenuHook (Private)
+ (id)msgFromView:(UIView *)v;
+ (id)msgInSubviews:(UIView *)root;
@end

// ============================================================
@interface ELKGestureHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation ELKGestureHandler

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;

    UIView *rootView = gr.view;
    CGPoint point = [gr locationInView:rootView];
    UIView *hit = [rootView hitTest:point withEvent:nil];
    if (!hit) return;

    UIView *bubble = hit;
    while (bubble) {
        if ([NSStringFromClass([bubble class]) hasPrefix:@"WWKConversation"]) break;
        bubble = bubble.superview;
    }
    if (!bubble) return;

    id message = [ELKMenuHook msgFromView:bubble] ?: [ELKMenuHook msgInSubviews:bubble];
    if (!message) return;

    NSLog(@"[喵喵] 👆 长按: %@", NSStringFromClass([bubble class]));
    [ELKFileExporter exportFileFromMessage:message];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

@end

static ELKGestureHandler *g_handler = nil;

// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install（单手势方案）");

        g_handler = [[ELKGestureHandler alloc] init];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self tryAddGesture];
        });

        NSLog(@"[喵喵] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ %@", e);
    }
}

+ (void)tryAddGesture {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden || !w.rootViewController) continue;
        if (w.bounds.size.width < 100 || w.bounds.size.height < 100) continue;

        BOOL exists = NO;
        for (UIGestureRecognizer *gr in w.gestureRecognizers) {
            if ([gr.delegate isKindOfClass:[ELKGestureHandler class]]) { exists = YES; break; }
        }
        if (exists) return;

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:g_handler action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.5;
        lp.cancelsTouchesInView = NO;
        lp.delaysTouchesBegan = NO;
        lp.delaysTouchesEnded = NO;
        lp.delegate = g_handler;

        [w addGestureRecognizer:lp];
        NSLog(@"[喵喵] ✅ 手势已添加");
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self tryAddGesture];
    });
}

+ (id)msgFromView:(UIView *)v {
    if (!v) return nil;
    for (NSString *key in @[@"message", @"messageItem", @"messageMedia", @"bubbleData"]) {
        @try {
            id val = [v valueForKey:key];
            if (val) {
                NSString *cn = NSStringFromClass([val class]);
                if ([cn hasPrefix:@"WWKMessage"] || [cn containsString:@"Media"]) return val;
            }
        } @catch (...) {}
    }
    return nil;
}

+ (id)msgInSubviews:(UIView *)root {
    if (!root) return nil;
    for (UIView *sub in root.subviews) {
        id m = [self msgFromView:sub] ?: [self msgInSubviews:sub];
        if (m) return m;
    }
    return nil;
}

@end
