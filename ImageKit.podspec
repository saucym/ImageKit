# MARK: converted automatically by spec.py. @hgy

Pod::Spec.new do |s|
	s.name = 'ImageKit'
	s.version = '1.2.1'
	s.description = 'ImageKit'
	s.license = 'MIT'
	s.summary = 'ImageKit'
	s.homepage = 'https://saucym.github.io/'
	s.authors = { 'saucym' => '413132340@qq.com' }
	s.source = { :git => 'git@github.com:saucym/ImageKit.git', :tag => s.version.to_s }
	s.ios.deployment_target = '15.0'
    s.osx.deployment_target = '12.0'

	s.source_files = 'Sources/**/*.{h,m,swift}'
    s.swift_versions = ['5.0']
end
