Pod::Spec.new do |s|
  s.name         = 'YYModel'
  s.summary      = 'High performance JSON model framework for iOS/macOS.'
  s.version      = '2.1.9'
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

  s.source       = { :git => 'https://github.com/leeeeeeeefulong/YYModel.git', :tag => s.version.to_s }

  s.requires_arc = true
  s.default_subspecs = 'ObjC', 'Swift'

  s.subspec 'ObjC' do |oc|
    oc.source_files = 'YYModel/*.{h,m}'
    oc.public_header_files = 'YYModel/*.{h}'
    oc.resource_bundles = { 'YYModel' => ['PrivacyInfo.xcprivacy'] }
  end

  s.subspec 'Swift' do |swift|
    swift.source_files = 'YYModelSwift/*.swift'
  end

  s.frameworks = 'Foundation', 'CoreFoundation'

  # The Swift product requires a Swift 5.9+ toolchain. ObjC has no Swift dependency.
  s.swift_versions = ['5.9', '6.0']

end
