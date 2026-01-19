//
//  MediaTailorExampleHelper.swift
//  AVPlayer-DemoApp
//
//  Created by Archit Dhupar on 2025-02-09.
//

import Foundation
import MediaTailorSDK
  
class MediaTailorHelper {
  
  private var session: Session? = nil
  
  public func createMediaTailor(url: String, onSession: @escaping(Session?, SessionError?) -> Void) {
    MediaTailor.shared.setLogLevel(logLevel: LogLevel.off)
    let features = SessionFeatures.Builder()
      .reportingMode(value: SessionReportingMode.server)
      .overlayAvails(value: true)
      .build()
    
    let config = SessionConfiguration.Builder()
      .sessionInitUrl(value: url)
      .sessionFeatures(value: features)
      .build()
    
    MediaTailor.shared.createSession(config: config, callback: { [weak self] session, error in
      self?.session = session
      Task {
        await MainActor.run {
          onSession(session, error)
        }
      }
    })
  }
}
