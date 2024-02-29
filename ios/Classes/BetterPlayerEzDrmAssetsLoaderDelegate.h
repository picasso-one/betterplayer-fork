#import <Foundation/Foundation.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

@interface BetterPlayerEzDrmAssetsLoaderDelegate : NSObject

@property (readonly, nonatomic) NSURL *certificateURL;
@property (readonly, nonatomic) NSURL *licenseURL;
@property (readonly, nonatomic) NSDictionary *headers;

- (instancetype)init:(NSURL *)certificateURL withLicenseURL:(NSURL *)licenseURL withHeaders:(NSDictionary *)headers;
- (NSData *)getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest:(NSData *)requestBytes
                                                                and:(NSString *)assetId
                                                                and:(NSString *)customParams
                                                              errorOut:(NSError **)errorOut;
- (NSData *)getAppCertificate:(NSString *)String;

@end
