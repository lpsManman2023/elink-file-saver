//
//  ELKRuntimeHelper.h
//  ELKFileSaver - Method Swizzling 工具
//
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

@interface ELKRuntimeHelper : NSObject

/// 交换实例方法
+ (void)swizzleInstanceMethod:(SEL)original
                   withMethod:(SEL)replacement
                      onClass:(Class)cls;

/// 交换类方法
+ (void)swizzleClassMethod:(SEL)original
                withMethod:(SEL)replacement
                   onClass:(Class)cls;

/// 获取当前最顶层的 ViewController
+ (UIViewController *)topViewController;

/// 在主线程延迟执行 block
+ (void)runAfterDelay:(NSTimeInterval)delay block:(void (^)(void))block;

@end
