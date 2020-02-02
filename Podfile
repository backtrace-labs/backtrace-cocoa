def shared_pods
    pod 'Backtrace-PLCrashReporter', :git => "https://github.com/backtrace-labs/plcrashreporter.git", :branch => "feature/merge-microsoft-changes"
end

def shared_test_pods
    shared_pods
    pod 'Nimble'
    pod 'Quick'
end

inhibit_all_warnings!

# Framework iOS
target 'Backtrace-iOS' do
    use_frameworks!
    shared_pods

    target 'Backtrace-iOSTests' do
        inherit! :search_paths
        shared_test_pods
    end
end

# Framework macOS
target 'Backtrace-macOS' do
    use_frameworks!
    shared_pods
    target 'Backtrace-macOSTests' do
        inherit! :search_paths
        shared_test_pods
    end
end

# Framework tvOS
target 'Backtrace-tvOS' do
    use_frameworks!
    shared_pods
    target 'Backtrace-tvOSTests' do
        inherit! :search_paths
        shared_test_pods
    end
end

def local_backtrace
    pod 'Backtrace', :path => "./Backtrace.podspec"
end

#Examples
target 'Example-iOS' do
    use_frameworks!
    local_backtrace
end

target 'Example-iOS-ObjC' do
    use_frameworks!
    local_backtrace
end

target 'Example-macOS-ObjC' do
    use_frameworks!
    local_backtrace
end

target 'Example-tvOS' do
    use_frameworks!
    local_backtrace
end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
        end
    end
  end
