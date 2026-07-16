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

    // 找气泡
    UIView *bubble = hit;
    while (bubble) {
        if ([NSStringFromClass([bubble class]) hasPrefix:@"WWKConversation"]) break;
        bubble = bubble.superview;
    }
    if (!bubble) return;

    // 提取消息
    id message = [ELKMenuHook msgFromView:bubble] ?: [ELKMenuHook msgInSubviews:bubble];
    if (!message) return;

    NSLog(@"[喵喵] 👆 长按: %@", NSStringFromClass([bubble class]));

    // 直接导出
    [ELKFileExporter exportFileFromMessage:message];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

// 不让我们的手势吃掉触摸
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr
shouldReceiveTouch:(UITouch *)touch {
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

        // 延迟等 UI 就绪
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
    // 只在一个 window 上加
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        // 跳过系统 window
        if (w.hidden || !w.rootViewController) continue;
        if (CGRectIsEmpty(w.bounds) || w.bounds.size.width < 10) continue;
        if ([NSStringFromClass([w class]) hasPrefix:@"UIText"]) continue;

        // 查重
        BOOL exists = NO;
        for (UIGestureRecognizer *gr in w.gestureRecognizers) {
            if ([gr.delegate isKindOfClass:[ELKGestureHandler class]]) { exists = YES; break; }
        }
        if (exists) return;

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:g_handler action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.5;
        lp.cancelsTouchesInView = NO;      // 不拦截触摸
        lp.delaysTouchesBegan = NO;         // 不延迟触摸
        lp.delaysTouchesEnded = NO;
        lp.delegate = g_handler;

        [w addGestureRecognizer:lp];
        NSLog(@"[喵喵] ✅ 手势已添加到 %@", NSStringFromClass([w class]));
        return; // 只加一个
    }

    // 没找到合适的窗口，2 秒后重试
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
                if ([cn hasPrefix:@"WWKMessage"]) return val;
                // 也接受 media 对象
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
