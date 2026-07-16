//
//  ELKMenuHook.h
//  ELKFileSaver - 消息菜单注入
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKMenuHook : NSObject

/// 安装所有 Hook（在 constructor 中调用）
+ (void)install;

@end
