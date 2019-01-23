def shared_pods
    pod 'Backtrace-PLCrashReporter'
    pod 'SwiftLint'
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
