// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "BetterPlayer.h"

 #import <DzBase/DzBase.h>
#import <MediaTailorSDK/MediaTailorSDK.h>
#import <better_player/better_player-Swift.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>

static void* timeRangeContext = &timeRangeContext;
static void* statusContext = &statusContext;
static void* playbackLikelyToKeepUpContext = &playbackLikelyToKeepUpContext;
static void* playbackBufferEmptyContext = &playbackBufferEmptyContext;
static void* playbackBufferFullContext = &playbackBufferFullContext;
static void* presentationSizeContext = &presentationSizeContext;



#if TARGET_OS_IOS
void (^__strong _Nonnull _restoreUserInterfaceForPIPStopCompletionHandler)(BOOL);
API_AVAILABLE(ios(9.0))
AVPictureInPictureController *_pipController;
#endif

@implementation BetterPlayer
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _isInitialized = false;
    _isPlaying = false;
    _disposed = false;
    _player = [[AVPlayer alloc] init];
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    ///Fix for loading large videos
    if (@available(iOS 10.0, *)) {
        _player.automaticallyWaitsToMinimizeStalling = false;
    }
    self._observersAdded = false;
    return self;
}


- (nonnull UIView *)view {
    
    BetterPlayerView *playerView = [[BetterPlayerView alloc] initWithFrame:CGRectZero];
    playerView.player = _player;
    return playerView;
}

- (void)addObservers:(AVPlayerItem*)item {
    if (!self._observersAdded){
        [_player addObserver:self forKeyPath:@"rate" options:0 context:nil];
        [item addObserver:self forKeyPath:@"loadedTimeRanges" options:0 context:timeRangeContext];
        [item addObserver:self forKeyPath:@"status" options:0 context:statusContext];
        [item addObserver:self forKeyPath:@"presentationSize" options:0 context:presentationSizeContext];
        [item addObserver:self
               forKeyPath:@"playbackLikelyToKeepUp"
                  options:0
                  context:playbackLikelyToKeepUpContext];
        [item addObserver:self
               forKeyPath:@"playbackBufferEmpty"
                  options:0
                  context:playbackBufferEmptyContext];
        [item addObserver:self
               forKeyPath:@"playbackBufferFull"
                  options:0
                  context:playbackBufferFullContext];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(itemDidPlayToEndTime:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:item];
        self._observersAdded = true;
    }
}

- (void)clear {
    _isInitialized = false;
    _isPlaying = false;
    _disposed = false;
    _failedCount = 0;
    _key = nil;
    if (_player.currentItem == nil) {
        return;
    }

    if (_player.currentItem == nil) {
        return;
    }

    [self removeObservers];
    AVAsset* asset = [_player.currentItem asset];
    [asset cancelLoading];
}

- (void) removeObservers{
    if (self._observersAdded){
        [_player removeObserver:self forKeyPath:@"rate" context:nil];
        [[_player currentItem] removeObserver:self forKeyPath:@"status" context:statusContext];
        [[_player currentItem] removeObserver:self forKeyPath:@"presentationSize" context:presentationSizeContext];
        [[_player currentItem] removeObserver:self
                                   forKeyPath:@"loadedTimeRanges"
                                      context:timeRangeContext];
        [[_player currentItem] removeObserver:self
                                   forKeyPath:@"playbackLikelyToKeepUp"
                                      context:playbackLikelyToKeepUpContext];
        [[_player currentItem] removeObserver:self
                                   forKeyPath:@"playbackBufferEmpty"
                                      context:playbackBufferEmptyContext];
        [[_player currentItem] removeObserver:self
                                   forKeyPath:@"playbackBufferFull"
                                      context:playbackBufferFullContext];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        self._observersAdded = false;
    }
}

- (void)itemDidPlayToEndTime:(NSNotification*)notification {
    if (_isLooping) {
        AVPlayerItem* p = [notification object];
        [p seekToTime:kCMTimeZero completionHandler:nil];
    } else {
        if (_eventSink) {
            _eventSink(@{@"event" : @"completed", @"key" : _key});
            [ self removeObservers];

        }
    }
}


static inline CGFloat radiansToDegrees(CGFloat radians) {
    // Input range [-pi, pi] or [-180, 180]
    CGFloat degrees = GLKMathRadiansToDegrees((float)radians);
    if (degrees < 0) {
        // Convert -90 to 270 and -180 to 180
        return degrees + 360;
    }
    // Output degrees in between [0, 360[
    return degrees;
};

