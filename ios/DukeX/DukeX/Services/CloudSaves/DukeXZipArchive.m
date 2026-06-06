#import "DukeXZipArchive.h"
#import "../../Vendor/miniz/miniz.h"

static NSString *const DukeXZipArchiveErrorDomain = @"DukeXZipArchiveError";

static void DukeXZipArchiveSetError(NSError **error, NSString *message)
{
    if (!error) {
        return;
    }
    *error = [NSError errorWithDomain:DukeXZipArchiveErrorDomain
                                 code:1
                             userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *DukeXZipArchiveRelativePath(NSString *basePath, NSString *filePath)
{
    if (![filePath hasPrefix:basePath]) {
        return filePath.lastPathComponent;
    }

    NSString *relative = [filePath substringFromIndex:basePath.length];
    while ([relative hasPrefix:@"/"]) {
        relative = [relative substringFromIndex:1];
    }
    return [relative stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
}

@implementation DukeXZipArchive

+ (BOOL)createArchiveAtPath:(NSString *)archivePath
              fromDirectory:(NSString *)directoryPath
                      error:(NSError **)error
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray<NSString *> *keys = @[NSURLIsDirectoryKey];
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [fileManager enumeratorAtURL:[NSURL fileURLWithPath:directoryPath]
           includingPropertiesForKeys:keys
                              options:0
                         errorHandler:nil];

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));

    if (!mz_zip_writer_init_file(&zip, archivePath.UTF8String, 0)) {
        DukeXZipArchiveSetError(error, @"Could not create the .dukex archive.");
        return NO;
    }

    BOOL ok = YES;
    for (NSURL *url in enumerator) {
        NSNumber *isDirectory = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) {
            continue;
        }

        NSString *relativePath = DukeXZipArchiveRelativePath(directoryPath, url.path);
        if (relativePath.length == 0) {
            continue;
        }

        if (!mz_zip_writer_add_file(&zip,
                                    relativePath.UTF8String,
                                    url.path.UTF8String,
                                    NULL,
                                    0,
                                    MZ_DEFAULT_COMPRESSION)) {
            ok = NO;
            DukeXZipArchiveSetError(error, [NSString stringWithFormat:@"Could not add %@ to the .dukex archive.", relativePath]);
            break;
        }
    }

    if (ok && !mz_zip_writer_finalize_archive(&zip)) {
        ok = NO;
        DukeXZipArchiveSetError(error, @"Could not finalize the .dukex archive.");
    }

    mz_zip_writer_end(&zip);
    return ok;
}

+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                 toDirectory:(NSString *)directoryPath
                       error:(NSError **)error
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    [fileManager createDirectoryAtPath:directoryPath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));

    if (!mz_zip_reader_init_file(&zip, archivePath.UTF8String, 0)) {
        DukeXZipArchiveSetError(error, @"Could not open the .dukex archive.");
        return NO;
    }

    BOOL ok = YES;
    mz_uint fileCount = mz_zip_reader_get_num_files(&zip);
    for (mz_uint i = 0; i < fileCount; i++) {
        mz_zip_archive_file_stat stat;
        if (!mz_zip_reader_file_stat(&zip, i, &stat)) {
            ok = NO;
            DukeXZipArchiveSetError(error, @"Could not read the .dukex archive metadata.");
            break;
        }

        NSString *relativePath = [NSString stringWithUTF8String:stat.m_filename ?: ""];
        if (relativePath.length == 0 ||
            [relativePath containsString:@"../"] ||
            [relativePath hasPrefix:@"/"]) {
            continue;
        }

        NSString *destinationPath = [directoryPath stringByAppendingPathComponent:relativePath];
        if (stat.m_is_directory) {
            [fileManager createDirectoryAtPath:destinationPath
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:nil];
            continue;
        }

        NSString *parentPath = destinationPath.stringByDeletingLastPathComponent;
        [fileManager createDirectoryAtPath:parentPath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];

        if (!mz_zip_reader_extract_to_file(&zip, i, destinationPath.UTF8String, 0)) {
            ok = NO;
            DukeXZipArchiveSetError(error, [NSString stringWithFormat:@"Could not extract %@ from the .dukex archive.", relativePath]);
            break;
        }
    }

    mz_zip_reader_end(&zip);
    return ok;
}

+ (NSData *)dataForEntryNamed:(NSString *)entryName
              inArchiveAtPath:(NSString *)archivePath
                        error:(NSError **)error
{
    if (entryName.length == 0 ||
        [entryName containsString:@"../"] ||
        [entryName hasPrefix:@"/"]) {
        DukeXZipArchiveSetError(error, @"Invalid archive entry name.");
        return nil;
    }

    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));

    if (!mz_zip_reader_init_file(&zip, archivePath.UTF8String, 0)) {
        DukeXZipArchiveSetError(error, @"Could not open the skin archive.");
        return nil;
    }

    mz_uint fileIndex = 0;
    if (!mz_zip_reader_locate_file_v2(&zip,
                                      entryName.UTF8String,
                                      NULL,
                                      0,
                                      &fileIndex)) {
        mz_zip_reader_end(&zip);
        DukeXZipArchiveSetError(error, [NSString stringWithFormat:@"Could not find %@ in the skin archive.", entryName]);
        return nil;
    }

    size_t size = 0;
    void *bytes = mz_zip_reader_extract_to_heap(&zip, fileIndex, &size, 0);
    if (bytes == NULL) {
        mz_zip_reader_end(&zip);
        DukeXZipArchiveSetError(error, [NSString stringWithFormat:@"Could not read %@ from the skin archive.", entryName]);
        return nil;
    }

    NSData *data = [NSData dataWithBytes:bytes length:size];
    mz_free(bytes);
    mz_zip_reader_end(&zip);
    return data;
}

@end
