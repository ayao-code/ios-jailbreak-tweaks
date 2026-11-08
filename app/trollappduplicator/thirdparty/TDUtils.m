#import "TDUtils.h"
#include <Foundation/Foundation.h>
#include <limits.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import "LSApplicationProxy+AltList.h"

NSUInteger iconFormat(void) {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 8 : 10;
}

NSString *docPath(void) {
#if CLONE_UPSTREAM_EXPERIMENT
    NSString *directory=@"/var/mobile/Documents/CloneStudioUpstream";
#else
    NSString *directory=@"/var/mobile/Documents/CloneStudio";
#endif
    NSError *error = nil;
    [[NSFileManager defaultManager]
              createDirectoryAtPath:directory
        withIntermediateDirectories:YES
                         attributes:nil
                              error:&error];
    if (error != nil) {
        NSLog(@"[TrollAppDuplicator] error creating directory: %@", error);
    }

    return directory;
}

NSArray *duplicatedFileList(void) {
    NSMutableArray *files = [NSMutableArray array];
    NSMutableArray *fileNames = [NSMutableArray array];

    // iterate through all files in the Documents directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *file in [fileManager contentsOfDirectoryAtPath:docPath() error:nil]) {
        if ([@[@"ipa", @"json"] containsObject:file.pathExtension.lowercaseString]) {
            NSString *filePath =
                [[docPath() stringByAppendingPathComponent:file] stringByStandardizingPath];

            NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:filePath error:nil];
            NSDate *modificationDate = fileAttributes[NSFileModificationDate];

            if(![fileAttributes[NSFileType] isEqual:NSFileTypeRegular] || !modificationDate) continue;
            NSDictionary *fileInfo = @{@"fileName" : file, @"modificationDate" : modificationDate};
            [files addObject:fileInfo];
        }
    }

    // Sort the array based on modification date
    NSArray *sortedFiles = [files sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
      NSDate *date1 = [obj1 objectForKey:@"modificationDate"];
      NSDate *date2 = [obj2 objectForKey:@"modificationDate"];
      return [date2 compare:date1];
    }];

    // Get the file names from the sorted array
    for (NSDictionary *fileInfo in sortedFiles) {
        [fileNames addObject:[fileInfo objectForKey:@"fileName"]];
    }

    return [fileNames copy];
}

static BOOL readAt(FILE *binary, uint64_t offset, void *buffer, size_t size) {
    if (offset > LONG_MAX || fseek(binary, (long)offset, SEEK_SET)) return NO;
    return fread(buffer, 1, size, binary) == size;
}

BOOL isArchitectureEncrypted(FILE *binary, uint32_t offset) {
    struct mach_header header;
    if (!readAt(binary, offset, &header, sizeof(header))) return YES;
    BOOL swap = header.magic == MH_CIGAM || header.magic == MH_CIGAM_64;
    BOOL wide = header.magic == MH_MAGIC_64 || header.magic == MH_CIGAM_64;
    if (header.magic != MH_MAGIC && header.magic != MH_CIGAM && !wide) return YES;
    uint32_t count = swap ? OSSwapInt32(header.ncmds) : header.ncmds;
    uint32_t commandBytes = swap ? OSSwapInt32(header.sizeofcmds) : header.sizeofcmds;
    uint64_t position = (uint64_t)offset + (wide ? sizeof(struct mach_header_64) : sizeof(header));
    uint64_t end = position + commandBytes;
    if (fseek(binary, 0, SEEK_END)) return YES;
    long fileSize = ftell(binary);
    if (fileSize < 0 || end > (uint64_t)fileSize || count > commandBytes / 8) return YES;
    for (uint32_t i = 0; i < count; i++) {
        struct load_command lc;
        if (position + sizeof(lc) > end || !readAt(binary, position, &lc, sizeof(lc))) return YES;
        uint32_t cmd = swap ? OSSwapInt32(lc.cmd) : lc.cmd;
        uint32_t size = swap ? OSSwapInt32(lc.cmdsize) : lc.cmdsize;
        if (size < sizeof(lc) || size > end - position) return YES;
        if (cmd == LC_ENCRYPTION_INFO || cmd == LC_ENCRYPTION_INFO_64) {
            struct encryption_info_command info;
            if (size < sizeof(info) || !readAt(binary, position, &info, sizeof(info))) return YES;
            if ((swap ? OSSwapInt32(info.cryptid) : info.cryptid) != 0) return YES;
        }
        position += size;
    }
    return NO;
}

BOOL isBinaryEncrypted(NSString *path) {
    FILE *binary = fopen([path fileSystemRepresentation], "rb");
    if (!binary) return YES;
    struct fat_header header;
    BOOL result = YES;
    if (!readAt(binary, 0, &header, sizeof(header))) goto done;
    if (header.magic == FAT_MAGIC || header.magic == FAT_CIGAM) {
        BOOL swap = header.magic == FAT_CIGAM;
        uint32_t count = swap ? OSSwapInt32(header.nfat_arch) : header.nfat_arch;
        if (!count || count > 64) goto done;
        for (uint32_t i = 0; i < count; i++) {
            struct fat_arch arch;
            if (!readAt(binary, sizeof(header) + i * sizeof(arch), &arch, sizeof(arch))) goto done;
            uint32_t offset = swap ? OSSwapInt32(arch.offset) : arch.offset;
            if (isArchitectureEncrypted(binary, offset)) goto done;
        }
        result = NO;
    } else if (header.magic != FAT_MAGIC_64 && header.magic != FAT_CIGAM_64) {
        result = isArchitectureEncrypted(binary, 0);
    }
done:
    fclose(binary);
    return result;
}
