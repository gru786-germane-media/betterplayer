// DataZoomBridge.swift
import Foundation
import AVKit
//import MediaTailorSDK
import DzBase
import DzAVPlayerAdapter
import DzMediaTailorAdapter

@objc public class DataZoomBridge: NSObject {
    
    // MARK: - Singleton
    @objc public static let shared = DataZoomBridge()
    
    // MARK: - 1. Create DataZoom Adapter for AVPlayer
    @objc public func createAdapter(player: AVPlayer) -> Any {
        // Get the shared Datazoom instance
        let datazoom = DzBase.Datazoom.shared()!
        
        // Call Swift-only method: createContext with just player
        // Swift will use default eventSpace automatically
        let adapter = datazoom.createContext(player: player)
        
        print("[DataZoomBridge] ✅ Adapter created for player")
        return adapter
    }
    
    // MARK: - 2. Configure MediaTailor Session
    @objc public func configureMediaTailor(adapter: Any,
                                         session: Any,
                                         videoUrl: String,
                                         videoPlayerView: Any?) -> Bool {
        // Convert generic types to specific Swift types
        let dzAdapter = adapter as! DzBase.DzAdapter
        let mtSession = session as! MediaTailorSDK.Session
        let playerView = videoPlayerView as? UIView ?? UIView()
        
        // Call Swift-only method from DzMediaTailorAdapter
        dzAdapter.configureAdSession(adSession: mtSession,
                                    videoUrl: videoUrl,
                                    videoPlayerView: playerView,
                                    friendlyObstructionsView: nil)
        
        print("[DataZoomBridge] ✅ MediaTailor configured for: \(videoUrl)")
        return true
    }
    
    // MARK: - 3. Simplified MediaTailor Configuration (no view)
    @objc public func configureMediaTailor(adapter: Any,
                                         session: Any,
                                         videoUrl: String) -> Bool {
        return configureMediaTailor(adapter: adapter,
                                  session: session,
                                  videoUrl: videoUrl,
                                  videoPlayerView: nil)
    }
    
    // MARK: - 4. Set Player View on Adapter
    @objc public func setPlayerView(adapter: Any, view: Any) -> Bool {
        let dzAdapter = adapter as! DzBase.DzAdapter
        let uiView = view as! UIView
        
        dzAdapter.setPlayerView(playerView: uiView)
        print("[DataZoomBridge] ✅ Player view set")
        return true
    }
    
    // MARK: - 5. Track Ad Events
    @objc public func trackAdSkip(adapter: Any) -> Bool {
        let dzAdapter = adapter as! DzBase.DzAdapter
        dzAdapter.trackAdSkip()
        print("[DataZoomBridge] ✅ Ad skip tracked")
        return true
    }
    
    @objc public func trackAdClick(adapter: Any) -> Bool {
        let dzAdapter = adapter as! DzBase.DzAdapter
        dzAdapter.trackAdClick()
        print("[DataZoomBridge] ✅ Ad click tracked")
        return true
    }
    
    // MARK: - 6. Remove MediaTailor Session
    @objc public func removeMediaTailorSession(adapter: Any) -> Bool {
        let dzAdapter = adapter as! DzBase.DzAdapter
        dzAdapter.removeMediaTailorSession()
        print("[DataZoomBridge] ✅ MediaTailor session removed")
        return true
    }
    
    // MARK: - 7. Get OMSDK Partner Info
    @objc public func getOMIDPartnerInfo(adapter: Any) -> [String: String] {
        let dzAdapter = adapter as! DzBase.DzAdapter
        let partnerInfo = dzAdapter.omidPartnerInfo
        
        return [
            "name": partnerInfo.name,
            "version": partnerInfo.version
        ]
    }
}
