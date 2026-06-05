#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DukeXZipArchive : NSObject

+ (BOOL)createArchiveAtPath:(NSString *)archivePath
              fromDirectory:(NSString *)directoryPath
                      error:(NSError ** _Nullable)error;

+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                 toDirectory:(NSString *)directoryPath
                       error:(NSError ** _Nullable)error;

+ (nullable NSData *)dataForEntryNamed:(NSString *)entryName
                       inArchiveAtPath:(NSString *)archivePath
                                 error:(NSError ** _Nullable)error;

@end

NS_ASSUME_NONNULL_END