- (AVMutableVideoComposition*)getVideoCompositionWithTransform:(CGAffineTransform)transform
                                                     withAsset:(AVAsset*)asset
                                                withVideoTrack:(AVAssetTrack*)videoTrack {
    AVMutableVideoCompositionInstruction* instruction =
    [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, [asset duration]);
    AVMutableVideoCompositionLayerInstruction* layerInstruction =
    [AVMutableVideoCompositionLayerInstruction
     videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    [layerInstruction setTransform:_preferredTransform atTime:kCMTimeZero];

    AVMutableVideoComposition* videoComposition = [AVMutableVideoComposition videoComposition];
    instruction.layerInstructions = @[ layerInstruction ];
    videoComposition.instructions = @[ instruction ];

    // If in portrait mode, switch the width and height of the video
    CGFloat width = videoTrack.naturalSize.width;
    CGFloat height = videoTrack.naturalSize.height;
    NSInteger rotationDegrees =
    (NSInteger)round(radiansToDegrees(atan2(_preferredTransform.b, _preferredTransform.a)));
    if (rotationDegrees == 90 || rotationDegrees == 270) {
        width = videoTrack.naturalSize.height;
        height = videoTrack.naturalSize.width;
    }
    videoComposition.renderSize = CGSizeMake(width, height);

    float nominalFrameRate = videoTrack.nominalFrameRate;
    int fps = 30;
    if (nominalFrameRate > 0) {
        fps = (int) ceil(nominalFrameRate);
    }
    videoComposition.frameDuration = CMTimeMake(1, fps);
    
    return videoComposition;
}

- (CGAffineTransform)fixTransform:(AVAssetTrack*)videoTrack {
  CGAffineTransform transform = videoTrack.preferredTransform;
  // TODO(@recastrodiaz): why do we need to do this? Why is the preferredTransform incorrect?
  // At least 2 user videos show a black screen when in portrait mode if we directly use the
  // videoTrack.preferredTransform Setting tx to the height of the video instead of 0, properly
  // displays the video https://github.com/flutter/flutter/issues/17606#issuecomment-413473181
  NSInteger rotationDegrees = (NSInteger)round(radiansToDegrees(atan2(transform.b, transform.a)));
  if (rotationDegrees == 90) {
    transform.tx = videoTrack.naturalSize.height;
    transform.ty = 0;
  } else if (rotationDegrees == 180) {
    transform.tx = videoTrack.naturalSize.width;
    transform.ty = videoTrack.naturalSize.height;
  } else if (rotationDegrees == 270) {
    transform.tx = 0;
    transform.ty = videoTrack.naturalSize.width;
  }
  return transform;
}

- (void)setDataSourceAsset:(NSString*)asset withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int) overriddenDuration{
    NSString* path = [[NSBundle mainBundle] pathForResource:asset ofType:nil];
    return [self setDataSourceURL:[NSURL fileURLWithPath:path] withKey:key withCertificateUrl:certificateUrl withLicenseUrl:(NSString*)licenseUrl withHeaders: @{} withCache: false cacheKey:cacheKey cacheManager:cacheManager overriddenDuration:overriddenDuration videoExtension: nil shouldEnableSSAI:false];
}
// Helper method to get RDID (IDFA)
- (NSString *)getRDID {
   // NSLog(@"[BetterPlayer] START: Getting RDID...");
    
    @try {
        BOOL isTrackingEnabled = [[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled];
      //  NSLog(@"[BetterPlayer] Advertising tracking enabled: %@", isTrackingEnabled ? @"YES" : @"NO");
        
        if (isTrackingEnabled) {
            NSUUID *idfaUUID = [[ASIdentifierManager sharedManager] advertisingIdentifier];
            NSString *idfaString = [idfaUUID UUIDString];
      //      NSLog(@"[BetterPlayer] SUCCESS: Got RDID (IDFA): %@", idfaString);
            return idfaString;
        } else {
            // Generate random UUID when tracking is disabled
            NSUUID *randomUUID = [NSUUID UUID];
            NSString *randomUUIDString = [randomUUID UUIDString];
       //     NSLog(@"[BetterPlayer] Tracking disabled, generated random UUID: %@", randomUUIDString);
            return randomUUIDString;
        }
    }
    @catch (NSException *exception) {
   //     NSLog(@"[BetterPlayer] EXCEPTION in getRDID: %@", exception.description);
   //     NSLog(@"[BetterPlayer] Exception reason: %@", exception.reason);
        NSUUID *fallbackUUID = [NSUUID UUID];
    //    NSLog(@"[BetterPlayer] Using fallback UUID: %@", [fallbackUUID UUIDString]);
        return [fallbackUUID UUIDString];
    }
}

// Helper method to extract query parameter from URL
- (NSString *)extractQueryParameterValue:(NSURL *)url parameterName:(NSString *)paramName {
  //  NSLog(@"[BetterPlayer] START: Extracting query parameter '%@' from URL: %@", paramName, url.absoluteString);
    
    @try {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
      //  NSLog(@"[BetterPlayer] URL components created successfully");
        
        if (components == nil) {
        //    NSLog(@"[BetterPlayer] ERROR: Failed to create URL components from URL");
            return @"";
        }
        
     //   NSLog(@"[BetterPlayer] Total query items found: %lu", (unsigned long)components.queryItems.count);
        
        for (NSURLQueryItem *queryItem in components.queryItems) {
         //   NSLog(@"[BetterPlayer] Query item - Name: %@, Value: %@", queryItem.name, queryItem.value);
            
            if ([queryItem.name isEqualToString:paramName]) {
                NSString *value = queryItem.value ? queryItem.value : @"";
              //  NSLog(@"[BetterPlayer] SUCCESS: Found parameter '%@' with value: %@", paramName, value);
                return value;
            }
        }
        
     //   NSLog(@"[BetterPlayer] WARNING: Parameter '%@' not found in URL query items", paramName);
        return @"";
    }
    @catch (NSException *exception) {
     //   NSLog(@"[BetterPlayer] EXCEPTION in extractQueryParameterValue: %@", exception.description);
    //    NSLog(@"[BetterPlayer] Exception reason: %@", exception.reason);
        return @"";
    }
}

// Helper method to add player parameters to URL
- (NSURL *)addPlayerParametersToURL:(NSURL *)baseURL {
  //  NSLog(@"[BetterPlayer] START: addPlayerParametersToURL with base URL: %@", baseURL.absoluteString);
    
    @try {
        NSString *baseURLString = baseURL.absoluteString;
    //    NSLog(@"[BetterPlayer] Base URL string created: %@", baseURLString);
        
        // Get RDID
     //   NSLog(@"[BetterPlayer] Calling getRDID...");
        NSString *rdid = [self getRDID];
     //   NSLog(@"[BetterPlayer] RDID obtained: %@", rdid);
        
        // Note: sessionID removed as per requirements
        
        // Build player_params format: player_params.idtype=value&player_params.an=value etc.
        NSMutableArray *playerParamsComponents = [NSMutableArray array];
     //   NSLog(@"[BetterPlayer] Building player parameters array...");
        
        // Add each parameter with player_params prefix
        NSString *param1 = @"ads.idtype=idfa";
        [playerParamsComponents addObject:param1];
    //    NSLog(@"[BetterPlayer] Added param: %@", param1);
        
        NSString *anValue = [@"Swift TV" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *param2 = [NSString stringWithFormat:@"ads.an=%@", anValue];
        [playerParamsComponents addObject:param2];
      //  NSLog(@"[BetterPlayer] Added param: %@", param2);
        
        NSString *msidValue = [@"com.thegermanemedia.swiftTvFe" stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *param3 = [NSString stringWithFormat:@"ads.msid=%@", msidValue];
        [playerParamsComponents addObject:param3];
      //  NSLog(@"[BetterPlayer] Added param: %@", param3);
        
        NSString *rdidValue = [rdid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *param4 = [NSString stringWithFormat:@"ads.rdid=%@", rdidValue];
        [playerParamsComponents addObject:param4];
      //  NSLog(@"[BetterPlayer] Added param: %@", param4);
        
        // Combine all player params
        NSString *playerParamString = [playerParamsComponents componentsJoinedByString:@"&"];
     //   NSLog(@"[BetterPlayer] Combined player parameters: %@", playerParamString);
        
        NSString *fullURLString = [NSString stringWithFormat:@"%@?%@", baseURLString, playerParamString];
     //   NSLog(@"[BetterPlayer] Full URL with parameters: %@", fullURLString);
        
        NSURL *finalURL = [NSURL URLWithString:fullURLString];
        
        if (finalURL == nil) {
       //     NSLog(@"[BetterPlayer] ERROR: Failed to create NSURL from full URL string");
            return baseURL;
        }
        
      //  NSLog(@"[BetterPlayer] SUCCESS: Final URL created: %@", finalURL.absoluteString);
        return finalURL;
    }
    @catch (NSException *exception) {
     //   NSLog(@"[BetterPlayer] EXCEPTION in addPlayerParametersToURL: %@", exception.description);
     //   NSLog(@"[BetterPlayer] Exception reason: %@", exception.reason);
     //   NSLog(@"[BetterPlayer] Returning original base URL due to exception");
        return baseURL;
    }
}

// Main setup method
- (void)setDataSourceURL:(NSURL*)url withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl withHeaders:(NSDictionary*)headers withCache:(BOOL)useCache cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int) overriddenDuration videoExtension: (NSString*) videoExtension shouldEnableSSAI:(BOOL)shouldEnableSSAI {
    
    //NSLog(@"[BetterPlayer] Setting up player. URL: %@, SSAI: %@", 
      //    url.absoluteString, shouldEnableSSAI ? @"YES" : @"NO");
    
    NSURL *sessionURL;
    
    if(shouldEnableSSAI) {
        // Create session URL by replacing "master" with "session"
        NSString *originalURLString = url.absoluteString;
        NSString *sessionURLString = [originalURLString stringByReplacingOccurrencesOfString:@"/master/"
                                                                                  withString:@"/session/"];
        
       // NSLog(@"[BetterPlayer] Original URL: %@", originalURLString);
      //  NSLog(@"[BetterPlayer] Session URL: %@", sessionURLString);
        
        // Convert to NSURL
        NSURL *baseSessionURL = [NSURL URLWithString:sessionURLString];
        
        // Add player parameters to session URL
        sessionURL = [self addPlayerParametersToURL:baseSessionURL];
    }
    
    if (shouldEnableSSAI && sessionURL) {
       // NSLog(@"[BetterPlayer] will start the process of SSAI setup");
        
        // Try SSAI/MediaTailor setup with session URL containing player parameters
        [self attemptSSAISetupWithURL:sessionURL 
                             withKey:key
                              headers:headers 
                           cacheKey:cacheKey 
                      cacheManager:cacheManager 
                         useCache:useCache 
                   videoExtension:videoExtension 
                  overriddenDuration:overriddenDuration];
    } else {
      //  NSLog(@"[BetterPlayer] will start the process of Regular setup");
        
        // Regular HLS flow
        [self setupRegularPlayerWithURL:url 
                                withKey:key
                          withLicenseUrl:licenseUrl 
                     withCertificateUrl:certificateUrl 
                           withCacheKey:cacheKey 
                     withVideoExtension:videoExtension 
                            withHeaders:headers 
                             withCache:useCache 
                          cacheManager:cacheManager 
                      overriddenDuration:overriddenDuration];
        
        // Setup Datazoom WITH the player
        [self setupDatazoomWithPlayer:self.player];
    }
}
// ============================================
// FUNCTION 1: Initialize MediaTailor SDK (One-time)
// ============================================
- (void)initializeMediaTailorSDK {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      //  NSLog(@"[BetterPlayer] INITIALIZING MEDIATAILOR SDK");
        
        @try {
            // 1. Get MediaTailor instance
            MTSDKMediaTailor *mediaTailor = [MTSDKMediaTailor shared];
          //  NSLog(@"[BetterPlayer] MediaTailor instance: %p", mediaTailor);
            
            // 2. Create PAL consent settings
            MTSDKPalConsentSettingsBuilder *consentBuilder = [[MTSDKPalConsentSettingsBuilder alloc] init];
            [consentBuilder allowStorageValue:YES];
            MTSDKPalConsentSettings *consentSettings = [consentBuilder build];
            
            // 3. Initialize PAL consent
            [mediaTailor doInitPalConsentSettings:consentSettings];
          //  NSLog(@"[BetterPlayer] ✅ PAL Consent initialized");
            
            // 4. Verify initialization worked
            if (mediaTailor) {
         //       NSLog(@"[BetterPlayer] ✅ MediaTailor SDK ready for session creation");
            } else {
          //      NSLog(@"[BetterPlayer] ❌ MediaTailor instance is nil");
            }
            
        } @catch (NSException *e) {
       //     NSLog(@"[BetterPlayer] ❌ MediaTailor INIT ERROR: %@ | Reason: %@",
          //        e.name, e.reason);
        }
    });
}
    
    // ============================================
    // FUNCTION 2: Create PAL Nonce Request Parameters
    // ============================================
    
    - (MTSDKPalNonceRequestParams *)createPalNonceRequestParamsWithContentURL:(NSString *)contentURL {
        
      //  NSLog(@"[BetterPlayer] Creating PAL nonce request params for: %@", contentURL);
        
        @try {
            if (!contentURL || contentURL.length == 0) {
             //   NSLog(@"[BetterPlayer] ❌ Invalid content URL");
                return nil;
            }
            
            MTSDKPalNonceRequestParamsBuilder *paramsBuilder = [[MTSDKPalNonceRequestParamsBuilder alloc] init];
            
            if (!paramsBuilder) {
          //      NSLog(@"[BetterPlayer] ❌ Failed to create PAL params builder");
                return nil;
            }
            
            // Set required parameters
            [paramsBuilder descriptionUrlValue:@"https://playswift.tv"];
            [paramsBuilder omidPartnerNameValue:@"amazon2"];
            [paramsBuilder omidPartnerVersionValue:@"1.0.0"];
            
            // Set player configuration
            [paramsBuilder playerTypeValue:@"BetterPlayer"];
            [paramsBuilder playerVersionValue:@"1.0"];
            [paramsBuilder adWillAutoPlayValue:YES];
            [paramsBuilder adWillPlayMutedValue:NO];
            [paramsBuilder continuousPlaybackValue:YES];
            [paramsBuilder iconsSupportedValue:YES];
            
            // Set video dimensions
            [paramsBuilder videoHeightValue:1080];
            [paramsBuilder videoWidthValue:1920];
            
            MTSDKPalNonceRequestParams *palNonceRequestParams = [paramsBuilder build];
            
            if (!palNonceRequestParams) {
        //        NSLog(@"[BetterPlayer] ❌ Failed to build PAL nonce params");
                return nil;
            }
            
          //  NSLog(@"[BetterPlayer] ✅ PAL nonce params created successfully");
            
            return palNonceRequestParams;
            
        } @catch (NSException *e) {
          //  NSLog(@"[BetterPlayer] ❌ Exception in createPalNonceRequestParams: %@", e.reason);
            return nil;
        }
    }
    
    // ============================================
    // FUNCTION 3: Create MediaTailor Session Configuration
    // ============================================
    - (MTSDKSessionConfiguration *)createMediaTailorSessionConfigWithContentURL:(NSString *)contentURL
    palNonceParams:(MTSDKPalNonceRequestParams *)palNonceParams
    headers:(NSDictionary *)headers {

     //   NSLog(@"[BetterPlayer] Creating MediaTailor session config");

        MTSDKSessionConfigurationBuilder *configBuilder = [[MTSDKSessionConfigurationBuilder alloc] init];

        // 1. Set the PAL nonce request params (required)
        [configBuilder palNonceRequestParamsValue:palNonceParams];

        // 2. Set basic player parameters (as dictionary), overlaying every MediaTailor
        //    ad-param macro the Dart side sent via headers so SSAI targeting reaches the
        //    ad server. Keep this key list in sync with MediaTailorHelper.adParamHeaderKeys.
        NSMutableDictionary *playerParams = [@{
            @"playerType": @"BetterPlayer",
            @"playerVersion": @"1.0"
        } mutableCopy];
        NSArray<NSString *> *adParamHeaderKeys = @[
            @"msid", @"idtype", @"AV_PUBLISHERID", @"AV_CHANNELID", @"AV_APPSTOREURL",
            @"AV_RTB_DEVICE_TYPE", @"AV_WIDTH", @"AV_HEIGHT", @"AV_LATITUDE", @"AV_LONGITUDE",
            @"AV_APP_DOMAIN", @"AV_SCHAIN", @"AV_CONTENT_CONTEXT", @"AV_CONTENT_KEYWORDS",
            @"AV_CONTENT_LANGUAGE", @"AV_CONTENT_TITLE", @"AV_CONTENT_SERIES",
            @"AV_CONTENT_NETWORK_NAME", @"AV_CONTENT_DIST_NAME", @"AV_CONTENT_CAT",
            @"AV_CONTENT_ID", @"AV_CONTENT_URL", @"AV_CONTENT_CHANNEL", @"AV_CONTENT_GENRE",
            @"AV_CONTENT_RATING", @"AV_CONTENT_PRODQ", @"ssai_e", @"ssai_p", @"livestream", @"coppa"
        ];
        if ([headers isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in adParamHeaderKeys) {
                id value = headers[key];
                if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                    playerParams[key] = value;
                }
            }
        }
        [configBuilder playerParamsValue:playerParams];
        
        // 3. adding the sessionInitUrl
        [configBuilder sessionInitUrlValue:contentURL];
        
        // 4. Build the configuration
        MTSDKSessionConfiguration *sessionConfig = [configBuilder build];
        
        //
        
     //   NSLog(@"[BetterPlayer] 🧪 TEST 3: Calling createSessionConfig...");
        // TEST 3: Try to call createSessionConfig
        
      
        
    //    NSLog(@"[BetterPlayer] Session config created");
        
        return sessionConfig;
    }
    
    // ============================================
    // FUNCTION 4 (UPDATED): Handle Successful MediaTailor Session
    // ============================================
  - (void)handleMediaTailorSessionSuccessWithOriginalURL:(NSURL *)originalURL
    withKey:(NSString*)key
    session:(MTSDKSession *)session
    playbackURL:(NSString *)playbackURL
    sessionId:(NSString *)sessionId
    headers:(NSDictionary *)headers
    cacheKey:(NSString *)cacheKey
    cacheManager:(CacheManager *)cacheManager
    useCache:(BOOL)useCache
    videoExtension:(NSString *)videoExtension
    overriddenDuration:(int)overriddenDuration {
        
     //   NSLog(@"[BetterPlayer] Handling successful MediaTailor session: %@", sessionId);
        
        // 1. Send success event to Flutter
        [self sendSSAISuccessEvent:originalURL.absoluteString
                         sessionId:sessionId
                       playbackUrl:playbackURL];
        
        // 2. Create player with ad-stitched URL
        NSURL *playbackNSURL = [NSURL URLWithString:playbackURL];
        if (!playbackNSURL) {
     //       NSLog(@"[BetterPlayer] ERROR: Invalid playback URL");
            [self sendSSAIFailureEvent:originalURL.absoluteString
                             sessionId:sessionId
                                 error:@"Invalid playback URL"];
            [self fallbackToRegularPlayerWithURL:originalURL
                                         withKey:key
                                         headers:headers
                                        cacheKey:cacheKey
                                    cacheManager:cacheManager
                                        useCache:useCache
                                  videoExtension:videoExtension
                              overriddenDuration:overriddenDuration];
            return;
        }
        
        // Create the player
        [self setupRegularPlayerWithURL:playbackNSURL
                                withKey:key
                         withLicenseUrl:nil
                     withCertificateUrl:nil
                           withCacheKey:nil  // Don't cache SSAI
                     withVideoExtension:nil
                            withHeaders:headers
                              withCache:NO   // Don't cache
                           cacheManager:cacheManager
                     overriddenDuration:overriddenDuration];
        
        // 3. Setup Datazoom WITH the created player (CORRECT ORDER)
        [self setupDatazoomWithPlayer:self.player];
        
        // 4. Link MediaTailor session to Datazoom adapter
        [self linkMediaTailorSessionToDatazoom:session
                                   originalURL:originalURL.absoluteString];
        
        // 5. Set metadata
        [self setSSAIMetadataWithOriginalURL:originalURL.absoluteString
                                 playbackURL:playbackURL
                                   sessionId:sessionId];
        
     //   NSLog(@"[BetterPlayer] SSAI setup complete for session: %@", sessionId);
    }
