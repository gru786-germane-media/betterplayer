// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <GLKit/GLKit.h>
#import "BetterPlayerTimeUtils.h"
#import "BetterPlayerView.h"
#import "BetterPlayerEzDrmAssetsLoaderDelegate.h"

// Add Datazoom imports
#import <DzBase/DzBase.h>
#import <DzMediaTailorAdapter/DzMediaTailorAdapter.h>
#import <MediaTailorSDK/MediaTailorSDK.h>

NS_ASSUME_NONNULL_BEGIN

@class CacheManager;

// Forward declarations for Swift classes (they will be available via Swift bridge)
@class DzBridge;  // Our Swift bridge class


@interface BetterPlayer : NSObject <FlutterPlatformView, FlutterStreamHandler, AVPictureInPictureControllerDelegate>
@property(readonly, nonatomic) AVPlayer* player;
@property(readonly, nonatomic) BetterPlayerEzDrmAssetsLoaderDelegate* loaderDelegate;
@property(nonatomic) FlutterEventChannel* eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(nonatomic) CGAffineTransform preferredTransform;
@property(nonatomic, readonly) bool disposed;
@property(nonatomic, readonly) bool isPlaying;
@property(nonatomic) bool isLooping;
@property(nonatomic, readonly) bool isInitialized;
@property(nonatomic, readonly) NSString* key;
@property(nonatomic, readonly) int failedCount;
@property(nonatomic) AVPlayerLayer* _playerLayer;
@property(nonatomic) bool _pictureInPicture;
@property(nonatomic) bool _observersAdded;
@property(nonatomic) int stalledCount;
@property(nonatomic) bool isStalledCheckStarted;
@property(nonatomic) float playerRate;
@property(nonatomic) int overriddenDuration;
@property(nonatomic) AVPlayerTimeControlStatus lastAvPlayerTimeControlStatus;

// ============================================
// NEW PROPERTIES FOR DATAZOOM/SSAI INTEGRATION
// ============================================
@property(nonatomic, strong) DzBaseDzAdapter* datazoomAdapter; // ✅ CORRECT TYPE

// ============================================
// EXISTING PLAYER METHODS
// ============================================
- (void)play;
- (void)pause;
- (void)setIsLooping:(bool)isLooping;
- (void)updatePlayingState;
- (int64_t) duration;
- (int64_t) position;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)setMixWithOthers:(bool)mixWithOthers;
- (void)seekTo:(int)location;
- (void)setDataSourceAsset:(NSString*)asset withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int) overriddenDuration;

// ✅ SINGLE CORRECT DECLARATION (REMOVED DUPLICATE)
- (void)setDataSourceURL:(NSURL*)url 
                 withKey:(NSString*)key          
          withCertificateUrl:(NSString*)certificateUrl 
             withLicenseUrl:(NSString*)licenseUrl 
                withHeaders:(NSDictionary*)headers 
                  withCache:(BOOL)useCache 
                  cacheKey:(NSString*)cacheKey 
            cacheManager:(CacheManager*)cacheManager 
         overriddenDuration:(int)overriddenDuration
            videoExtension:(NSString*)videoExtension 
          shouldEnableSSAI:(BOOL)shouldEnableSSAI;

- (void)setVolume:(double)volume;
- (void)setSpeed:(double)speed result:(FlutterResult)result;
- (void) setAudioTrack:(NSString*) name index:(int) index;
- (void)setTrackParameters:(int) width: (int) height: (int)bitrate;
- (void) enablePictureInPicture: (CGRect) frame;
- (void)setPictureInPicture:(BOOL)pictureInPicture;
- (void)disablePictureInPicture;
- (int64_t)absolutePosition;
- (int64_t) FLTCMTimeToMillis:(CMTime) time;

- (void)clear;
- (void)disposeSansEventChannel;
- (void)dispose;

// ============================================
// PLAYER SETUP FUNCTIONS (MISSING IN YOUR .h)
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
              overriddenDuration:(int)overriddenDuration;

- (void)setupPlayerWithItem:(AVPlayerItem*)item key:(NSString*)key;

// ============================================
// DATAZOOM INTEGRATION FUNCTIONS
// ============================================
- (void)setupDatazoomWithPlayer:(AVPlayer *)player; // ✅ REPLACES attachPlayerToDatazoom
- (void)linkMediaTailorSessionToDatazoom:(MTSDKSession *)session 
                            originalURL:(NSString *)originalURLString;
- (void)setSSAIMetadataWithOriginalURL:(NSString *)originalURL 
                          playbackURL:(NSString *)playbackURL 
                            sessionId:(NSString *)sessionId;

// ============================================
// MEDIATAILOR SDK FUNCTIONS
// ============================================
- (void)initializeMediaTailorSDK;
- (MTSDKPalNonceRequestParams *)createPalNonceRequestParamsWithContentURL:(NSString *)contentURL;
- (MTSDKSessionConfiguration *)createMediaTailorSessionConfigWithContentURL:(NSString *)contentURL 
                                                          palNonceParams:(MTSDKPalNonceRequestParams *)palNonceParams;
- (void)attemptSSAISetupWithURL:(NSURL *)url 
                         withKey:(NSString*)key
                          headers:(NSDictionary*)headers 
                      cacheKey:(NSString*)cacheKey 
                 cacheManager:(CacheManager*)cacheManager 
                    useCache:(BOOL)useCache 
              videoExtension:(NSString*)videoExtension 
             overriddenDuration:(int)overriddenDuration;

// ============================================
// SESSION HANDLERS
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
                                    overriddenDuration:(int)overriddenDuration;

- (void)handleMediaTailorSessionFailureWithOriginalURL:(NSURL *)originalURL 
                                                  withKey:(NSString*)key 
                                                  error:(MTSDKSessionError *)error 
                                               headers:(NSDictionary *)headers 
                                             cacheKey:(NSString *)cacheKey 
                                        cacheManager:(CacheManager *)cacheManager 
                                           useCache:(BOOL)useCache 
                                     videoExtension:(NSString *)videoExtension 
                                    overriddenDuration:(int)overriddenDuration;

// ============================================
// EVENT FUNCTIONS (KEEP THESE)
// ============================================
- (void)sendSSAISuccessEvent:(NSString *)url 
                    sessionId:(NSString *)sessionId 
                   playbackUrl:(NSString *)playbackUrl;

- (void)sendSSAIFailureEvent:(NSString *)url 
                    sessionId:(NSString *)sessionId 
                        error:(NSString *)error;

- (void)fallbackToRegularPlayerWithURL:(NSURL *)url 
                               withKey:(NSString*)key
                          headers:(NSDictionary *)headers 
                             cacheKey:(NSString *)cacheKey 
                        cacheManager:(CacheManager *)cacheManager 
                           useCache:(BOOL)useCache 
                     videoExtension:(NSString *)videoExtension 
                    overriddenDuration:(int)overriddenDuration;

@end

NS_ASSUME_NONNULL_END