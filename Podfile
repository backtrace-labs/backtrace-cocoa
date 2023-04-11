source 'https://cdn.cocoapods.org/'

# Library

# Definitions
def shared_pods
    # Define shared CocoaPods here
end

def shared_test_pods
    shared_pods
    # Define shared Testing CocoaPods here

end

def shared_ios_mac_pods
    shared_pods
end

def shared_test_ios_mac_pods
    shared_test_pods
    shared_ios_mac_pods
end

inhibit_all_warnings!

## Framework iOS
target 'Backtrace-iOS' do
    use_frameworks!
    shared_ios_mac_pods
    target 'Backtrace-iOSTests' do
        inherit! :search_paths
        shared_test_ios_mac_pods
    end
end

## Framework macOS
target 'Backtrace-macOS' do
    platform :osx, '10.11'
    use_frameworks!
    shared_ios_mac_pods
    target 'Backtrace-macOSTests' do
        inherit! :search_paths
        shared_test_ios_mac_pods
    end
end

## Framework tvOS
target 'Backtrace-tvOS' do
    use_frameworks!
    shared_pods
    target 'Backtrace-tvOSTests' do
        inherit! :search_paths
        shared_test_pods
    end
end

# Examples

## Definitions	
def local_backtrace
    pod 'Backtrace', :path => "./Backtrace.podspec"
end

## Example targets
target 'Example-iOS' do
    use_frameworks!
    local_backtrace
end

target 'Example-iOS-ObjC' do
    use_frameworks!
    local_backtrace
end

target 'Example-macOS-ObjC' do
    platform :osx, '10.11'
    use_frameworks!
    local_backtrace
end

target 'Example-tvOS' do
    use_frameworks!
    local_backtrace
end

# Post install configuration
post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
            config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '10.0'
        end
    end
  end
