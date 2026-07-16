//
//  ELKMenuHook.m
//  ELKFileSaver - 消息菜单注入（精简稳定版）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

static SEL elkSaveAction;
static __weak UIView *g_targetBubble = nil;

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
        // 检查是否是气泡视图
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
        NSLog(@"[ELKFileSaver] 🔔 用户点击『保存到文件』");
        id message = [ELKMenuHook findMessageFromResponder:self];
        if (message) {
            [ELKFileExporter exportFileFromMessage:message];
        } else {
            [ELKFileExporter showAlertWithTitle:@"无法定位文件"
                                        message:@"请在聊天消息上长按后使用此功能。"];
        }
    } @catch (NSException *e) {
        NSLog(@"[ELKFileSaver] ❌ elk_saveToFiles 异常: %@", e);
    }
}

@end

// ============================================================
//  3. UIMenuController Hook（只追加菜单，不干扰原逻辑）
// ============================================================
static void (*orig_setMenuItems)(id, SEL, NSArray<UIMenuItem *> *);

static void hook_setMenuItems(id self, SEL _cmd, NSArray<UIMenuItem *> *items) {
    // 追加我们的菜单项
    NSMutableArray *new = items ? [items mutableCopy] : [NSMutableArray array];
    BOOL has = NO;
    for (UIMenuItem *it in new) {
        if (it.action == elkSaveAction) { has = YES; break; }
    }
    if (!has) {
        [new addObject:[[UIMenuItem alloc] initWithTitle:@"保存到文件" action:elkSaveAction]];
    }
    // 只调一次原始实现
    orig_setMenuItems(self, _cmd, new);
}

// ============================================================
//  4. 主入口
// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[ELKFileSaver] 🚀 install");
        elkSaveAction = @selector(elk_saveToFiles:);

        // ── Hook A: UIWindow.hitTest 记录被点击的气泡 ──
        // 这个方法非常简单，不会干扰任何逻辑
        Method ht = class_getInstanceMethod([UIWindow class], @selector(hitTest:withEvent:));
        if (ht) {
            orig_hitTest = (UIView *(*)(id, SEL, CGPoint, UIEvent *))method_getImplementation(ht);
            method_setImplementation(ht, (IMP)hook_hitTest);
            NSLog(@"[ELKFileSaver] ✅ hitTest hook 完成");
        }

        // ── Hook B: UIMenuController 追加菜单 ──
        Method sm = class_getInstanceMethod([UIMenuController class], @selector(setMenuItems:));
        if (sm) {
            orig_setMenuItems = (void(*)(id, SEL, NSArray *))method_getImplementation(sm);
            method_setImplementation(sm, (IMP)hook_setMenuItems);
            NSLog(@"[ELKFileSaver] ✅ UIMenuController hook 完成");
        }

        NSLog(@"[ELKFileSaver] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[ELKFileSaver] ❌ install 异常: %@", e);
    }
}

// ============================================================
//  5. 从 Responder 链中查找消息对象
// ============================================================
+ (id)findMessageFromResponder:(UIResponder *)r {
    @try {
        // 优先：之前 hitTest 记录的气泡
        if (g_targetBubble) {
            id m = [self msgFromView:g_targetBubble];
            if (m) return m;
        }

        // 遍历 responder chain
        while (r) {
            if ([r isKindOfClass:[UIView class]]) {
                id m = [self msgFromView:(UIView *)r] ?: [self msgInSubviews:(UIView *)r];
                if (m) return m;
            }
            r = r.nextResponder;
        }

        // 兜底：全窗口搜索
        UIWindow *win = safeKeyWindow();
        if (win) return [self msgInSubviews:win];
    } @catch (NSException *e) {
        NSLog(@"[ELKFileSaver] ❌ findMessage 异常: %@", e);
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
