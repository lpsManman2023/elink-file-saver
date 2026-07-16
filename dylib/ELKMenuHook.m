//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（sendEvent 拦截方案）
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
//  Hook UIWindow.sendEvent: —— 拦截所有触摸事件
// ============================================================
static void (*orig_sendEvent)(id, SEL, UIEvent *);

static void hook_sendEvent(id self, SEL _cmd, UIEvent *event) {
    // 先调用原始实现，保证 App 完全不受影响
    orig_sendEvent(self, _cmd, event);

    @try {
        NSSet *touches = [event allTouches];
        if (touches.count != 1) return;

        UITouch *touch = [touches anyObject];
        if (touch.phase != UITouchPhaseBegan) return;

        // 记录触摸开始时间和位置
        CGPoint point = [touch locationInView:nil]; // window 坐标
        NSTimeInterval ts = touch.timestamp;

        // 检查触摸下面的视图是不是气泡
        UIView *hit = [(UIWindow *)self hitTest:point withEvent:event];
        if (!hit) return;

        UIView *bubble = hit;
        while (bubble) {
            if ([NSStringFromClass([bubble class]) hasPrefix:@"WWKConversation"]) break;
            bubble = bubble.superview;
        }
        if (!bubble) return;

        // 🔥 存储这次触摸信息，等待长按确认
        // 我们用 dispatch_after 等待 0.5 秒后检查
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            // 检查触摸是否还在进行中（即用户确实在长按）
            // touch.phase 在闭包里不准确，但我们用另一种方式：
            // 如果在 0.5 秒后 bubble 仍然可见，说明用户没有松手
            if (bubble.window != nil) {
                // 尝试提取消息
                id message = [ELKMenuHook msgFromView:bubble] ?: [ELKMenuHook msgInSubviews:bubble];
                if (message) {
                    NSLog(@"[喵喵] 👆 长按气泡: %@", NSStringFromClass([bubble class]));
                    // 再延迟 0.3 秒，等 App 自己的菜单先显示
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        [ELKFileExporter exportFileFromMessage:message];
                    });
                }
            }
        });
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ⚠️ sendEvent Hook: %@", e);
    }
}

// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install（sendEvent 方案）");

        Method m = class_getInstanceMethod([UIWindow class], @selector(sendEvent:));
        if (m) {
            orig_sendEvent = (void(*)(id, SEL, UIEvent *))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_sendEvent);
            NSLog(@"[喵喵] ✅ sendEvent: Hook 完成");
        }

        NSLog(@"[喵喵] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ install: %@", e);
    }
}

+ (id)msgFromView:(UIView *)v {
    if (!v) return nil;
    for (NSString *key in @[@"message", @"messageItem", @"messageMedia", @"bubbleData"]) {
        @try {
            id val = [v valueForKey:key];
            if (val && [NSStringFromClass([val class]) hasPrefix:@"WWKMessage"]) return val;
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