// Helper method to setup the player
- (void)setupPlayerWithURL:(NSURL *)url
                   withKey:(NSString *)key
                   headers:(NSDictionary *)headers
                  cacheKey:(NSString *)cacheKey
              cacheManager:(CacheManager *)cacheManager
                  useCache:(BOOL)useCache
            videoExtension:(NSString *)videoExtension
      overriddenDuration:(int)overriddenDuration {
    
    // Your existing player setup code here
    AVAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
    
    [self.player replaceCurrentItemWithPlayerItem:playerItem];
    
    if (overriddenDuration > 0) {
        self.overriddenDuration = overriddenDuration;
    }
    
  //  NSLog(@"[BetterPlayer] ✅ SSAI player setup complete");
}
    // ============================================
    // FUNCTION 5: Send SSAI Success Event to Flutter
    // ============================================
    - (void)sendSSAISuccessEvent:(NSString *)url
    sessionId:(NSString *)sessionId
    playbackUrl:(NSString *)playbackUrl {
        
        if (!self.eventSink) {
      //      NSLog(@"[BetterPlayer] WARNING: No eventSink to send success event");
            return;
        }
        
        NSDictionary *eventData = @{
            @"event": @"ssai_session_success",
            @"url": url ?: @"",
            @"sessionId": sessionId ?: @"",
            @"playbackUrl": playbackUrl ?: @"",
            @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000)
        };
        
        self.eventSink(eventData);
        
     //   NSLog(@"[BetterPlayer] Sent SSAI success event: %@", sessionId);
    }
    
    // ============================================
    // FUNCTION 6 (CORRECTED & SIMPLIFIED): Link MediaTailor Session to Datazoom
    // ============================================
    - (void)linkMediaTailorSessionToDatazoom:(MTSDKSession *)session
    originalURL:(NSString *)originalURLString { 
        
      //  NSLog(@"[BetterPlayer] Linking MediaTailor session to Datazoom via Swift bridge");
        
        if (!self.datazoomAdapter) {
         //   NSLog(@"[BetterPlayer] ERROR: No Datazoom adapter available");
            return;
        }
        
        if (!session) {
        //    NSLog(@"[BetterPlayer] ERROR: No MediaTailor session to link");
            return;
        }
        
        // Get the Swift bridge
        DzBridge *bridge = [DzBridge shared];
        
        // Configure MediaTailor through Swift bridge
        BOOL success = [bridge configureMediaTailorWithAdapter:self.datazoomAdapter
                                                       session:session
                                                      videoUrl:originalURLString];
        
        if (success) {
        //    NSLog(@"[BetterPlayer] ✅ MediaTailor session linked to Datazoom");
            
            // Update metadata
            NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:@{
                @"original_url": originalURLString ?: @"",
                @"ssai_enabled": @YES,
                @"ssai_session_id": session.palNonce ?: @"unknown",
                @"ssai_provider": @"aws_mediatailor",
                @"pal_configured": @YES,
                @"datazoom_linked": @YES
            }];
            
            // Update Datazoom metadata
            DzBaseDatazoom *datazoom = [DzBaseDatazoom shared];
            [datazoom setMetadataMetadata:metadata];
            
        } else {
         //   NSLog(@"[BetterPlayer] ❌ ERROR: Failed to link MediaTailor session");
        }
    }
    
    // ============================================
    // FUNCTION: Create Datazoom Context with AVPlayer (UPDATED)
    // ============================================
    - (void)setupDatazoomWithPlayer:(AVPlayer *)player {
        
        if (!player) {
       //     NSLog(@"[BetterPlayer] ERROR: No player to setup Datazoom");
            return;
        }
        
        // NSLog(@"[BetterPlayer] Setting up Datazoom via Swift bridge");
        
        // Get the Swift bridge
        DzBridge *bridge = [DzBridge shared];
        
        // Create adapter through Swift bridge
        id adapter = [bridge createAdapterWithPlayer:player];
        
        if (adapter) {
            self.datazoomAdapter = adapter;
           // NSLog(@"[BetterPlayer] ✅ Datazoom adapter created via bridge");
        } else {
         //   NSLog(@"[BetterPlayer] ❌ ERROR: Failed to create Datazoom adapter");
        }
    }
    // ============================================
    // FUNCTION 9: Fallback to Regular Player
    // ============================================
    - (void)fallbackToRegularPlayerWithURL:(NSURL *)url
    withKey:(NSString*)key
    headers:(NSDictionary *)headers
    cacheKey:(NSString *)cacheKey
    cacheManager:(CacheManager *)cacheManager
    useCache:(BOOL)useCache
    videoExtension:(NSString *)videoExtension
    overriddenDuration:(int)overriddenDuration {
        
      //  NSLog(@"[BetterPlayer] Falling back to regular HLS playback with key: %@", key);
        
        // Use the existing regular player setup
        [self setupRegularPlayerWithURL:url
                                withKey:key
                         withLicenseUrl:nil
                     withCertificateUrl:nil
                           withCacheKey:cacheKey
                     withVideoExtension:videoExtension
                            withHeaders:headers
                              withCache:useCache
                           cacheManager:cacheManager
                     overriddenDuration:overriddenDuration];
        
        
        // Setup Datazoom WITH the created player
        [self setupDatazoomWithPlayer:self.player];
        
      //  NSLog(@"[BetterPlayer] Fallback to regular player complete");
    }
    
    // ============================================
    // FUNCTION 10: Set SSAI Metadata for Datazoom
    // ============================================
    - (void)setSSAIMetadataWithOriginalURL:(NSString *)originalURL
    playbackURL:(NSString *)playbackURL
    sessionId:(NSString *)sessionId {
        
        NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:@{
            @"original_url": originalURL ?: @"",
            @"playback_url": playbackURL ?: @"",
            @"ssai_enabled": @YES,
            @"ssai_session_id": sessionId ?: @"unknown",
            @"ssai_provider": @"aws_mediatailor",
            @"player_type": @"BetterPlayer",
            @"pal_configured": @YES,
            @"datazoom_linked": @(self.datazoomAdapter != nil) // Dynamic based on actual state
        }];
        
        [[DzBaseDatazoom shared] setMetadataMetadata:metadata];
        
       // NSLog(@"[BetterPlayer] SSAI metadata set for session: %@", sessionId);
    }
    
    // ============================================
    // FUNCTION 11: Handle Failed MediaTailor Session
    // ============================================
    - (void)handleMediaTailorSessionFailureWithOriginalURL:(NSURL *)originalURL
    withKey:(NSString*)key
    error:(MTSDKSessionError *)error
    headers:(NSDictionary *)headers
    cacheKey:(NSString *)cacheKey
    cacheManager:(CacheManager *)cacheManager
    useCache:(BOOL)useCache
    videoExtension:(NSString *)videoExtension
    overriddenDuration:(int)overriddenDuration {
        
        NSString *errorMsg = @"Unknown MediaTailor error";
        if (error) {
            errorMsg = [NSString stringWithFormat:@"Code: %@", error.code];        if (error.message) {
                errorMsg = [NSString stringWithFormat:@"%@ - %@", errorMsg, error.message];
            }
        }
        
       // NSLog(@"[BetterPlayer] SSAI setup failed: %@", errorMsg);
        
        // Send failure event to Flutter
        [self sendSSAIFailureEvent:originalURL.absoluteString
                         sessionId:nil
                             error:errorMsg];
        
        // Fallback to regular player
        [self fallbackToRegularPlayerWithURL:originalURL
                                     withKey:key
                                     headers:headers
                                    cacheKey:cacheKey
                                cacheManager:cacheManager
                                    useCache:useCache
                              videoExtension:videoExtension
                          overriddenDuration:overriddenDuration];
    }
    
    // ============================================
    // FUNCTION 12: Send SSAI Failure Event to Flutter
    // ============================================
    - (void)sendSSAIFailureEvent:(NSString *)url
    sessionId:(NSString *)sessionId
    error:(NSString *)error {
        
        if (!self.eventSink) {
          //  NSLog(@"[BetterPlayer] WARNING: No eventSink to send failure event");
            return;
        }
        
        NSMutableDictionary *eventData = [NSMutableDictionary dictionaryWithDictionary:@{
            @"event": @"ssai_session_failure",
            @"url": url ?: @"",
            @"error": error ?: @"Unknown error",
            @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000)
        }];
        
        // Handle sessionId (could be nil)
        if (sessionId) {
            eventData[@"sessionId"] = sessionId;
        } else {
            eventData[@"sessionId"] = [NSNull null]; // Explicit null for Flutter
        }
        
        self.eventSink(eventData);
        
     //   NSLog(@"[BetterPlayer] Sent SSAI failure event: %@", error);
    }
    
    
