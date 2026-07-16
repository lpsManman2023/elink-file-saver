//
//  ELKMenuHook.m
//  ELKFileSaver - 消息菜单注入
//
//  策略：
//    Hook 1: UIMenuController → 追加 "保存到文件" 菜单项
//    Hook 2: 气泡视图 canPerformAction: → 启用自定义 action
//    Hook 3: 备用 — 模糊匹配 UIResponder 子类
//
#import "ELKMenuHook.h"
#import "ELKFileExporter.h"
#import "ELKRuntimeHelper.h"
#import <objc/runtime.h>

// ── 自定义 action selector ──
static SEL elkSaveAction;

// ── 保存每个类的原始 canPerformAction: IMP ──
static NSMutableDictionary<NSString *, NSValue *> *g_origIMPMap = nil;

// ── 弱引用：当前被长按的消息气泡 ──
static __weak UIView *g_targetBubble = nil;

// 前向声明：实现在文件末尾
@interface ELKMenuHook (Private)
+ (id)findMessageFromResponder:(UIResponder *)r;
@end

// ============================================================
//  1. UIResponder 分类 — action 实现
// ============================================================
@interface UIResponder (ELKSaveToFiles)
- (void)elk_saveToFiles:(id)sender;
@end

@implementation UIResponder (ELKSaveToFiles)

- (void)elk_saveToFiles:(id)sender {
    NSLog(@"[ELKFileSaver] 🔔 用户点击『保存到文件』");

    id message = [ELKMenuHook findMessageFromResponder:self];
    if (message) {
        [ELKFileExporter exportFileFromMessage:message];
    } else {
        [ELKFileExporter showAlertWithTitle:@"无法定位文件"
                                    message:@"请在聊天中的文件/图片/视频消息上长按使用此功能。"];
    }
}

@end

// ============================================================
//  2. UIMenuController Hook
// ============================================================
static void (*orig_UIMenuController_setMenuItems)(id, SEL, NSArray<UIMenuItem *> *);

static void hook_UIMenuController_setMenuItems(id self, SEL _cmd, NSArray<UIMenuItem *> *items) {
    NSMutableArray *new = items ? [items mutableCopy] : [NSMutableArray array];

    // 去重
    BOOL has = NO;
    for (UIMenuItem *it in new) { if (it.action == elkSaveAction) { has = YES; break; } }
    if (!has) {
        [new addObject:[[UIMenuItem alloc] initWithTitle:@"保存到文件" action:elkSaveAction]];
    }

    orig_UIMenuController_setMenuItems(self, _cmd, new);
}

// ============================================================
//  3. 气泡视图 canPerformAction: Hook
// ============================================================
//  返回 YES 让我们的 action 在菜单中可见

static BOOL hook_canPerformAction(id self, SEL _cmd, SEL action, id sender) {
    if (action == elkSaveAction) {
        g_targetBubble = self;   // 记录当前气泡
        return YES;
    }

    // 查表获取原始的 IMP
    NSString *clsName = NSStringFromClass([self class]);
    NSValue *val = g_origIMPMap[clsName];
    if (val) {
        IMP imp = val.pointerValue;
        return ((BOOL(*)(id, SEL, SEL, id))imp)(self, _cmd, action, sender);
    }
    // 最终兜底：调用父类
    return NO;
}

// ============================================================
//  4. 主入口
// ============================================================
@implementation ELKMenuHook

+ (void)install {
    NSLog(@"[ELKFileSaver] 🚀 install");

    elkSaveAction = @selector(elk_saveToFiles:);
    g_origIMPMap = [NSMutableDictionary dictionary];

    // ── Hook A: UIMenuController ──
    {
        Method m = class_getInstanceMethod([UIMenuController class], @selector(setMenuItems:));
        if (m) {
            orig_UIMenuController_setMenuItems = (void(*)(id, SEL, NSArray *))method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_UIMenuController_setMenuItems);
            NSLog(@"[ELKFileSaver] ✅ UIMenuController");
        }
    }

    // ── Hook B: 已知的气泡视图类 ──
    NSArray<NSString *> *names = @[
        @"WWKConversationStandardBubbleView",
        @"WWKConversationFileBubbleView",
        @"WWKConversationImageBubbleView",
        @"WWKConversationVideoBubbleView",
        @"WWKConversationVoiceBubbleView",
        @"WWKConversationTextBubbleView",
        @"WWKConversationEncryptBubbleView",
        @"WWKConversationRedEnvelopesBubbleView",
        @"WWKConversationWeAppTemplateCardBubbleView",
        @"WWKConversationPersonalCardBubbleView",
        @"WWKConversationChatApplicationBubbleView",
        @"WWKConversationCardCellBubbleView",
        @"WWKConversationCardCellMaskedBubbleView",
        @"WWKConversationLishiTextBubbleView",
        @"WWKConversationLocationBubbleView",
        @"WWKConversationLinkBubbleView",
        @"WWKConversationAppShareBubbleView",
    ];

    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (!cls) continue;

        Method m = class_getInstanceMethod(cls, @selector(canPerformAction:withSender:));
        if (!m) continue;

        // 保存原始 IMP
        IMP orig = method_getImplementation(m);
        g_origIMPMap[name] = [NSValue valueWithPointer:orig];

        method_setImplementation(m, (IMP)hook_canPerformAction);
        NSLog(@"[ELKFileSaver] ✅ canPerformAction: %@", name);
    }

    // ── 最终数量 ──
    NSLog(@"[ELKFileSaver] 🏁 安装完成, hooked=%lu 个气泡类", (unsigned long)g_origIMPMap.count);
}

// ============================================================
//  5. 从 Responder 链中查找消息对象
// ============================================================
+ (id)findMessageFromResponder:(UIResponder *)r {
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

    return [self msgInSubviews:[UIApplication sharedApplication].keyWindow];
}

+ (id)msgFromView:(UIView *)v {
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
    for (UIView *sub in root.subviews) {
        id m = [self msgFromView:sub] ?: [self msgInSubviews:sub];
        if (m) return m;
    }
    return nil;
}

@end
