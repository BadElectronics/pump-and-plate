Pod::Spec.new do |s|
  s.name             = 'pump_native'
  s.version          = '1.0.0'
  s.summary          = 'Pump and Plate iPhone features.'
  s.description      = 'Device features, the backup folder and Apple on-device AI for Pump and Plate.'
  s.homepage         = 'https://github.com/'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'Pump and Plate' => 'support@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.9'
  # Apple's on-device model only exists on iOS 26 and later; older iPhones
  # must still start the app.
  s.weak_frameworks  = 'FoundationModels'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