- (void)attemptSSAISetupWithURL:(NSURL *)url
    withKey:(NSString*)key
    headers:(NSDictionary*)headers
    cacheKey:(NSString*)cacheKey
    cacheManager:(CacheManager*)cacheManager
    useCache:(BOOL)useCache
    videoExtension:(NSString*)videoExtension
    overriddenDuration:(int)overriddenDuration {
        
       // NSLog(@"[BetterPlayer] 🔄 Attempting SSAI setup for: %@", url.absoluteString);
        
        @try {
            // Initialize DatazoomWrapper
            if (!self.datazoomWrapper) {
                self.datazoomWrapper = [[DatazoomWrapper alloc] init];
            }
            
        //    NSLog(@"[BetterPlayer] 📤 Calling createMediaTailorSession...");
            
            __weak typeof(self) weakSelf = self;
            
            [self.datazoomWrapper
             createMediaTailorSessionWithUrl: url.absoluteString
             headers: (headers ?: @{})
             onSuccess:^(NSString *mtSessionUrl, MTSDKSession* session) {
                 
                 __strong typeof(self) strongSelf = weakSelf;
                 if (!strongSelf) {
                   //  NSLog(@"[BetterPlayer] ❌ Self deallocated during callback");
                     return;
                 }
                 
                NSLog(@"[BetterPlayer] ========================================");
                 NSLog(@"[BetterPlayer] ✅ SSAI SUCCESS");
                 NSLog(@"[BetterPlayer] ========================================");
                 NSLog(@"[BetterPlayer]   - Playback URL: %@", mtSessionUrl);
             //    NSLog(@"[BetterPlayer]   - Session: %@", session);
                 
                 // Handle successful session creation
                 [strongSelf handleMediaTailorSessionSuccessWithOriginalURL:url
                                                                    withKey:key
                                                                    session:session
                                                                playbackURL:mtSessionUrl
                                                                  sessionId:@"datazoom-session"
                                                                    headers:headers
                                                                   cacheKey:cacheKey
                                                               cacheManager:cacheManager
                                                                   useCache:useCache
                                                             videoExtension:videoExtension
                                                         overriddenDuration:overriddenDuration];
             }
             onError:^(NSString *errorMessage) {
                 
                 __strong typeof(self) strongSelf = weakSelf;
                 if (!strongSelf) {
                //     NSLog(@"[BetterPlayer] ❌ Self deallocated during callback");
                     return;
                 }
                 
              //   NSLog(@"[BetterPlayer] ========================================");
              //   NSLog(@"[BetterPlayer] ❌ SSAI FAILED");
              //   NSLog(@"[BetterPlayer] ========================================");
              //   NSLog(@"[BetterPlayer]   - Error: %@", errorMessage);
                 
                 // Fallback to regular playback
                 [strongSelf fallbackToRegularPlayerWithURL:url
                                                    withKey:key
                                                    headers:headers
                                                   cacheKey:cacheKey
                                               cacheManager:cacheManager
                                                   useCache:useCache
                                             videoExtension:videoExtension
                                       overriddenDuration:overriddenDuration];
             }];  // Close the createMediaTailorSessionWithUrl call
            
        } @catch (NSException *e) {
         //   NSLog(@"[BetterPlayer] ❌ EXCEPTION in SSAI setup: %@", e.reason);
            [self fallbackToRegularPlayerWithURL:url withKey:key headers:headers
                                        cacheKey:cacheKey cacheManager:cacheManager
                                        useCache:useCache videoExtension:videoExtension
                              overriddenDuration:overriddenDuration];
        }
    }   
    
    // ============================================
    // CORRECT: setupRegularPlayerWithURL (Standalone Implementation)
    // ============================================
    - (void)setupRegularPlayerWithURL:(NSURL*)url
    withKey:(NSString*)key
    withLicenseUrl:(NSURL*)licenseUrl
    withCertificateUrl:(NSURL*)certificateUrl
    withCacheKey:(NSString*)cacheKey
    withVideoExtension:(NSString*)videoExtension
    withHeaders:(NSDictionary*)headers
    withCache:(BOOL)useCache
    cacheManager:(CacheManager*)cacheManager
    overriddenDuration:(int)overriddenDuration {
        
      //  NSLog(@"[BetterPlayer] Setting up regular player for: %@ with key: %@", url.absoluteString, key);
        // Reset overridden duration
        _overriddenDuration = 0;
        
        // Ensure headers is not null
        if (headers == [NSNull null] || headers == NULL){
            headers = @{};
        }
        
        AVPlayerItem* item;
        
        // 1. Create AVPlayerItem (with or without cache)
        if (useCache && cacheManager){
            if (cacheKey == [NSNull null]){
                cacheKey = nil;
            }
            if (videoExtension == [NSNull null]){
                videoExtension = nil;
            }
            
            item = [cacheManager getCachingPlayerItemForNormalPlayback:url
                                                              cacheKey:cacheKey
                                                        videoExtension:videoExtension
                                                               headers:headers];
        } else {
            // Non-cached playback
            AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url
                                                    options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
            
            // Handle DRM if license/certificate URLs provided
            if (certificateUrl && certificateUrl != [NSNull null]) {
                NSString *certificateUrlString = certificateUrl.absoluteString;
                NSString *licenseUrlString = licenseUrl.absoluteString;
                
                if (certificateUrlString && certificateUrlString.length > 0) {
                    NSURL *certificateNSURL = [NSURL URLWithString:certificateUrlString];
                    NSURL *licenseNSURL = [NSURL URLWithString:licenseUrlString];
                    
                    _loaderDelegate = [[BetterPlayerEzDrmAssetsLoaderDelegate alloc] init:certificateNSURL
                                                                           withLicenseURL:licenseNSURL];
                    dispatch_queue_attr_t qos = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                                        QOS_CLASS_DEFAULT, -1);
                    dispatch_queue_t streamQueue = dispatch_queue_create("streamQueue", qos);
                    [asset.resourceLoader setDelegate:_loaderDelegate queue:streamQueue];
                }
            }
            
            item = [AVPlayerItem playerItemWithAsset:asset];
        }
        
        // 2. Set overridden duration if applicable
        if (@available(iOS 10.0, *) && overriddenDuration > 0) {
            _overriddenDuration = overriddenDuration;
        }
        
        // 3. Setup the player with the item
        [self setupPlayerWithItem:item key:key];
    }
    
    // ============================================
    // HELPER: setupPlayerWithItem (Reusable player setup)
    // ============================================
    - (void)setupPlayerWithItem:(AVPlayerItem*)item key:(NSString*)key {
        _key = key;
        _stalledCount = 0;
        _isStalledCheckStarted = false;
        _playerRate = 1;
        
        // Create or replace player item
        if (_player) {
            [_player replaceCurrentItemWithPlayerItem:item];
        } else {
            _player = [AVPlayer playerWithPlayerItem:item];
        }
        
        // Handle video composition (rotation)
        AVAsset* asset = [item asset];
        void (^assetCompletionHandler)(void) = ^{
            if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
                NSArray* tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
                if ([tracks count] > 0) {
                    AVAssetTrack* videoTrack = tracks[0];
                    void (^trackCompletionHandler)(void) = ^{
                        if (self->_disposed) return;
                        if ([videoTrack statusOfValueForKey:@"preferredTransform"
                                                      error:nil] == AVKeyValueStatusLoaded) {
                            // Rotate the video by using a videoComposition
                            self->_preferredTransform = [self fixTransform:videoTrack];
                            AVMutableVideoComposition* videoComposition =
                            [self getVideoCompositionWithTransform:self->_preferredTransform
                                                         withAsset:asset
                                                    withVideoTrack:videoTrack];
                            item.videoComposition = videoComposition;
                        }
                    };
                    [videoTrack loadValuesAsynchronouslyForKeys:@[ @"preferredTransform" ]
                                              completionHandler:trackCompletionHandler];
                }
            }
        };
        
        [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ] completionHandler:assetCompletionHandler];
        [self addObservers:item];
    }
    
    // ============================================
    // NEW FUNCTION: Cleanup Datazoom Resources
    // ============================================
    - (void)cleanupDatazoom {
        if (self.datazoomAdapter) {
            // Get the Swift bridge
            DzBridge *bridge = [DzBridge shared];
            
            // Remove MediaTailor session from adapter
            if ([bridge respondsToSelector:@selector(removeMediaTailorSessionWithAdapter:)]) {
                [bridge removeMediaTailorSessionWithAdapter:self.datazoomAdapter];
            }
            
            // Clear the adapter reference
            self.datazoomAdapter = nil;
            
          //  NSLog(@"[BetterPlayer] Datazoom resources cleaned up");
        }
    }
    // Helper to get a unique player ID
    - (NSString *)getPlayerId {
        return [NSString stringWithFormat:@"player_%p", self];
    }
    
    - (void)setDataSourcePlayerItem:(AVPlayerItem*)item withKey:(NSString*)key{
        _key = key;
        _stalledCount = 0;
        _isStalledCheckStarted = false;
        _playerRate = 1;
        [_player replaceCurrentItemWithPlayerItem:item];
        
        AVAsset* asset = [item asset];
        void (^assetCompletionHandler)(void) = ^{
            if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
                NSArray* tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
                if ([tracks count] > 0) {
                    AVAssetTrack* videoTrack = tracks[0];
                    void (^trackCompletionHandler)(void) = ^{
                        if (self->_disposed) return;
                        if ([videoTrack statusOfValueForKey:@"preferredTransform"
                                                      error:nil] == AVKeyValueStatusLoaded) {
                            // Rotate the video by using a videoComposition and the preferredTransform
                            self->_preferredTransform = [self fixTransform:videoTrack];
                            // Note:
                            // https://developer.apple.com/documentation/avfoundation/avplayeritem/1388818-videocomposition
                            // Video composition can only be used with file-based media and is not supported for
                            // use with media served using HTTP Live Streaming.
                            AVMutableVideoComposition* videoComposition =
                            [self getVideoCompositionWithTransform:self->_preferredTransform
                                                         withAsset:asset
                                                    withVideoTrack:videoTrack];
                            item.videoComposition = videoComposition;
                        }
                    };
                    [videoTrack loadValuesAsynchronouslyForKeys:@[ @"preferredTransform" ]
                                              completionHandler:trackCompletionHandler];
                }
            }
        };
        
        [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ] completionHandler:assetCompletionHandler];
        [self addObservers:item];
    }
    
    -(void)handleStalled {
        if (_isStalledCheckStarted){
            return;
        }
        _isStalledCheckStarted = true;
        [self startStalledCheck];
    }
    
    -(void)startStalledCheck{
        if (_player.currentItem.playbackLikelyToKeepUp ||
            [self availableDuration] - CMTimeGetSeconds(_player.currentItem.currentTime) > 10.0) {
            [self play];
        } else {
            _stalledCount++;
            if (_stalledCount > 60){
                if (_eventSink != nil) {
                    _eventSink([FlutterError
                                errorWithCode:@"VideoError"
                                message:@"Failed to load video: playback stalled"
                                details:nil]);
                }
                return;
            }
            [self performSelector:@selector(startStalledCheck) withObject:nil afterDelay:1];
            
        }
    }
    
    - (NSTimeInterval) availableDuration
    {
        NSArray *loadedTimeRanges = [[_player currentItem] loadedTimeRanges];
        if (loadedTimeRanges.count > 0){
            CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
            Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
            Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);
            NSTimeInterval result = startSeconds + durationSeconds;
            return result;
        } else {
            return 0;
        }
        
    }
    
    - (void)observeValueForKeyPath:(NSString*)path
    ofObject:(id)object
    change:(NSDictionary*)change
    context:(void*)context {
        
        if ([path isEqualToString:@"rate"]) {
            if (@available(iOS 10.0, *)) {
                if (_pipController.pictureInPictureActive == true){
                    if (_lastAvPlayerTimeControlStatus != [NSNull null] && _lastAvPlayerTimeControlStatus == _player.timeControlStatus){
                        return;
                    }
                    
                    if (_player.timeControlStatus == AVPlayerTimeControlStatusPaused){
                        _lastAvPlayerTimeControlStatus = _player.timeControlStatus;
                        if (_eventSink != nil) {
                            _eventSink(@{@"event" : @"pause"});
                        }
                        return;
                        
                    }
                    if (_player.timeControlStatus == AVPlayerTimeControlStatusPlaying){
                        _lastAvPlayerTimeControlStatus = _player.timeControlStatus;
                        if (_eventSink != nil) {
                            _eventSink(@{@"event" : @"play"});
                        }
                    }
                }
            }
            
            if (_player.rate == 0 && //if player rate dropped to 0
                CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, >, kCMTimeZero) && //if video was started
                CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, <, _player.currentItem.duration) && //but not yet finished
                _isPlaying) { //instance variable to handle overall state (changed to YES when user triggers playback)
                [self handleStalled];
            }
        }
        
        if (context == timeRangeContext) {
            if (_eventSink != nil) {
                NSMutableArray<NSArray<NSNumber*>*>* values = [[NSMutableArray alloc] init];
                for (NSValue* rangeValue in [object loadedTimeRanges]) {
                    CMTimeRange range = [rangeValue CMTimeRangeValue];
                    int64_t start = [BetterPlayerTimeUtils FLTCMTimeToMillis:(range.start)];
                    int64_t end = start + [BetterPlayerTimeUtils FLTCMTimeToMillis:(range.duration)];
                    if (!CMTIME_IS_INVALID(_player.currentItem.forwardPlaybackEndTime)) {
                        int64_t endTime = [BetterPlayerTimeUtils FLTCMTimeToMillis:(_player.currentItem.forwardPlaybackEndTime)];
                        if (end > endTime){
                            end = endTime;
                        }
                    }
                    
                    [values addObject:@[ @(start), @(end) ]];
                }
                _eventSink(@{@"event" : @"bufferingUpdate", @"values" : values, @"key" : _key});
            }
        }
        else if (context == presentationSizeContext){
            [self onReadyToPlay];
        }
        
        else if (context == statusContext) {
            AVPlayerItem* item = (AVPlayerItem*)object;
            switch (item.status) {
                case AVPlayerItemStatusFailed:
                    NSLog(@"Failed to load video:");
              NSLog(item.error.debugDescription);
                    
                    if (_eventSink != nil) {
                        _eventSink([FlutterError
                                    errorWithCode:@"VideoError"
                                    message:[@"Failed to load video: "
                                             stringByAppendingString:[item.error localizedDescription]]
                                    details:nil]);
                    }
                    break;
                case AVPlayerItemStatusUnknown:
                    break;
                case AVPlayerItemStatusReadyToPlay:
                    [self onReadyToPlay];
                    break;
            }
        } else if (context == playbackLikelyToKeepUpContext) {
            if ([[_player currentItem] isPlaybackLikelyToKeepUp]) {
                [self updatePlayingState];
                if (_eventSink != nil) {
                    _eventSink(@{@"event" : @"bufferingEnd", @"key" : _key});
                }
            }
        } else if (context == playbackBufferEmptyContext) {
            if (_eventSink != nil) {
                _eventSink(@{@"event" : @"bufferingStart", @"key" : _key});
            }
        } else if (context == playbackBufferFullContext) {
            if (_eventSink != nil) {
                _eventSink(@{@"event" : @"bufferingEnd", @"key" : _key});
            }
        }
    }
    
    - (void)updatePlayingState {
        if (!_isInitialized || !_key) {
            return;
        }
        if (!self._observersAdded){
            [self addObservers:[_player currentItem]];
        }
        
        if (_isPlaying) {
            if (@available(iOS 10.0, *)) {
                [_player playImmediatelyAtRate:1.0];
                _player.rate = _playerRate;
            } else {
                [_player play];
                _player.rate = _playerRate;
            }
        } else {
            [_player pause];
        }
    }
    
    - (void)onReadyToPlay {
        if (_eventSink && !_isInitialized && _key) {
            if (!_player.currentItem) {
                return;
            }
            if (_player.status != AVPlayerStatusReadyToPlay) {
                return;
            }
            
            CGSize size = [_player currentItem].presentationSize;
            CGFloat width = size.width;
            CGFloat height = size.height;
            
            
            AVAsset *asset = _player.currentItem.asset;
            bool onlyAudio =  [[asset tracksWithMediaType:AVMediaTypeVideo] count] == 0;
            
            // The player has not yet initialized.
            if (!onlyAudio && height == CGSizeZero.height && width == CGSizeZero.width) {
                return;
            }
            const BOOL isLive = CMTIME_IS_INDEFINITE([_player currentItem].duration);
            // The player may be initialized but still needs to determine the duration.
            if (isLive == false && [self duration] == 0) {
                return;
            }
            
            //Fix from https://github.com/flutter/flutter/issues/66413
            AVPlayerItemTrack *track = [self.player currentItem].tracks.firstObject;
            CGSize naturalSize = track.assetTrack.naturalSize;
            CGAffineTransform prefTrans = track.assetTrack.preferredTransform;
            CGSize realSize = CGSizeApplyAffineTransform(naturalSize, prefTrans);
            
            int64_t duration = [BetterPlayerTimeUtils FLTCMTimeToMillis:(_player.currentItem.asset.duration)];
            if (_overriddenDuration > 0 && duration > _overriddenDuration){
                _player.currentItem.forwardPlaybackEndTime = CMTimeMake(_overriddenDuration/1000, 1);
            }
            
            _isInitialized = true;
            [self updatePlayingState];
            _eventSink(@{
                @"event" : @"initialized",
                @"duration" : @([self duration]),
                @"width" : @(fabs(realSize.width) ? : width),
                @"height" : @(fabs(realSize.height) ? : height),
                @"key" : _key
            });
        }
    }
    
    - (void)play {
        _stalledCount = 0;
        _isStalledCheckStarted = false;
        _isPlaying = true;
        [self updatePlayingState];
    }
    
    - (void)pause {
        _isPlaying = false;
        [self updatePlayingState];
    }
    
    - (int64_t)position {
        return [BetterPlayerTimeUtils FLTCMTimeToMillis:([_player currentTime])];
    }
    
    - (int64_t)absolutePosition {
        return [BetterPlayerTimeUtils FLTNSTimeIntervalToMillis:([[[_player currentItem] currentDate] timeIntervalSince1970])];
    }
    
    - (int64_t)duration {
        CMTime time;
        if (@available(iOS 13, *)) {
            time =  [[_player currentItem] duration];
        } else {
            time =  [[[_player currentItem] asset] duration];
        }
        if (!CMTIME_IS_INVALID(_player.currentItem.forwardPlaybackEndTime)) {
            time = [[_player currentItem] forwardPlaybackEndTime];
        }
        
        return [BetterPlayerTimeUtils FLTCMTimeToMillis:(time)];
    }
    
    - (void)seekTo:(int)location {
        ///When player is playing, pause video, seek to new position and start again. This will prevent issues with seekbar jumps.
        bool wasPlaying = _isPlaying;
        if (wasPlaying){
            [_player pause];
        }
        
        [_player seekToTime:CMTimeMake(location, 1000)
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished){
            if (wasPlaying){
                _player.rate = _playerRate;
            }
        }];
    }
    
    - (void)setIsLooping:(bool)isLooping {
        _isLooping = isLooping;
    }
    
    - (void)setVolume:(double)volume {
        _player.volume = (float)((volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume));
    }
    
    - (void)setSpeed:(double)speed result:(FlutterResult)result {
        if (speed == 1.0 || speed == 0.0) {
            _playerRate = 1;
            result(nil);
        } else if (speed < 0 || speed > 2.0) {
            result([FlutterError errorWithCode:@"unsupported_speed"
                                       message:@"Speed must be >= 0.0 and <= 2.0"
                                       details:nil]);
        } else if ((speed > 1.0 && _player.currentItem.canPlayFastForward) ||
                   (speed < 1.0 && _player.currentItem.canPlaySlowForward)) {
            _playerRate = speed;
            result(nil);
        } else {
            if (speed > 1.0) {
                result([FlutterError errorWithCode:@"unsupported_fast_forward"
                                           message:@"This video cannot be played fast forward"
                                           details:nil]);
            } else {
                result([FlutterError errorWithCode:@"unsupported_slow_forward"
                                           message:@"This video cannot be played slow forward"
                                           details:nil]);
            }
        }
        
        if (_isPlaying){
            _player.rate = _playerRate;
        }
    }
    
    
    - (void)setTrackParameters:(int) width: (int) height: (int)bitrate {
        _player.currentItem.preferredPeakBitRate = bitrate;
        if (@available(iOS 11.0, *)) {
            if (width == 0 && height == 0){
                _player.currentItem.preferredMaximumResolution = CGSizeZero;
            } else {
                _player.currentItem.preferredMaximumResolution = CGSizeMake(width, height);
            }
        }
    }
    
    - (void)setPictureInPicture:(BOOL)pictureInPicture
    {
        self._pictureInPicture = pictureInPicture;
        if (@available(iOS 9.0, *)) {
            if (_pipController && self._pictureInPicture && ![_pipController isPictureInPictureActive]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_pipController startPictureInPicture];
                });
            } else if (_pipController && !self._pictureInPicture && [_pipController isPictureInPictureActive]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_pipController stopPictureInPicture];
                });
            } else {
                // Fallback on earlier versions
            } }
    }
    
