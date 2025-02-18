//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAsset.h>
#import <EXUpdates/EXUpdatesAppLauncherNoDatabase.h>
#import <EXUpdates/EXUpdatesEmbeddedAppLoader.h>
#import <EXUpdates/EXUpdatesUtils.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const EXUpdatesErrorLogFile = @"expo-error.log";

@interface EXUpdatesAppLauncherNoDatabase ()

@property (nullable, nonatomic, strong, readwrite) EXUpdatesUpdate *launchedUpdate;
@property (nullable, nonatomic, strong, readwrite) NSURL *launchAssetUrl;
@property (nullable, nonatomic, strong, readwrite) NSMutableDictionary *assetFilesMap;

@end

@implementation EXUpdatesAppLauncherNoDatabase

- (void)launchUpdateWithConfig:(EXUpdatesConfig *)config
{
  _launchedUpdate = [EXUpdatesEmbeddedAppLoader embeddedManifestWithConfig:config database:nil];
  if (_launchedUpdate) {
    if (_launchedUpdate.status == EXUpdatesUpdateStatusEmbedded) {
      NSAssert(_assetFilesMap == nil, @"assetFilesMap should be null for embedded updates");
      _launchAssetUrl = [[NSBundle mainBundle] URLForResource:EXUpdatesBareEmbeddedBundleFilename withExtension:EXUpdatesBareEmbeddedBundleFileType];
    } else {
      _launchAssetUrl = [[NSBundle mainBundle] URLForResource:EXUpdatesEmbeddedBundleFilename withExtension:EXUpdatesEmbeddedBundleFileType];

      NSMutableDictionary *assetFilesMap = [NSMutableDictionary new];
      for (EXUpdatesAsset *asset in _launchedUpdate.assets) {
        NSURL *localUrl = [EXUpdatesUtils urlForBundledAsset:asset];
        if (localUrl && asset.key) {
          assetFilesMap[asset.key] = localUrl.absoluteString;
        }
      }
      _assetFilesMap = assetFilesMap;
    }
  }
}

- (BOOL)isUsingEmbeddedAssets
{
  return _assetFilesMap == nil;
}

- (void)launchUpdateWithConfig:(EXUpdatesConfig *)config fatalError:(NSError *)error;
{
  [self launchUpdateWithConfig:config];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self _writeErrorToLog:error];
  });
}

+ (nullable NSString *)consumeError;
{
  NSString *errorLogFilePath = [[self class] _errorLogFilePath]; 
  NSData *data = [NSData dataWithContentsOfFile:errorLogFilePath options:kNilOptions error:nil];
  if (data) {
    NSError *err;
    if (![NSFileManager.defaultManager removeItemAtPath:errorLogFilePath error:&err]) {
      NSLog(@"Could not delete error log: %@", err.localizedDescription);
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  } else {
    return nil;
  }
}

- (void)_writeErrorToLog:(NSError *)error
{
  NSString *serializedError = [NSString stringWithFormat:@"Expo encountered a fatal error: %@", [self _serializeError:error]];
  NSData *data = [serializedError dataUsingEncoding:NSUTF8StringEncoding];

  NSError *err;
  if (![data writeToFile:[[self class] _errorLogFilePath] options:NSDataWritingAtomic error:&err]) {
    NSLog(@"Could not write fatal error to log: %@", error.localizedDescription);
  }
}

- (NSString *)_serializeError:(NSError *)error
{
  NSString *localizedFailureReason = error.localizedFailureReason;
  NSError *underlyingError = error.userInfo[NSUnderlyingErrorKey];
  
  NSMutableString *serialization = [[NSString stringWithFormat:@"Time: %f\nDomain: %@\nCode: %li\nDescription: %@",
                                    [[NSDate date] timeIntervalSince1970] * 1000,
                                    error.domain,
                                    (long)error.code,
                                    error.localizedDescription] mutableCopy];
  if (localizedFailureReason) {
    [serialization appendFormat:@"\nFailure Reason: %@", localizedFailureReason];
  }
  if (underlyingError) {
    [serialization appendFormat:@"\n\nUnderlying Error:\n%@", [self _serializeError:underlyingError]];
  }
  return serialization;
}

+ (NSString *)_errorLogFilePath
{
  NSURL *applicationDocumentsDirectory = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
  return [[applicationDocumentsDirectory URLByAppendingPathComponent:EXUpdatesErrorLogFile] path];
}

@end

NS_ASSUME_NONNULL_END
