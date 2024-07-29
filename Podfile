source 'https://cdn.cocoapods.org/'

# Library
project 'Backtrace.xcworkspace'

# Definitions
def shared_pods
    # Define shared CocoaPods here
    pod 'PLCrashReporter', '1.11' 
end

def shared_test_pods
    shared_pods
    pod 'Nimble', '~> 10.0.0'
    pod 'Quick', '~> 5.0.1'
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
    platform :ios, '12.0'
    use_frameworks!
    shared_ios_mac_pods
    target 'Backtrace-iOSTests' do
        inherit! :search_paths
        shared_test_ios_mac_pods
    end
end

## Framework macOS
target 'Backtrace-macOS' do
    platform :osx, '10.13'
    use_frameworks!
    shared_ios_mac_pods
    target 'Backtrace-macOSTests' do
        inherit! :search_paths
        shared_test_ios_mac_pods
    end
end

## Framework tvOS
target 'Backtrace-tvOS' do
    platform :tvos, '12.0'
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
    platform :ios, '12.0'
    use_frameworks!
    local_backtrace
end

target 'Example-iOS-ObjC' do
    platform :ios, '12.0'
    use_frameworks!
    local_backtrace
end

target 'Example-macOS-ObjC' do
    platform :osx, '10.13'
    use_frameworks!
    local_backtrace
end

target 'Example-tvOS' do
    platform :tvos, '12.0'
    use_frameworks!
    local_backtrace
end

# Post install configuration
post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
            config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
            config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.13'
            config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '12.0'
        end
    end
  end
