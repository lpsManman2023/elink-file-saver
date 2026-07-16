//
//  ELKMenuHook.m
//  ELKFileSaver - 消息菜单注入（喵喵插件版）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

static SEL elkSaveAction;
static __weak UIView *g_targetBubble = nil;

// ── 前向声明（实现在文件末尾） ──
@interface ELKMenuHook (Private)
+ (id)findMessageFromResponder:(UIResponder *)r;
@end

// ── 安全获取 keyWindow ──
static UIWindow *safeKeyWindow(void) {
    @try {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    } @catch (...) {}
    @try { return [UIApplication sharedApplication].keyWindow; } @catch (...) {}
    return nil;
}

// ============================================================
//  1. 记录当前被长按的 bubble（通过 hitTest 拦截）
// ============================================================
static UIView *(*orig_hitTest)(id, SEL, CGPoint, UIEvent *);

static UIView *hook_hitTest(id self, SEL _cmd, CGPoint point, UIEvent *event) {
    UIView *hit = orig_hitTest(self, _cmd, point, event);
    if (hit) {
        NSString *cn = NSStringFromClass([hit class]);
        if ([cn hasPrefix:@"WWKConversation"]) {
            g_targetBubble = hit;
        }
    }
    return hit;
}

// ============================================================
//  2. UIResponder 分类 — action 实现
// ============================================================
@interface UIResponder (ELKSaveToFiles)
- (void)elk_saveToFiles:(id)sender;
@end

@implementation UIResponder (ELKSaveToFiles)

- (void)elk_saveToFiles:(id)sender {
    @try {
        NSLog(@"[喵喵插件] 🔔 用户点击『保存到文件』");
        id message = [ELKMenuHook findMessageFromResponder:self];
        if (message) {
            [ELKFileExporter exportFileFromMessage:message];
        } else {
            [ELKFileExporter showAlertWithTitle:@"无法定位文件"
                                        message:@"请在聊天消息上长按后使用此功能。"];
        }
    } @catch (NSException *e) {
        NSLog(@"[喵喵插件] ❌ 异常: %@", e);
    }
}

@end

// ============================================================
//  3. UIMenuController Hook
// ============================================================
static void (*orig_setMenuItems)(id, SEL, NSArray<UIMenuItem *> *);

static void hook_setMenuItems(id self, SEL _cmd, NSArray<UIMenuItem *> *items) {
    NSMutableArray *new = items ? [items mutableCopy] : [NSMutableArray array];
    BOOL has = NO;
    for (UIMenuItem *it in new) {
        if (it.action == elkSaveAction) { has = YES; break; }
    }
    if (!has) {
        [new addObject:[[UIMenuItem alloc] initWithTitle:@"保存到文件" action:elkSaveAction]];
    }
    orig_setMenuItems(self, _cmd, new);
}

// ============================================================
//  4. 主入口
// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵插件] 🚀 install");
        elkSaveAction = @selector(elk_saveToFiles:);

        // Hook A: UIWindow.hitTest
        Method ht = class_getInstanceMethod([UIWindow class], @selector(hitTest:withEvent:));
        if (ht) {
            orig_hitTest = (UIView *(*)(id, SEL, CGPoint, UIEvent *))method_getImplementation(ht);
            method_setImplementation(ht, (IMP)hook_hitTest);
            NSLog(@"[喵喵插件] ✅ hitTest hook 完成");
        }

        // Hook B: UIMenuController
        Method sm = class_getInstanceMethod([UIMenuController class], @selector(setMenuItems:));
        if (sm) {
            orig_setMenuItems = (void(*)(id, SEL, NSArray *))method_getImplementation(sm);
            method_setImplementation(sm, (IMP)hook_setMenuItems);
            NSLog(@"[喵喵插件] ✅ UIMenuController hook 完成");
        }

        NSLog(@"[喵喵插件] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵插件] ❌ install 异常: %@", e);
    }
}

// ============================================================
//  5. 从 Responder 链中查找消息对象
// ============================================================
+ (id)findMessageFromResponder:(UIResponder *)r {
    @try {
        if (g_targetBubble) {
            id m = [self msgFromView:g_targetBubble];
            if (m) return m;
        }

        while (r) {
            if ([r isKindOfClass:[UIView class]]) {
                id m = [self msgFromView:(UIView *)r] ?: [self msgInSubviews:(UIView *)r];
                if (m) return m;
            }
            r = r.nextResponder;
        }

        UIWindow *win = safeKeyWindow();
        if (win) return [self msgInSubviews:win];
    } @catch (NSException *e) {
        NSLog(@"[喵喵插件] ❌ findMessage 异常: %@", e);
    }
    return nil;
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
