Pod::Spec.new do |s|
  s.name         = 'YYModel'
  s.summary      = 'High performance JSON model framework for iOS/macOS.'
  s.version      = '1.0.5'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'ibireme' => 'ibireme@gmail.com', 'leeeeeeeefulong' => 'leeeeeeeefulong@github.com' }
  s.homepage     = 'https://github.com/leeeeeeeefulong/YYModel'

  # Minimum deployment target: iOS 11.0 / macOS 10.13
  #
  # Constrained by NSSecureCoding archiving API (iOS 11.0+).
  # All other APIs are available from iOS 6.0 or earlier.
  #
  # API availability (verified against Apple Developer Documentation):
  #   os_unfair_lock:              iOS 10.0+ / macOS 10.12+
  #   archivedDataWithRootObject:  iOS 11.0+ / macOS 10.13+  ← bottleneck
  #   unarchivedObjectOfClass:     iOS 11.0+ / macOS 10.13+  ← bottleneck
  #   NSSecureCoding:              iOS 6.0+  / macOS 10.8+
  #   decodeObjectOfClass:forKey:  iOS 6.0+  / macOS 10.8+
  #   NSJSONSerialization:         iOS 5.0+  / macOS 10.7+
  #   dispatch_once:               iOS 4.0+  / macOS 10.6+
  #   NSGetSizeAndAlignment:       iOS 2.0+  / macOS 10.0+

  s.ios.deployment_target = '11.0'
  s.osx.deployment_target = '10.13'
  s.watchos.deployment_target = '4.0'
  s.tvos.deployment_target = '11.0'

  s.source       = { :git => 'https://github.com/leeeeeeeefulong/YYModel.git', :tag => s.version.to_s }

  s.requires_arc = true
  s.source_files = 'YYModel/*.{h,m}'
  s.public_header_files = 'YYModel/*.{h}'

  s.frameworks = 'Foundation', 'CoreFoundation'

  # Privacy manifest for iOS 17+ (Required Reason API)
  s.resource_bundles = {
    'YYModel' => ['PrivacyInfo.xcprivacy']
  }

  # Swift bridge (optional, for Codable coexistence)
  s.swift_versions = ['5.0', '5.5', '5.9', '6.0']

end
