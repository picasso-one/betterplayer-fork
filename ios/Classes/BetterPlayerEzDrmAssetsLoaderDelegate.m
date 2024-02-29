#import "BetterPlayerEzDrmAssetsLoaderDelegate.h"

@implementation BetterPlayerEzDrmAssetsLoaderDelegate

NSString *_assetId;

NSString *DEFAULT_LICENSE_SERVER_URL = @"https://fps.ezdrm.com/api/licenses/";

- (instancetype)init:(NSURL *)certificateURL withLicenseURL:(NSURL *)licenseURL withHeaders:(NSDictionary *)headers {
    self = [super init];
    _certificateURL = certificateURL;
    _licenseURL = licenseURL;
    _headers = headers;
    return self;
}

- (NSData *)getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest:(NSData *)requestBytes
                                                                  and:(NSString *)assetId
                                                                  and:(NSString *)customParams
                                                             errorOut:(NSError **)errorOut {
    __block NSData *decodedData;
    
    NSURL *finalLicenseURL;
    if (_licenseURL != [NSNull null]) {
        finalLicenseURL = _licenseURL;
    } else {
        finalLicenseURL = [NSURL URLWithString:DEFAULT_LICENSE_SERVER_URL];
    }
    NSURL *ksmURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@%@", finalLicenseURL, assetId, customParams]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:ksmURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-type"];
    [request setHTTPBody:requestBytes];
    
    for (NSString *key in _headers) {
        id value = _headers[key];
        [request addValue:[value copy] forHTTPHeaderField:[key copy]];
    }
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSLog(@"SDK Error, SDK responded with Error: %@", [error localizedDescription]);
            if (errorOut) {
                *errorOut = error;
            }
        } else {
            decodedData = data;
        }
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    [dataTask resume];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    return decodedData;
}


- (NSData *)getAppCertificate:(NSString *)String errorOut:(NSError **)errorOut {
    NSURL *certificateURL = _certificateURL;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:certificateURL];
    
    if (_headers) {
        for (NSString *key in _headers) {
            [request addValue:_headers[key] forHTTPHeaderField:key];
        }
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    __block NSData *certificateData = nil;
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Error fetching certificate data: %@", error.localizedDescription);
            if (errorOut) {
                *errorOut = error;
            }
        } else {
            certificateData = data;
        }
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    [dataTask resume];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    return certificateData;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSURL *assetURI = loadingRequest.request.URL;
    NSString *str = assetURI.absoluteString;
    NSString *mySubstring = [str substringFromIndex:str.length - 36];
    _assetId = mySubstring;
    NSString *scheme = assetURI.scheme;
    NSData *requestBytes;
    NSData *certificate;
    NSError *errorCert;
    if (!([scheme isEqualToString:@"skd"])) {
        return NO;
    }
    @try {
        certificate = [self getAppCertificate:_assetId errorOut:&errorCert];
    }
    @catch (NSException *excp) {
        [loadingRequest finishLoadingWithError:[[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorClientCertificateRejected userInfo:nil]];
    }
    @try {
        requestBytes = [loadingRequest streamingContentKeyRequestDataForApp:certificate contentIdentifier:[str dataUsingEncoding:NSUTF8StringEncoding] options:nil error:nil];
    }
    @catch (NSException *excp) {
        [loadingRequest finishLoadingWithError:nil];
        return YES;
    }
    
    NSString *passthruParams = [NSString stringWithFormat:@"?customdata=%@", _assetId];
    NSData *responseData;
    NSError *error;
    
    responseData = [self getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest:requestBytes and:_assetId and:passthruParams errorOut:&error];
    
    if (responseData != nil && responseData != NULL && ![responseData.class isKindOfClass:NSNull.class]) {
        AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
        [dataRequest respondWithData:responseData];
        [loadingRequest finishLoading];
    } else {
        [loadingRequest finishLoadingWithError:error];
    }
    
    return YES;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest *)renewalRequest {
    return [self resourceLoader:resourceLoader shouldWaitForLoadingOfRequestedResource:renewalRequest];
}

@end
