//
//  ELKFileExporter.h
//  ELKFileSaver - 文件导出到 iPhone 文件 App
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 尝试从消息对象中导出文件
/// @param message WWKMessage 或其子类实例
+ (void)exportFileFromMessage:(id)message;

/// 直接导出指定路径的文件
/// @param filePath 文件在磁盘上的完整路径
+ (void)exportFileAtPath:(NSString *)filePath;

/// 弹窗提示（供其他模块调用）
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
