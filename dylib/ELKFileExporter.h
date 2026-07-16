//
//  ELKFileExporter.h
//  ELKFileSaver
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

/// 方案 C：缓存从预览器拦截到的文件路径
+ (void)cacheInterceptedPath:(NSString *)path;

/// 获取缓存的路径
+ (NSString *)cachedPath;

/// 方案 F：KVC 搜索 VC 对象属性链找文件
+ (NSString *)searchVCForFile:(UIViewController *)vc;

/// 弹出系统分享菜单
+ (void)shareFileAtPath:(NSString *)filePath;

/// 弹出提示框
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
