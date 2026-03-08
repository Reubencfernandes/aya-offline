Pod::Spec.new do |s|
  s.name         = 'aya_engine'
  s.version      = '1.0.0'
  s.summary      = 'Aya offline inference engine (C)'
  s.homepage     = 'https://github.com/Complexity-ML/aya-offline'
  s.license      = { :type => 'MIT' }
  s.author       = 'INL'

  s.source       = { :path => '.' }
  s.source_files = 'src/gguf.c', 'src/model.c', 'src/aya_api.c', 'src/**/*.h'

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_CFLAGS' => '-O2 -DAYA_BUILD_DLL=0',
  }

  # Ensure symbols are visible for DynamicLibrary.process()
  s.compiler_flags = '-fvisibility=default'
end
