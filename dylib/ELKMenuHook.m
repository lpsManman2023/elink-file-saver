//
//  ELKMenuHook.m
//  ELKFileSaver - 喵喵插件（系统级菜单注入）
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

static SEL elkSaveAction;

// ── 前向声明 ──
@interface ELKMenuHook (Private)
+ (id)msgFromView:(UIView *)v;
+ (id)msgInSubviews:(UIView *)root;
@end

// ============================================================
//  Hook 1: UIResponder.canPerformAction:  —— 让所有 UIResponder 都对我们的 action 说 YES
// ============================================================
static BOOL (*orig_canPerformAction)(id, SEL, SEL, id);
static BOOL hook_canPerformAction(id self, SEL _cmd, SEL action, id sender) {
    if (action == elkSaveAction) {
        return YES;  // 🔥 无论谁问，都说 YES
    }
    return orig_canPerformAction(self, _cmd, action, sender);
}

// ============================================================
//  Hook 2: UIMenuController.setMenuItems: —— 追加菜单项
// ============================================================
static void (*orig_setMenuItems)(id, SEL, NSArray<UIMenuItem *> *);
static void hook_setMenuItems(id self, SEL _cmd, NSArray<UIMenuItem *> *items) {
    NSMutableArray *new = items ? [items mutableCopy] : [NSMutableArray array];

    BOOL has = NO;
    for (UIMenuItem *it in new) {
        if (it.action == elkSaveAction) { has = YES; break; }
    }
    if (!has) {
        [new addObject:[[UIMenuItem alloc] initWithTitle:@"💾 保存到文件" action:elkSaveAction]];
    }

    orig_setMenuItems(self, _cmd, new);
}

// ============================================================
//  UIResponder 分类 —— 点击菜单的处理
// ============================================================
@interface UIResponder (ELKSave)
- (void)elk_saveToFiles:(id)sender;
@end

@implementation UIResponder (ELKSave)

- (void)elk_saveToFiles:(id)sender {
    @try {
        NSLog(@"[喵喵] 🔔 保存到文件");

        // 从 firstResponder 所在的视图树中搜索消息对象
        id message = nil;
        if ([self isKindOfClass:[UIView class]]) {
            UIView *v = (UIView *)self;
            while (v) {
                message = [ELKMenuHook msgFromView:v];
                if (!message) message = [ELKMenuHook msgInSubviews:v];
                if (message) break;
                v = v.superview;
            }
        }

        if (message) {
            [ELKFileExporter exportFileFromMessage:message];
        } else {
            // 全局搜索兜底
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                message = [ELKMenuHook msgInSubviews:w];
                if (message) break;
            }
            if (message) {
                [ELKFileExporter exportFileFromMessage:message];
            } else {
                [ELKFileExporter showAlertWithTitle:@"提示"
                                            message:@"请先点开文件查看，然后返回再长按。"];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ %@", e);
    }
}

@end

// ============================================================
@implementation ELKMenuHook

+ (void)install {
    @try {
        NSLog(@"[喵喵] 🚀 install");
        elkSaveAction = @selector(elk_saveToFiles:);

        // Hook 1: UIResponder.canPerformAction:withSender:
        Method m1 = class_getInstanceMethod([UIResponder class], @selector(canPerformAction:withSender:));
        if (m1) {
            orig_canPerformAction = (BOOL(*)(id, SEL, SEL, id))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_canPerformAction);
            NSLog(@"[喵喵] ✅ UIResponder.canPerformAction: Hook 完成");
        }

        // Hook 2: UIMenuController.setMenuItems:
        Method m2 = class_getInstanceMethod([UIMenuController class], @selector(setMenuItems:));
        if (m2) {
            orig_setMenuItems = (void(*)(id, SEL, NSArray *))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_setMenuItems);
            NSLog(@"[喵喵] ✅ UIMenuController.setMenuItems: Hook 完成");
        }

        NSLog(@"[喵喵] 🏁 安装完成");
    } @catch (NSException *e) {
        NSLog(@"[喵喵] ❌ install: %@", e);
    }
}

+ (id)msgFromView:(UIView *)v {
    if (!v) return nil;
    NSArray *keys = @[@"message", @"messageItem", @"messageMedia", @"bubbleData"];
    for (NSString *key in keys) {
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
        id m = [self msgFromView:sub];
        if (m) return m;
        m = [self msgInSubviews:sub];
        if (m) return m;
    }
    return nil;
}

@end
