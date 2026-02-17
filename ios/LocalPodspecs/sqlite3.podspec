# Overrides the upstream sqlite3 pod to use iOS's built-in system SQLite library.
# This avoids downloading source from www.sqlite.org, which is blocked in
# restricted CI environments like Xcode Cloud.
#
# iOS 15+ ships with SQLite 3.36+ which includes FTS5, R-Tree, and JSON1.

Pod::Spec.new do |s|
  s.name         = 'sqlite3'
  s.version      = '3.51.1'
  s.summary      = 'System SQLite wrapper for CI compatibility'
  s.homepage     = 'https://sqlite.org'
  s.license      = { :type => 'Public Domain' }
  s.author       = 'SQLite Authors'
  s.source       = { :git => 'https://github.com/nicklockwood/sqlite3.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '10.14'

  s.libraries = 'sqlite3'

  # Empty source file so CocoaPods has something to compile.
  # The actual SQLite comes from the system library linked above.
  s.source_files = 'dummy.c'
  s.preserve_paths = 'dummy.c'
  s.prepare_command = 'touch dummy.c'

  s.subspec 'common' do |ss|
    ss.libraries = 'sqlite3'
    ss.source_files = 'dummy.c'
  end

  s.subspec 'fts5' do |ss|
    ss.dependency 'sqlite3/common'
  end

  s.subspec 'perf-threadsafe' do |ss|
    ss.dependency 'sqlite3/common'
  end

  s.subspec 'rtree' do |ss|
    ss.dependency 'sqlite3/common'
  end

  s.subspec 'dbstatvtab' do |ss|
    ss.dependency 'sqlite3/common'
  end

  s.subspec 'math' do |ss|
    ss.dependency 'sqlite3/common'
  end

  s.subspec 'session' do |ss|
    ss.dependency 'sqlite3/common'
  end
end
