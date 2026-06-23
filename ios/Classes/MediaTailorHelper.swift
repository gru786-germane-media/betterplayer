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

  // MediaTailor ad-param macros the Dart side may send via the data source `headers`
  // map. These are overlaid onto the base playerParams so the SSAI ad server receives
  // the app's targeting signals. Add new macro keys here when introduced on the Dart side.
  static let adParamHeaderKeys: [String] = [
    "msid",
    "idtype",
    "AV_PUBLISHERID",
    "AV_CHANNELID",
    "AV_APPSTOREURL",
    "AV_RTB_DEVICE_TYPE",
    "AV_WIDTH",
    "AV_HEIGHT",
    "AV_LATITUDE",
    "AV_LONGITUDE",
    "AV_APP_DOMAIN",
    "AV_SCHAIN",
    "AV_CONTENT_CONTEXT",
    "AV_CONTENT_KEYWORDS",
    "AV_CONTENT_LANGUAGE",
    "AV_CONTENT_TITLE",
    "AV_CONTENT_SERIES",
    "AV_CONTENT_NETWORK_NAME",
    "AV_CONTENT_DIST_NAME",
    "AV_CONTENT_CAT",
    "AV_CONTENT_ID",
    "AV_CONTENT_URL",
    "AV_CONTENT_CHANNEL",
    "AV_CONTENT_GENRE",
    "AV_CONTENT_RATING",
    "AV_CONTENT_PRODQ",
    "ssai_e",
    "ssai_p",
    "livestream",
    "coppa"
  ]

  public func createMediaTailor(url: String, headers: [String: String]?, onSession: @escaping(Session?, SessionError?) -> Void) {
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
      var playerParams: [String: String] = [
        "playerType": "BetterPlayer",
          "playerVersion": "1.0",
          "idtype": "idfa",
          "an": "Swift%20TV",
          "msid": bundleId,
          "rdid": rdid
      ]

      // Overlay every MediaTailor ad-param macro the Dart side sent via headers.
      // Headers take precedence so per-stream targeting (msid override, player size,
      // IP geo, content context, schain, etc.) reaches the SSAI ad server.
      if let headers = headers {
        for key in MediaTailorHelper.adParamHeaderKeys {
          if let value = headers[key], !value.isEmpty {
            playerParams[key] = value
          }
        }
      }
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
