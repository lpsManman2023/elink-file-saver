//
//  ELKRuntimeHelper.m
//  ELKFileSaver - Method Swizzling 工具实现
//
#import "ELKRuntimeHelper.h"

@implementation ELKRuntimeHelper

+ (void)swizzleInstanceMethod:(SEL)original
                   withMethod:(SEL)replacement
                      onClass:(Class)cls {
    Method origMethod = class_getInstanceMethod(cls, original);
    Method replMethod = class_getInstanceMethod(cls, replacement);

    if (!origMethod || !replMethod) {
        NSLog(@"[ELKFileSaver] ⚠️ Swizzle 失败: 方法不存在 (class=%@, orig=%@, repl=%@)",
              NSStringFromClass(cls),
              NSStringFromSelector(original),
              NSStringFromSelector(replacement));
        return;
    }

    // 先尝试把 replacement 方法添加到原始类
    BOOL didAdd = class_addMethod(cls,
                                  original,
                                  method_getImplementation(replMethod),
                                  method_getTypeEncoding(replMethod));

    if (didAdd) {
        // 如果成功添加，说明原方法在父类，把原方法的实现替换给 replacement
        class_replaceMethod(cls,
                           replacement,
                           method_getImplementation(origMethod),
                           method_getTypeEncoding(origMethod));
    } else {
        // 否则直接交换
        method_exchangeImplementations(origMethod, replMethod);
    }

    NSLog(@"[ELKFileSaver] ✅ Swizzle 完成: %@.%@",
          NSStringFromClass(cls), NSStringFromSelector(original));
}

+ (void)swizzleClassMethod:(SEL)original
                withMethod:(SEL)replacement
                   onClass:(Class)cls {
    Class metaCls = object_getClass(cls);
    [self swizzleInstanceMethod:original withMethod:replacement onClass:metaCls];
}

+ (UIViewController *)topViewController {
    // iOS 13+ 兼容方式获取 keyWindow
    UIWindow *keyWin = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { keyWin = w; break; }
            }
        }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
    return [self topViewControllerFrom:keyWin.rootViewController];
}

+ (UIViewController *)topViewControllerFrom:(UIViewController *)vc {
    if ([vc isKindOfClass:[UINavigationController class]]) {
        return [self topViewControllerFrom:[(UINavigationController *)vc visibleViewController]];
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        return [self topViewControllerFrom:[(UITabBarController *)vc selectedViewController]];
    }
    if (vc.presentedViewController) {
        return [self topViewControllerFrom:vc.presentedViewController];
    }
    return vc;
}

+ (void)runAfterDelay:(NSTimeInterval)delay block:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

@end
