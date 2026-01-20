//
//  MediaTailorExampleHelper.swift
//  AVPlayer-DemoApp
//
//  Created by Archit Dhupar on 2025-02-09.
//

import AdSupport
import AppTrackingTransparency
import Foundation
import MediaTailorSDK
import Foundation

  
class MediaTailorHelper {
  
  private var session: Session? = nil
  
  public func createMediaTailor(url: String, onSession: @escaping(Session?, SessionError?) -> Void) {
      NSLog("[BetterPlayer] START: createMediaTailor 1...")

      let palNonce = PalNonceRequestParams.Builder()
            .descriptionUrl(value: "https://playswift.tv")
            .omidPartnerName(value: "amazon2")
            .omidPartnerVersion(value: "1.0.0")
            .playerType(value:"BetterPlayer")
            .playerVersion(value: "1.0")
            .adWillAutoPlay(value: true)
            .adWillPlayMuted(value: false)
            .continuousPlayback(value: true)
           .iconsSupported(value: true)
            .videoHeight(value: 1080)
        .videoWidth(value: 1920)
            .build()


    NSLog("[BetterPlayer] START: createMediaTailor 2...")

    let features = SessionFeatures.Builder()
      .reportingMode(value: SessionReportingMode.server)
      .overlayAvails(value: true)
      .build()
    NSLog("[BetterPlayer] START: createMediaTailor 3...")
    
      let bundleId = Bundle.main.bundleIdentifier ?? "com.thegermanemedia.swiftTvFe"
    NSLog("[BetterPlayer] START: createMediaTailor 4...")

      let rdid =  getRDID()
         NSLog("[BetterPlayer] START: createMediaTailor 5...")
 
      // Create player parameters dictionary (not a closure!)
      let playerParams: [String: String] = [
        "playerType": "BetterPlayer",
          "playerVersion": "1.0",
          "idtype": "idfa",
          "an": "Swift%20TV",
          "msid": bundleId,
          "rdid": rdid
      ]
       NSLog("[BetterPlayer] START: createMediaTailor 6...")
  let config = SessionConfiguration.Builder()
       .sessionInitUrl(value: url)
       .sessionFeatures(value: features)
       //.palNonceRequestParams(value: palNonce)
       .playerParams(value: playerParams)
       .build()
    NSLog("[BetterPlayer] START: createMediaTailor 705...")

    MediaTailor.shared.createSession(config: config, callback: { [weak self] session, error in
      self?.session = session
      Task {
        await MainActor.run {
              NSLog("[BetterPlayer] START: createMediaTailor 8...")

          onSession(session, error)
        }
      }
    })
        NSLog("[BetterPlayer] START: createMediaTailor 9...")

  }
  
    
    // Helper method to get RDID (IDFA)
    func getRDID() -> String {
        // NSLog("[BetterPlayer] START: Getting RDID...")
        
        do {
            let isTrackingEnabled = ASIdentifierManager.shared().isAdvertisingTrackingEnabled
            // NSLog("[BetterPlayer] Advertising tracking enabled: \(isTrackingEnabled ? "YES" : "NO")")
            
            if isTrackingEnabled {
                let idfaUUID = ASIdentifierManager.shared().advertisingIdentifier
                let idfaString = idfaUUID.uuidString
                // NSLog("[BetterPlayer] SUCCESS: Got RDID (IDFA): \(idfaString)")
                return idfaString
            } else {
                // Generate random UUID when tracking is disabled
                let randomUUID = UUID()
                let randomUUIDString = randomUUID.uuidString
                // NSLog("[BetterPlayer] Tracking disabled, generated random UUID: \(randomUUIDString)")
                return randomUUIDString
            }
        } catch {
            // NSLog("[BetterPlayer] EXCEPTION in getRDID: \(error.localizedDescription)")
            let fallbackUUID = UUID()
            // NSLog("[BetterPlayer] Using fallback UUID: \(fallbackUUID.uuidString)")
            return fallbackUUID.uuidString
        }
    }
}
