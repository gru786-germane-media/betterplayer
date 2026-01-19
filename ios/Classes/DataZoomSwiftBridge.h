// DataZoomSwiftBridge.h
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Objective-C interface to the DataZoom Swift bridge.
 * This allows Objective-C code (BetterPlayer) to call Swift-only Datazoom methods.
 */
@interface DataZoomSwiftBridge : NSObject

#pragma mark - Singleton
/// Shared instance of the DataZoom bridge
+ (instancetype)shared;

#pragma mark - Datazoom Initialization Check
/// Returns YES if Datazoom SDK is properly initialized
@property (nonatomic, readonly) BOOL isDatazoomInitialized;

#pragma mark - AVPlayer Adapter Creation
/**
 * Creates a Datazoom adapter for an AVPlayer instance.
 *
 * @param player The AVPlayer instance to track
 * @return Datazoom adapter object, or nil if creation fails
 */
- (nullable id)createAdapterWithPlayer:(AVPlayer *)player;

#pragma mark - MediaTailor Configuration
/**
 * Configures MediaTailor session with a Datazoom adapter.
 * Version with optional video player view.
 *
 * @param adapter Datazoom adapter from createAdapterWithPlayer:
 * @param session MediaTailor session object
 * @param videoUrl Original video URL (for tracking)
 * @param videoPlayerView Optional UIView for video playback (can be nil)
 * @return YES if configuration succeeded, NO otherwise
 */
- (BOOL)configureMediaTailorWithAdapter:(id)adapter
        session:(id)session
        videoUrl:(NSString *)videoUrl
        videoPlayerView:(nullable id)videoPlayerView;

/**
 * Configures MediaTailor session with a Datazoom adapter.
 * Simplified version without video player view (uses placeholder).
 *
 * @param adapter Datazoom adapter from createAdapterWithPlayer:
 * @param session MediaTailor session object
 * @param videoUrl Original video URL (for tracking)
 * @return YES if configuration succeeded, NO otherwise
 */
- (BOOL)configureMediaTailorWithAdapter:(id)adapter
        session:(id)session
        videoUrl:(NSString *)videoUrl;

#pragma mark - Session Management
/**
 * Removes MediaTailor session from a Datazoom adapter.
 * Call this when switching videos or disposing player.
 *
 * @param adapter Datazoom adapter to clean up
 * @return YES if removal succeeded, NO otherwise
 */
- (BOOL)removeMediaTailorSessionWithAdapter:(id)adapter;

#pragma mark - Debug Utilities
/**
 * Gets type information about an adapter object.
 * Useful for debugging type casting issues.
 *
 * @param adapter Object to check
 * @return Dictionary with type information, or nil if error
 */
- (nullable NSDictionary<NSString *, id> *)getAdapterTypeInfo:(id)adapter;

@end

        NS_ASSUME_NONNULL_END