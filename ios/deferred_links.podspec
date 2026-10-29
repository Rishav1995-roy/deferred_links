Pod::Spec.new do |s|
  s.name             = 'deferred_links'
  s.version          = '0.0.1'
  s.summary          = 'Self-hostable app links, short links and deferred deep links.'
  s.description      = <<-DESC
Receives Universal Links and recovers deferred deep links after install, with a self-hosted server.
                       DESC
  s.homepage         = 'https://github.com/Rishav1995-roy/deferred_links'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Rishav Deb Roy' => 'debroyrishab@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'deferred_links/Sources/deferred_links/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'deferred_links_privacy' => ['deferred_links/Sources/deferred_links/PrivacyInfo.xcprivacy']}
end
