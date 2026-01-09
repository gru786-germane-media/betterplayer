Pod::Spec.new do |s|
  s.name             = 'better_player'
  s.version          = '0.0.1'
  s.summary          = 'Better Player with Datazoom integration'
  s.description      = <<-DESC
Better Player plugin with Datazoom analytics and AWS MediaTailor SSAI support.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }

  # Source files - include both Obj-C AND Swift
  s.source_files = 'Classes/**/*.{h,m,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.private_header_files = 'Classes/DataZoomSwiftBridge.h'  # Swift bridge header

  # Resources (if any)
  s.resource_bundles = {
    'better_player' => ['Classes/**/*.xib', 'Classes/**/*.storyboard']
  }

  # Dependencies
  s.dependency 'Flutter'
  s.dependency 'Cache', '~> 6.0.0'
  s.dependency 'GCDWebServer'
  s.dependency 'HLSCachingReverseProxyServer'
  s.dependency 'PINCache'

  # DataZoom dependencies
  s.dependency 'DzAVPlayerAdapter'  # This brings DzBase automatically
  s.dependency 'DzMediaTailorAdapter'

  # Platform
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'  # ✅ ADD THIS

  # IMPORTANT: Keep static_framework for mixed Obj-C/Swift
  s.static_framework = true

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64 arm64',

    # Swift settings
    'SWIFT_VERSION' => '5.0',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',

    # Module settings
    'CLANG_ENABLE_MODULES' => 'YES',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',

    # IMPORTANT: No custom modulemap needed
    # Remove this line if you have it:
    # 'MODULEMAP_FILE' => '${PODS_TARGET_SRCROOT}/Classes/better_player.modulemap',

    # IMPORTANT: No bridging header in podspec (Flutter handles this)
    # 'SWIFT_OBJC_BRIDGING_HEADER' => '${PODS_TARGET_SRCROOT}/Classes/Bridging-Header.h',

    # Search paths
    'HEADER_SEARCH_PATHS' => %{
      $(inherited)
      "${PODS_ROOT}/DzAVPlayerAdapter/DzAVPlayerAdapter.xcframework/ios-arm64/Headers"
      "${PODS_ROOT}/DzMediaTailorAdapter/DzMediaTailorAdapter.xcframework/ios-arm64/Headers"
      "${PODS_ROOT}/MediaTailorSDK/MediaTailorSDK.xcframework/ios-arm64/Headers"
    }.strip,

    # Framework search paths
    'FRAMEWORK_SEARCH_PATHS' => %{
      $(inherited)
      "${PODS_ROOT}/DzBase/DzBase.xcframework"
      "${PODS_ROOT}/DzAVPlayerAdapter/DzAVPlayerAdapter.xcframework"
      "${PODS_ROOT}/DzMediaTailorAdapter/DzMediaTailorAdapter.xcframework"
      "${PODS_ROOT}/MediaTailorSDK/MediaTailorSDK.xcframework"
    }.strip,
  }

  # User target xcconfig
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
end