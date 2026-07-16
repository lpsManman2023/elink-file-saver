//
//  ELKFileExporter.h
//  ELKFileSaver
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ELKFileExporter : NSObject

+ (void)exportFileFromMessage:(id)message;
+ (NSString *)findDecryptedFileInView:(UIView *)view;
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message;

@end
