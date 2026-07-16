//
//  ELKFileExporter.h
//  ELKFileSaver
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 安装预览拦截 Hook（在 dylib 初始化时调用）
+ (void)installPreviewHooks;

/// 从消息对象导出文件
+ (void)exportFileFromMessage:(id)message;

/// 显示提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
