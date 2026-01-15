import Foundation
import AVKit
import DzBase
import DzAVPlayerAdapter
import DzMediaTailorAdapter
import MediaTailorSDK

@objc public class DzBridge: NSObject {
    
    // MARK: - Singleton Pattern
    @objc public static let shared = DzBridge()
    
    // Private initializer to enforce singleton
    private override init() {
        super.init()
       // print("[DzBridge] Initialized")
    }
    
    // MARK: - AVPlayer Adapter Creation
    @objc(createAdapterWithPlayer:)
    public func createAdapter(player: AVPlayer) -> Any? {
       // print("[DzBridge] Creating adapter for player")
        
        // 1. Get the shared Datazoom instance
        let datazoom = DzBase.Datazoom.shared
      //  print("[DzBridge] Datazoom instance: \(datazoom)")
        
        // 2. Create base context (event space)
        let eventSpace = datazoom.createBaseContext()
        
        // 3. Create adapter with player and event space
        let adapter = datazoom.createContext(player: player, eventSpace: eventSpace)
        
      //  print("[DzBridge] ✅ Adapter created successfully")
        return adapter
    }
    
    // MARK: - MediaTailor Configuration (with optional view)
    @objc(configureMediaTailorWithAdapter:session:videoUrl:videoPlayerView:)
    public func configureMediaTailor(adapter: Any,
                                    session: Any,
                                    videoUrl: String,
                                    videoPlayerView: Any?) -> Bool {
      //  print("[DzBridge] Configuring MediaTailor for: \(videoUrl)")
        
        // 1. Type casting with validation
    //    guard let dzAdapter = adapter as? DzBase.DzAdapter else {
        guard let dzAdapter = adapter as? DzAdapter else {
     //       print("[DzBridge] ERROR: adapter is not DzBase.DzAdapter type")
            return false
        }
        
     //   guard let mtSession = session as? MediaTailorSDK.Session else {
        guard let mtSession = session as? Session else {
      //      print("[DzBridge] ERROR: session is not MediaTailorSDK.Session type")
            return false
        }
        
        // 2. Handle the videoPlayerView parameter
        let playerView: UIView
        if let providedView = videoPlayerView as? UIView {
            playerView = providedView
     //       print("[DzBridge] Using provided player view")
        } else {
            playerView = UIView() // Placeholder view
        //    print("[DzBridge] Using placeholder view")
        }
        
        // 3. Call the Swift-only method
        dzAdapter.configureAdSession(adSession: mtSession,
                                    videoUrl: videoUrl,
                                    videoPlayerView: playerView,
                                    friendlyObstructionsView: nil)
        
     //   print("[DzBridge] ✅ MediaTailor configured")
        return true
    }
    
    // MARK: - Convenience method without view (for backward compatibility)
    @objc(configureMediaTailorWithAdapter:session:videoUrl:)
    public func configureMediaTailorSimple(adapter: Any,
                                          session: Any,
                                          videoUrl: String) -> Bool {
        return configureMediaTailor(adapter: adapter,
                                  session: session,
                                  videoUrl: videoUrl,
                                  videoPlayerView: nil)
    }
    // MARK: - Remove MediaTailor Session
    @objc(removeMediaTailorSessionWithAdapter:)
    public func removeMediaTailorSession(adapter: Any) -> Bool {
     //   print("[DzBridge] Removing MediaTailor session")
        
        guard let dzAdapter = adapter as? DzBase.DzAdapter else {
        //    print("[DzBridge] ERROR: Invalid adapter type for removal")
            return false
        }
        
        // Call the Swift-only method
        dzAdapter.removeMediaTailorSession()
        
       // print("[DzBridge] ✅ MediaTailor session removed")
        return true
    }
    
    // MARK: - Utility: Get Adapter Type Info
    @objc(getAdapterTypeInfo:)
    public func getAdapterTypeInfo(adapter: Any) -> [String: Any]? {
        if adapter is DzBase.DzAdapter {
            return ["type": "DzBase.DzAdapter", "isValid": true]
        } else {
            return ["type": String(describing: type(of: adapter)), "isValid": false]
        }
    }
     
}