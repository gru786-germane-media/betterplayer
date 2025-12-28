Pod::Spec.new do |s|
  s.name             = 'better_player'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  
  s.source_files = 'Classes/**/*.{h,m,swift}'
  s.public_header_files = 'Classes/**/*.h'
  
  # Add bridging header
  s.prefix_header_file = 'Classes/Bridging-Header.h'
  
  # Preserve paths for module map
  s.preserve_paths = 'Classes/**/*.modulemap'
  
  s.dependency 'Flutter'
  s.dependency 'Cache', '~> 6.0.0'
  s.dependency 'GCDWebServer'
  s.dependency 'HLSCachingReverseProxyServer'
  s.dependency 'PINCache'
  
  # DataZoom dependencies
  #s.dependency 'DzBase'
  s.dependency 'DzAVPlayerAdapter'
  s.dependency 'DzMediaTailorAdapter'
  
  s.static_framework = true
  s.platform = :ios, '11.0'
  s.swift_version = '5.0'
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64 arm64',
    
    # Use custom modulemap
    'MODULEMAP_FILE' => '${PODS_TARGET_SRCROOT}/Classes/better_player.modulemap',
    
    # Module settings
    'CLANG_ENABLE_MODULES' => 'YES',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',
    
    # Framework search paths
    'FRAMEWORK_SEARCH_PATHS' => %{
      $(inherited)
      "${PODS_ROOT}/DzBase/DzBase.xcframework/ios-arm64"
      "${PODS_ROOT}/DzAVPlayerAdapter/DzAVPlayerAdapter.xcframework/ios-arm64"
      "${PODS_ROOT}/DzMediaTailorAdapter/DzMediaTailorAdapter.xcframework/ios-arm64"
    }.strip,
    
    # Linker flags
    'OTHER_LDFLAGS' => %{
      $(inherited)
      -framework "DzBase"
      -framework "DzAVPlayerAdapter"
      -framework "DzMediaTailorAdapter"
    }.strip,
  }
end