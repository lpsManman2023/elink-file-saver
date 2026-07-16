//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（自建长按菜单版）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

// ── 前向声明（实现在文件末尾） ──
@interface ELKMenuHook (Private)
+ (id)findMessageFromResponder:(UIResponder *)r;
+ (id)msgFromView:(UIView *)v;
+ (id)msgInSubviews:(UIView *)root;
@end

// ============================================================
//  1. 自定义长按手势
// ============================================================
@interface ELKLongPressHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation ELKLongPressHandler

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;

    UIView *view = gr.view;
    CGPoint point = [gr locationInView:view];

    UIView *hit = [view hitTest:point withEvent:nil];
    if (!hit) return;

    // 向上遍历找到消息气泡
    UIView *bubble = hit;
    while (bubble) {
        NSString *cn = NSStringFromClass([bubble class]);
        if ([cn hasPrefix:@"WWKConversation"]) break;
        bubble = bubble.superview;
    }
    if (!bubble) return;

    // 从气泡中提取消息对象
    id message = nil;
    for (NSString *key in @[@"message", @"messageItem", @"messageMedia",
                            @"mediaContext", @"bubbleData", @"data"]) {
        @try {
            id val = [bubble valueForKey:key];
            if (val) {
                NSString *cn = NSStringFromClass([val class]);
                if ([cn hasPrefix:@"WWKMessage"] || [cn containsString:@"Message"]) {
                    message = val;
                    break;
                }
            }
        } @catch (...) {}
    }

    if (!message) {
        message = [ELKMenuHook msgInSubviews:bubble];
    }

    if (message) {
        NSLog(@"[喵喵插件] 🔔 长按消息: %@", NSStringFromClass([message class]));

        UIAlertController *sheet = [UIAlertController
            alertControllerWithTitle:nil message:nil
            preferredStyle:UIAlertControllerStyleActionSheet];

        [sheet addAction:[UIAlertAction actionWithTitle:@"💾 保存到文件"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) {
                [ELKFileExporter exportFileFromMessage:message];
            }]];

        [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
            style:UIAlertActionStyleCancel handler:nil]];

        UIPopoverPresentationController *pop = sheet.popoverPresentationController;
        if (pop) {
            pop.sourceView = bubble;
            pop.sourceRect = bubble.bounds;
        }

        UIViewController *topVC = [ELKRuntimeHelper topViewController];
        if (topVC) {
            [topVC presentViewController:sheet animated:YES completion:nil];
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

@end

static ELKLongPressHandler *g_handler = nil;

// ============================================================
//  2. 主入口
// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵插件] 🚀 install");

        g_handler = [[ELKLongPressHandler alloc] init];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self addGestureToConversationViews];
        });

        NSLog(@"[喵喵插件] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵插件] ❌ install 异常: %@", e);
    }
}

+ (void)addGestureToConversationViews {
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        if ([self addGestureIfHasBubbles:win depth:0]) break;
    }

    // 定期重试，新打开的聊天页也能加上手势
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self addGestureToConversationViews];
    });
}

+ (BOOL)addGestureIfHasBubbles:(UIView *)view depth:(int)depth {
    if (depth > 20) return NO;

    for (UIView *sub in view.subviews) {
        if ([NSStringFromClass([sub class]) hasPrefix:@"WWKConversation"]) {
            UIView *target = view;

            // 已经加过就跳过
            for (UIGestureRecognizer *gr in target.gestureRecognizers) {
                if ([gr isKindOfClass:[UILongPressGestureRecognizer class]] &&
                    [gr.delegate isKindOfClass:[ELKLongPressHandler class]]) {
                    return YES;
                }
            }

            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                initWithTarget:g_handler action:@selector(handleLongPress:)];
            lp.minimumPressDuration = 0.5;
            lp.cancelsTouchesInView = NO;
            lp.delegate = g_handler;
            [target addGestureRecognizer:lp];

            NSLog(@"[喵喵插件] ✅ 手势已添加");
            return YES;
        }

        if ([self addGestureIfHasBubbles:sub depth:depth + 1]) return YES;
    }
    return NO;
}

// ============================================================
//  3. 消息查找
// ============================================================
+ (id)findMessageFromResponder:(UIResponder *)r {
    return nil; // 自建方案用不到
}

+ (id)msgFromView:(UIView *)v {
    if (!v) return nil;
    for (NSString *key in @[@"message", @"messageItem", @"messageMedia",
                            @"mediaContext", @"bubbleData", @"data", @"wwMessage",
                            @"fileMessage", @"imageMessage", @"videoMessage"]) {
        @try {
            id val = [v valueForKey:key];
            if (val) {
                NSString *cn = NSStringFromClass([val class]);
                if ([cn hasPrefix:@"WWKMessage"] || [cn containsString:@"Message"]) return val;
            }
        } @catch (...) {}
    }
    return nil;
}

+ (id)msgInSubviews:(UIView *)root {
    if (!root) return nil;
    for (UIView *sub in root.subviews) {
        id m = [self msgFromView:sub];
        if (m) return m;
        m = [self msgInSubviews:sub];
        if (m) return m;
    }
    return nil;
}

@end
