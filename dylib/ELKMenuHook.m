//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（WWK 菜单直插版）
//
//  策略：Hook 所有 WWKConversation*BubbleView 的 touchesEnded
//  检测长按 → 在 App 菜单出现的同时弹出我们的 ActionSheet
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

// ── 前向声明 ──
@interface ELKMenuHook (Private)
+ (id)msgFromView:(UIView *)v;
+ (id)msgInSubviews:(UIView *)root;
@end

// ============================================================
//  长按检测手势（加在气泡视图本身上）
// ============================================================
@interface ELKBubbleWatcher : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *bubble;
- (void)onLongPress:(UILongPressGestureRecognizer *)gr;
@end

@implementation ELKBubbleWatcher

- (void)onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;

    UIView *bubble = self.bubble;
    if (!bubble) return;

    NSLog(@"[喵喵] 👆 长按气泡: %@", NSStringFromClass([bubble class]));

    // 提取消息
    id message = [ELKMenuHook msgFromView:bubble] ?: [ELKMenuHook msgInSubviews:bubble];

    if (!message) {
        NSLog(@"[喵喵] ⚠️ 未提取到消息对象");
        return;
    }

    // 🔥 延迟 0.3 秒弹出，等 App 自己的菜单先起来
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // 直接导出，不再弹二级菜单
        [ELKFileExporter exportFileFromMessage:message];
    });
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES; // 与 App 自己的长按手势共存
}

@end

// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install（气泡注入手势方案）");

        // 延迟等 UI 加载完
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self scanAndInject:0];
        });

        NSLog(@"[喵喵] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ install 异常: %@", e);
    }
}

+ (void)scanAndInject:(int)retryCount {
    // 遍历所有窗口
    int injected = 0;
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        injected += [self injectBubblesInView:win depth:0];
    }

    NSLog(@"[喵喵] 📊 本轮注入: %d 个气泡", injected);

    // 最多重试 6 次 (30秒)
    if (injected == 0 && retryCount < 6) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self scanAndInject:retryCount + 1];
        });
    }
}

+ (int)injectBubblesInView:(UIView *)view depth:(int)depth {
    if (depth > 30) return 0;
    int count = 0;

    for (UIView *sub in view.subviews) {
        NSString *cn = NSStringFromClass([sub class]);

        // 找到聊天气泡
        if ([cn hasPrefix:@"WWKConversation"] && [cn hasSuffix:@"BubbleView"]) {
            // 检查是否已经注过
            BOOL hasOurs = NO;
            for (UIGestureRecognizer *gr in sub.gestureRecognizers) {
                if ([gr.delegate isKindOfClass:[ELKBubbleWatcher class]]) {
                    hasOurs = YES; break;
                }
            }
            if (!hasOurs) {
                ELKBubbleWatcher *watcher = [[ELKBubbleWatcher alloc] init];
                watcher.bubble = sub;

                UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                    initWithTarget:watcher action:@selector(onLongPress:)];
                lp.minimumPressDuration = 0.4;
                lp.delegate = watcher;

                [sub addGestureRecognizer:lp];
                count++;
            }
        }

        // 继续递归
        count += [self injectBubblesInView:sub depth:depth + 1];
    }

    return count;
}

+ (id)msgFromView:(UIView *)v {
    if (!v) return nil;
    NSArray *keys = @[@"message", @"messageItem", @"messageMedia", @"bubbleData",
                      @"fileMessage", @"imageMessage", @"videoMessage", @"data"];
    for (NSString *key in keys) {
        @try {
            id val = [v valueForKey:key];
            if (val) {
                NSString *cn = NSStringFromClass([val class]);
                if ([cn hasPrefix:@"WWKMessage"] || [cn containsString:@"Message"] || [cn containsString:@"Media"]) {
                    return val;
                }
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
