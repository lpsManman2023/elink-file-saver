//
//  ELKFileExporter.h
//  ELKFileSaver - v11 异步扫描版
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 异步扫描 tmp/Caches 找解密文件，完成回调在主线程
+ (void)findDecryptedFileAsync:(void(^)(NSString *_Nullable path))completion;

/// 弹出系统分享菜单
+ (void)shareFileAtPath:(NSString *)filePath;

/// 弹出提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
