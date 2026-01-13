//
//  File.swift
//  ObjCDependency
//
//  Created by Archit Dhupar on 2025-05-06.
//

import Foundation
import AVKit
import DzAVPlayerAdapter
import DzBase
import DzMediaTailorAdapter
import MediaTailorSDK

@objc public class DatazoomWrapper: NSObject {
  
  private var adSession: Session?
  private let mediaTailorAdapter = MediaTailorHelper()
  private var dzAdapter: DzAdapter? = nil

  @objc
  public func initializeDZ(configId: String) {
    let configBuilder = Config.Builder(configurationId: configId)
    Datazoom.shared.doInit(config: configBuilder.build())
  }
  
    @objc(createMediaTailorSessionWithUrl:onSuccess:onError:)
  public func createMediaTailorSession(
    url: String,
    onSuccess: @escaping(String, Session) -> Void,
    onError: @escaping(String) -> Void
  ) {
    mediaTailorAdapter.createMediaTailor(url: url) { [weak self] session, error in
      guard let self = self else { return }
      
      Task {
        await MainActor.run {
          if let error = error {
            // Handle error case
            onError(error.description)
          } else if let session = session, let videoUrl = session.playbackUrl {
            // Handle success case - pass both URL and session
            self.adSession = session
            onSuccess(videoUrl, session)
          } else {
            // Handle case where session exists but no playback URL
            onError("Session created but no playback URL available")
          }
        }
      }
    }
  }
  
  @objc
 public  func setupDataZoomAdapter(player: AVPlayer, videoUrl: String, videoPlayerView: UIView) {
    guard let adSession else { return }
    dzAdapter = Datazoom.shared.createContext(player: player)
    dzAdapter?.configureAdSession(adSession: adSession, videoUrl: videoUrl, videoPlayerView: videoPlayerView)
  }
  
  // MARK: - Event Listener
  @objc
  func setUpMTEventListener(onUpdateEvent: @escaping(String) -> Void) {
    guard let adSession = adSession else { return }
    adSession.addUiEventListener(event: SessionUiEvent.adStart) { event, eventData in
     // Here ads start event
      onUpdateEvent("Ad started")
    }
    
    adSession.addUiEventListener(event: SessionUiEvent.adEnd) { event, eventData in
      // Here you get ad end event
      onUpdateEvent("Ad ended")
    }
    
    adSession.addUiEventListener(event: SessionUiEvent.adCanSkip) { event, eventData in
    // Here you get the event when ad can be skipped
      onUpdateEvent("Ad can be skipped")
    }
  }
}
