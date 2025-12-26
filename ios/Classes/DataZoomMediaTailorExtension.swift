// DataZoomExtensions.swift
import Foundation
import DzBase
import DzAVPlayerAdapter
import DzMediaTailorAdapter
import MediaTailorSDK
import AVKit

// MARK: - DzBaseDatazoom extensions
@objc extension DzBaseDatazoom {
    // Expose the Swift method to Objective-C
    @objc(createContextWithPlayer:eventSpace:)
    func createContextObjC(player: AVPlayer, eventSpace: DzBaseBaseContext?) -> DzBaseDzAdapter {
        let space = eventSpace ?? self.createBaseContext()
        return self.createContext(player: player, eventSpace: space)
    }
    
    // Convenience method
    @objc(createContextWithPlayer:)
    func createContextObjC(player: AVPlayer) -> DzBaseDzAdapter {
        return self.createContext(player: player)
    }
}

// MARK: - DzBaseDzAdapter extensions
@objc extension DzBaseDzAdapter {
    // MediaTailor integration
    @objc(configureMediaTailorSession:videoUrl:videoPlayerView:)
    func configureMediaTailorSession(_ session: MTSDKSession,
                                    videoUrl: String,
                                    videoPlayerView: UIView?) {
        self.configureAdSession(adSession: session,
                               videoUrl: videoUrl,
                               videoPlayerView: videoPlayerView ?? UIView(),
                               friendlyObstructionsView: nil)
    }
    
    @objc(configureMediaTailorSession:videoUrl:)
    func configureMediaTailorSession(_ session: MTSDKSession,
                                    videoUrl: String) {
        self.configureMediaTailorSession(session,
                                        videoUrl: videoUrl,
                                        videoPlayerView: nil)
    }
    
    // Player view setup
    @objc(setPlayerView:)
    func setPlayerViewObjC(_ view: UIView) {
        self.setPlayerView(playerView: view)
    }
}