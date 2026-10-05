Pod::Spec.new do |s|
  s.name         = 'YYModel2'
  s.summary      = 'High performance JSON model framework for iOS/macOS. Maintained fork of ibireme/YYModel.'
  s.version      = '2.3.2'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'ibireme' => 'ibireme@gmail.com', 'leeeeeeeefulong' => 'leeeeeeeefulong@github.com' }
  s.homepage     = 'https://github.com/leeeeeeeefulong/YYModel'

  # Supported distribution floors: iOS 11.0 / macOS 10.13.
  # Core cache locking uses os_unfair_lock (iOS 10 / macOS 10.12).
  # Complete archivedData/unarchivedObject convenience APIs are caller/demo APIs,
  # not an unavoidable Core dependency. See docs/OBJC-MIGRATION.md.

  s.ios.deployment_target = '11.0'
  s.osx.deployment_target = '10.13'

  s.source       = { :git => 'https://github.com/leeeeeeeefulong/YYModel.git', :tag => s.version.to_s }

  s.requires_arc = true
  s.default_subspecs = 'ObjC', 'Swift'

  s.subspec 'ObjC' do |oc|
    oc.source_files = 'YYModel/*.{h,m}'
    oc.public_header_files = 'YYModel/*.{h}'
    oc.resource_bundles = { 'YYModel2' => ['PrivacyInfo.xcprivacy'] }
  end

  s.subspec 'Swift' do |swift|
    swift.source_files = 'YYModelSwift/*.swift'
  end

  s.frameworks = 'Foundation', 'CoreFoundation'

  # swift_versions declares CocoaPods Swift LANGUAGE MODES (valid compiler values:
  # 5.0 and 6.0 — e.g. "5.9" is not a language mode and breaks client selection).
  # The analyzer reads this root-level attribute; both modes compile the full source.
  # The source additionally requires a Swift 5.9+ toolchain (no language-mode implication).
  # Pure-ObjC consumers are unaffected: the ObjC subspec contains no Swift sources.
  s.swift_versions = ['5.0', '6.0']

end