#if TARGET_OS_IOS
    - (void)setRestoreUserInterfaceForPIPStopCompletionHandler:(BOOL)restore
    {
        if (_restoreUserInterfaceForPIPStopCompletionHandler != NULL) {
            _restoreUserInterfaceForPIPStopCompletionHandler(restore);
            _restoreUserInterfaceForPIPStopCompletionHandler = NULL;
        }
    }
    
    - (void)setupPipController {
        if (@available(iOS 9.0, *)) {
            [[AVAudioSession sharedInstance] setActive: YES error: nil];
            [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
            if (!_pipController && self._playerLayer && [AVPictureInPictureController isPictureInPictureSupported]) {
                _pipController = [[AVPictureInPictureController alloc] initWithPlayerLayer:self._playerLayer];
                _pipController.delegate = self;
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    - (void) enablePictureInPicture: (CGRect) frame{
        [self disablePictureInPicture];
        [self usePlayerLayer:frame];
    }
    
    - (void)usePlayerLayer: (CGRect) frame
    {
        if( _player )
        {
            // Create new controller passing reference to the AVPlayerLayer
            self._playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
            UIViewController* vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
            self._playerLayer.frame = frame;
            self._playerLayer.needsDisplayOnBoundsChange = YES;
            //  [self._playerLayer addObserver:self forKeyPath:readyForDisplayKeyPath options:NSKeyValueObservingOptionNew context:nil];
            [vc.view.layer addSublayer:self._playerLayer];
            vc.view.layer.needsDisplayOnBoundsChange = YES;
            if (@available(iOS 9.0, *)) {
                _pipController = NULL;
            }
            [self setupPipController];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self setPictureInPicture:true];
            });
        }
    }
    
    - (void)disablePictureInPicture
    {
        [self setPictureInPicture:true];
        if (__playerLayer){
            [self._playerLayer removeFromSuperlayer];
            self._playerLayer = nil;
            if (_eventSink != nil) {
                _eventSink(@{@"event" : @"pipStop"});
            }
        }
    }
#endif
    
#if TARGET_OS_IOS
    - (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController  API_AVAILABLE(ios(9.0)){
        [self disablePictureInPicture];
    }
    
    - (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController  API_AVAILABLE(ios(9.0)){
        if (_eventSink != nil) {
            _eventSink(@{@"event" : @"pipStart"});
        }
    }
    
    - (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController  API_AVAILABLE(ios(9.0)){
        
    }
    
    - (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
        
    }
    
    - (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
        
    }
    
    - (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler {
        [self setRestoreUserInterfaceForPIPStopCompletionHandler: true];
    }
    
    - (void) setAudioTrack:(NSString*) name index:(int) index{
        AVMediaSelectionGroup *audioSelectionGroup = [[[_player currentItem] asset] mediaSelectionGroupForMediaCharacteristic: AVMediaCharacteristicAudible];
        NSArray* options = audioSelectionGroup.options;
        
        
        for (int audioTrackIndex = 0; audioTrackIndex < [options count]; audioTrackIndex++) {
            AVMediaSelectionOption* option = [options objectAtIndex:audioTrackIndex];
            NSArray *metaDatas = [AVMetadataItem metadataItemsFromArray:option.commonMetadata withKey:@"title" keySpace:@"comn"];
            if (metaDatas.count > 0) {
                NSString *title = ((AVMetadataItem*)[metaDatas objectAtIndex:0]).stringValue;
                if ([name compare:title] == NSOrderedSame && audioTrackIndex == index ){
                    [[_player currentItem] selectMediaOption:option inMediaSelectionGroup: audioSelectionGroup];
                }
            }
            
        }
        
    }
    
    - (void)setMixWithOthers:(bool)mixWithOthers {
        if (mixWithOthers) {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                             withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                                   error:nil];
        } else {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        }
    }
    
    
#endif
    
    - (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
        _eventSink = nil;
        return nil;
    }
    
    - (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
    eventSink:(nonnull FlutterEventSink)events {
        _eventSink = events;
        // TODO(@recastrodiaz): remove the line below when the race condition is resolved:
        // https://github.com/flutter/flutter/issues/21483
        // This line ensures the 'initialized' event is sent when the event
        // 'AVPlayerItemStatusReadyToPlay' fires before _eventSink is set (this function
        // onListenWithArguments is called)
        [self onReadyToPlay];
        return nil;
    }
    
    /// This method allows you to dispose without touching the event channel.  This
    /// is useful for the case where the Engine is in the process of deconstruction
    /// so the channel is going to die or is already dead.
    - (void)disposeSansEventChannel {
        @try{
            [self clear];
        }
        @catch(NSException *exception) {
            NSLog(exception.debugDescription);
        }
    }
    
    - (void)dispose {
        [self pause];
        [self disposeSansEventChannel];
        
        // Cleanup Datazoom resources
        [self cleanupDatazoom];
        
        [_eventChannel setStreamHandler:nil];
        [self disablePictureInPicture];
        [self setPictureInPicture:false];
        // Clean up Datazoom context
        _disposed = true;
        
        
    }

@end

