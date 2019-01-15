def shared_pods
    pod 'PLCrashReporter', :git => 'https://github.com/apptailors/plcrashreporter.git', :branch => 'backtrace'
end

# Framework iOS
target 'Backtrace-iOS' do
    use_frameworks!
    shared_pods

    target 'Backtrace-iOSTests' do
        inherit! :search_paths
        shared_pods
    end
end

# Framework macOS
target 'Backtrace-macOS' do
    use_frameworks!
    shared_pods
    target 'Backtrace-macOSTests' do
        inherit! :search_paths
        shared_pods
    end
end

#Examples
target 'Example-iOS' do
    use_frameworks!
    shared_pods
end

target 'Example-iOS-ObjC' do
    use_frameworks!
    shared_pods
end

target 'Example-macOS-ObjC' do
    use_frameworks!
    shared_pods
end
