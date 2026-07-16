//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（自建长按菜单版）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

// ── 前向声明 ──
@interface ELKMenuHook (Private)
+ (id)findMessageFromResponder:(UIResponder *)r;
@end

// ============================================================
//  1. 自定义长按手势 — 完全独立于 App 的菜单系统
// ============================================================
@interface ELKLongPressHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation ELKLongPressHandler

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;

    UIView *view = gr.view;
    CGPoint point = [gr locationInView:view];

    // 找到被按的视图
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

    // 尝试从气泡中提取消息对象
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
        // 在气泡的子视图中搜索
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

        // iPad 兼容
        UIPopoverPresentationController *pop = sheet.popoverPresentationController;
        if (pop) {
            pop.sourceView = bubble;
            pop.sourceRect = bubble.bounds;
        }

        // 找到当前顶层 VC
        UIViewController *topVC = [ELKRuntimeHelper topViewController];
        if (topVC) {
            [topVC presentViewController:sheet animated:YES completion:nil];
        }
    }
}

// 允许与 App 自己的手势同时存在
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
        NSLog(@"[喵喵插件] 🚀 install 自建长按菜单方案");

        g_handler = [[ELKLongPressHandler alloc] init];

        // 在所有 window 上加长按手势
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
    // 遍历所有 window，找到包含聊天气泡的视图，加手势
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        if ([self addGestureIfHasBubbles:win depth:0]) break;
    }

    // 如果没找到，延迟再试
    if (!g_handler) return;

    // 定期重试，确保新打开的聊天窗口也能加手势
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self addGestureToConversationViews];
    });
}

+ (BOOL)addGestureIfHasBubbles:(UIView *)view depth:(int)depth {
    if (depth > 20) return NO;

    for (UIView *sub in view.subviews) {
        NSString *cn = NSStringFromClass([sub class]);
        if ([cn hasPrefix:@"WWKConversation"]) {
            // 找到气泡了！给顶层视图加手势
            UIView *target = view; // 给包含气泡的父视图加手势

            // 检查是否已经加过
            for (UIGestureRecognizer *gr in target.gestureRecognizers) {
                if ([gr isKindOfClass:[UILongPressGestureRecognizer class]] &&
                    [gr.delegate isKindOfClass:[ELKLongPressHandler class]]) {
                    return YES; // 已经加过了
                }
            }

            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                initWithTarget:g_handler action:@selector(handleLongPress:)];
            lp.minimumPressDuration = 0.5;
            lp.cancelsTouchesInView = NO;  // 不干扰 App 自己的手势
            lp.delegate = g_handler;
            [target addGestureRecognizer:lp];

            NSLog(@"[喵喵插件] ✅ 长按手势已添加到 %@ (因为有 %@)",
                  NSStringFromClass([target class]), cn);
            return YES;
        }

        if ([self addGestureIfHasBubbles:sub depth:depth + 1]) return YES;
    }
    return NO;
}

@end
