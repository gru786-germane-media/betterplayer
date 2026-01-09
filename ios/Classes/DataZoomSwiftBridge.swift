import Foundation
import AVKit
import DzBase
import DzAVPlayerAdapter
import DzMediaTailorAdapter
import MediaTailorSDK

@objc public class DataZoomSwiftBridge: NSObject {
    
    // MARK: - Singleton Pattern
    @objc public static let shared = DataZoomSwiftBridge()
    
    // Private initializer to enforce singleton
    private override init() {
        super.init()
        print("[DataZoomSwiftBridge] Initialized")
    }
    
    // MARK: - AVPlayer Adapter Creation
    @objc(createAdapterWithPlayer:)
    public func createAdapter(player: AVPlayer) -> Any? {
        print("[DataZoomSwiftBridge] Creating adapter for player")
        
        do {
            // 1. Get the shared Datazoom instance
            guard let datazoom = DzBase.Datazoom.shared() else {
                print("[DataZoomSwiftBridge] ERROR: Datazoom.shared is nil")
                return nil
            }
            
            // 2. Create base context (event space)
            let eventSpace = datazoom.createBaseContext()
            
            // 3. Create adapter with player and event space
            let adapter = datazoom.createContext(player: player, eventSpace: eventSpace)
            
            print("[DataZoomSwiftBridge] ✅ Adapter created successfully")
            return adapter
            
        } catch {
            print("[DataZoomSwiftBridge] ERROR creating adapter: \(error)")
            return nil
        }
    }
    
    // MARK: - MediaTailor Configuration (with optional view)
    @objc(configureMediaTailorWithAdapter:session:videoUrl:videoPlayerView:)
    public func configureMediaTailor(adapter: Any,
                                    session: Any,
                                    videoUrl: String,
                                    videoPlayerView: Any?) -> Bool {
        print("[DataZoomSwiftBridge] Configuring MediaTailor for: \(videoUrl)")
        
        do {
            // 1. Type casting with validation
            guard let dzAdapter = adapter as? DzBase.DzAdapter else {
                print("[DataZoomSwiftBridge] ERROR: adapter is not DzBase.DzAdapter type")
                return false
            }
            
            guard let mtSession = session as? MediaTailorSDK.Session else {
                print("[DataZoomSwiftBridge] ERROR: session is not MediaTailorSDK.Session type")
                return false
            }
            
            // 2. Handle the videoPlayerView parameter
            let playerView: UIView
            if let providedView = videoPlayerView as? UIView {
                playerView = providedView
                print("[DataZoomSwiftBridge] Using provided player view")
            } else {
                playerView = UIView() // Placeholder view
                print("[DataZoomSwiftBridge] Using placeholder view")
            }
            
            // 3. Call the Swift-only method
            dzAdapter.configureAdSession(adSession: mtSession,
                                        videoUrl: videoUrl,
                                        videoPlayerView: playerView,
                                        friendlyObstructionsView: nil)
            
            print("[DataZoomSwiftBridge] ✅ MediaTailor configured")
            return true
            
        } catch {
            print("[DataZoomSwiftBridge] ERROR configuring MediaTailor: \(error)")
            return false
        }
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
        print("[DataZoomSwiftBridge] Removing MediaTailor session")
        
        do {
            guard let dzAdapter = adapter as? DzBase.DzAdapter else {
                print("[DataZoomSwiftBridge] ERROR: Invalid adapter type for removal")
                return false
            }
            
            // Call the Swift-only method
            dzAdapter.removeMediaTailorSession()
            
            print("[DataZoomSwiftBridge] ✅ MediaTailor session removed")
            return true
            
        } catch {
            print("[DataZoomSwiftBridge] ERROR removing session: \(error)")
            return false
        }
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
    
    // MARK: - Utility: Check if Datazoom is initialized
    @objc public var isDatazoomInitialized: Bool {
        return DzBase.Datazoom.shared() != nil
    }
}