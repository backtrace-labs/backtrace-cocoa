import Foundation
import Testing
@testable import Backtrace

@Suite struct AttributesTests {

    // MARK: - Components

    @Test func setsProcessorInfo() {
        let attributes = ProcessorInfo()
        #expect(attributes.mutable != nil)
        #expect(attributes.immutable != nil)
    }

    @Test func setsDeviceInfo() {
        let attributes = Device()
        #expect(attributes.mutable != nil)
        #expect(attributes.immutable != nil)
    }

    @Test func setsScreenInfo() {
        let attributes = ScreenInfo()
        #expect(attributes.mutable != nil)
        #expect(attributes.immutable != nil)
    }

    @Test func setsLocaleInfo() {
        let attributes = LocaleInfo()
        #expect(attributes.mutable != nil)
        #expect(attributes.immutable != nil)
    }

    @Test func setsNetworkInfo() {
        let attributes = NetworkInfo()
        #expect(attributes.mutable != nil)
        #expect(attributes.immutable != nil)
    }

    @Test func setsLibInfo() {
        let attributes = LibInfo()
        #expect(attributes.mutable != nil)
        #expect(attributes.immutable != nil)
    }

    // MARK: - Processor Info

    @Test func canDisableHostname() {
        let attributes = ProcessorInfo()
        let hostname = attributes.immutable["hostname"] as? String
        #expect(hostname?.isEmpty == true)
    }

    @Test func canEnableHostname() {
        let attributes = ProcessorInfo(reportHostName: true)
        let hostname = attributes.immutable["hostname"] as? String
        #expect(hostname?.isEmpty == false)
    }

    // MARK: - Fault information

    @Test func canOverrideFaultInformation() {
        let oldAttributeValue = "a"
        let newAttributeValue = "b"
        let attributes = AttributesProvider()
        attributes.set(faultMessage: oldAttributeValue)
        attributes.set(faultMessage: newAttributeValue)
        #expect(attributes.allAttributes["error.message"] as? String == newAttributeValue)
    }

    // MARK: - Metrics Info

    @Test func setsApplicationVersionAndSession() {
        let attributes = ApplicationInfo()
        #expect(attributes.immutable["application.version"] != nil)
        #expect(attributes.immutable["application.session"] != nil)
    }

    // MARK: - Device

    @Test func setsUnameSysnameCorrectlyDependingOnPlatform() {
        let attributes = Device()
        guard let sysname = attributes.immutable["uname.sysname"] as? String else {
            Issue.record("could not parse uname.sysname")
            return
        }
#if os(iOS) && !targetEnvironment(macCatalyst)
        #expect(sysname == "iOS")
#elseif os(tvOS)
        #expect(sysname == "tvOS")
#elseif os(macOS) || targetEnvironment(macCatalyst)
        #expect(sysname == "macOS")
#else
        Issue.record("unsupported platform")
#endif
    }

    // MARK: - Attributes Provider

    @Test func setsApplicationVersionAndSessionEvenIfMetricsNotEnabled() {
        let attributes = AttributesProvider()
        #expect(attributes.allAttributes["application.version"] != nil)
        #expect(attributes.allAttributes["application.session"] != nil)
    }

    // MARK: - Version Provider

    @Test func findsFrameworkVersionCorrectly() {
        let attributes = AttributesProvider()

        #expect(attributes.allAttributes["lang.version"] as? String != nil)
        #expect(attributes.allAttributes["backtrace.version"] as? String != nil)
    }

    // MARK: - C API - Statistics

    @Test func setsVmStatistics64Information() throws {
        #expect(try Statistics.vmStatistics64() != nil)
    }

    @Test func setsProcessorSetLoadInfoInformation() throws {
        #expect(try Statistics.processorSetLoadInfo() != nil)
    }

    @Test func setsHostCpuLoadInfoInformation() throws {
        #expect(try Statistics.hostCpuLoadInfo() != nil)
    }

    @Test func setsMachTaskBasicInfoInformation() throws {
        #expect(try Statistics.machTaskBasicInfo() != nil)
    }

    @Test func setsTaskVmInfoInformation() throws {
        #expect(try Statistics.taskVmInfo() != nil)
    }

    @Test func setsTaskEventsInfoInformation() throws {
        #expect(try Statistics.taskEventsInfo() != nil)
    }

    // MARK: - C API - System

    @Test func setsBoottimeInformation() throws {
        #expect(try System.boottime() != 0)
    }

    @Test func setsUptimeInformation() throws {
        #expect(try System.uptime() != 0)
    }

    @Test func setsMachineNameInformation() throws {
        #expect(try System.machine().isEmpty == false)
    }

    @Test func setsModelNameInformation() throws {
        #expect(try System.model().isEmpty == false)
    }

    // MARK: - C API - ProcessInfo

    @Test func setsProcessStartTimeInformation() throws {
        #expect(try ProcessInfo.startTime() != 0)
    }

    @Test func setsProcessAgeInformation() throws {
        sleep(1)
        #expect(try ProcessInfo.age() != 0)
    }

    @Test func setsNumberOfThreadsInformation() throws {
        #expect(try ProcessInfo.numberOfThreads() != 0)
    }
}
