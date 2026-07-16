//
//  ELKFileExporter.h
//  ELKFileSaver
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

+ (void)shareFileAtPath:(NSString *)filePath;
+ (NSString *)findDecryptedFileInView:(UIView *)view;
+ (void)exportFileFromMessage:(id)message;
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
