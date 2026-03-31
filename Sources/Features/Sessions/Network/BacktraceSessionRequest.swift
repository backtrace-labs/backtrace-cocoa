import Foundation
#if os(iOS)
import UIKit
#endif

/// Builds HTTP requests following the TF wire protocol.
enum BacktraceSessionRequest {

    private static let multipartBoundary = "BacktraceSessionBoundary"

    // MARK: - Start Session Request

    static func buildStartSessionRequest(url: URL,
                                         appToken: String,
                                         startTime: Date,
                                         sessionId: String) -> URLRequest {
        var body = Data()
        let boundary = multipartBoundary

        // Required fields
        body.appendMultipartField(name: "token", value: appToken, boundary: boundary)
        body.appendMultipartField(name: "startTime", value: String(startTime.timeIntervalSince1970), boundary: boundary)
        body.appendMultipartField(name: "platform", value: "1", boundary: boundary)  // iOS
        body.appendMultipartField(name: "version", value: "2", boundary: boundary)   // API version

        // Device data
        let deviceData = collectDeviceData()
        if let jsonData = try? JSONSerialization.data(withJSONObject: deviceData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            body.appendMultipartField(name: "deviceData", value: jsonString, boundary: boundary)
        }

        // Agent version
        body.appendMultipartField(name: "agentVersion", value: BacktraceSessionRequest.agentVersion, boundary: boundary)

        // Bundle info
        let bundle = Bundle.main
        body.appendMultipartField(name: "bundleVersion", value: bundle.buildVersionNumber ?? "0", boundary: boundary)
        body.appendMultipartField(name: "bundleIdentifier", value: bundle.bundleIdentifier ?? "app", boundary: boundary)
        body.appendMultipartField(name: "bundleDisplayName", value: bundle.displayName ?? "App", boundary: boundary)
        if let shortVersion = bundle.releaseVersionNumber {
            body.appendMultipartField(name: "bundleShortVersion", value: shortVersion, boundary: boundary)
        }

        // Certificate type (0 = App Store)
        body.appendMultipartField(name: "cert", value: "0", boundary: boundary)

        // WiFi status
        let reachability = NetworkReachability()
        body.appendMultipartField(name: "wifi", value: reachability.isReachable ? "on" : "off", boundary: boundary)

        // Close multipart
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30
        return request
    }

    // MARK: - Parse Start Session Response

    static func parseStartSessionResponse(_ data: Data) throws -> BacktraceSessionStartResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BacktraceSessionError.invalidResponse
        }

        guard let status = json["status"] as? String, status == "ok" else {
            throw BacktraceSessionError.invalidResponse
        }

        let sessionToken = json["sessionToken"] as? String
        let endpointStr = json["endpointAddress"] as? String
        let endpointAddress = endpointStr.flatMap { URL(string: $0) }
        let sessionUrl = json["sessionUrl"] as? String

        return BacktraceSessionStartResponse(
            sessionToken: sessionToken,
            endpointAddress: endpointAddress,
            sessionUrl: sessionUrl
        )
    }

    // MARK: - Build Feedback Request

    static func buildFeedbackRequest(
        sessionToken: String?,
        appToken: String?,
        text: String,
        email: String?,
        screenshot: Data?,
        customFields: [String: String]?,
        sessionAttributes: [String: String]?
    ) -> (data: Data, boundary: String) {
        let boundary = multipartBoundary
        var body = Data()

        if let token = sessionToken {
            body.appendMultipartField(name: "sessionToken", value: token, boundary: boundary)
        }
        if let appToken = appToken, sessionToken == nil {
            // Anonymous feedback — include start parameters
            body.appendMultipartField(name: "token", value: appToken, boundary: boundary)
            body.appendMultipartField(name: "platform", value: "1", boundary: boundary)
            body.appendMultipartField(name: "version", value: "2", boundary: boundary)
        }

        body.appendMultipartField(name: "text", value: text, boundary: boundary)
        body.appendMultipartField(name: "timestamp", value: String(Date().timeIntervalSince1970), boundary: boundary)
        body.appendMultipartField(name: "utcTimestamp", value: String(Date().timeIntervalSince1970), boundary: boundary)

        if let email = email {
            body.appendMultipartField(name: "reporterEmail", value: email, boundary: boundary)
        }

        if let screenshot = screenshot {
            body.appendMultipartFile(name: "screenshot", filename: "screenshot.jpg", mimeType: "image/jpeg", data: screenshot, boundary: boundary)
        }

        if let fields = customFields {
            if let jsonData = try? JSONSerialization.data(withJSONObject: fields),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                body.appendMultipartField(name: "feedbackAttributes", value: jsonString, boundary: boundary)
            }
        }

        if let attrs = sessionAttributes {
            if let jsonData = try? JSONSerialization.data(withJSONObject: attrs),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                body.appendMultipartField(name: "sessionAttributes", value: jsonString, boundary: boundary)
            }
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return (data: body, boundary: boundary)
    }

    // MARK: - Device Data

    private static func collectDeviceData() -> [String: Any] {
        var data: [String: Any] = [
            "manufacturer": "Apple",
            "apiLevel": "1"
        ]

        #if os(iOS)
        let screen = UIScreen.main
        data["screenWidth"] = Int(screen.bounds.width * screen.scale)
        data["screenHeight"] = Int(screen.bounds.height * screen.scale)
        data["deviceModel"] = deviceModelIdentifier()
        data["osVersion"] = UIDevice.current.systemVersion
        data["osRelease"] = UIDevice.current.systemVersion
        #elseif os(macOS)
        data["deviceModel"] = deviceModelIdentifier()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        data["osVersion"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        data["osRelease"] = data["osVersion"]
        #endif

        data["cpuCores"] = String(ProcessInfo.processInfo.processorCount)
        data["memorySize"] = ProcessInfo.processInfo.physicalMemory

        if let storage = totalDiskSpace() {
            data["deviceStorage"] = storage
        }

        let locale = Locale.current
        data["localeLanguage"] = locale.languageCode
        data["localeCountry"] = locale.regionCode

        return data
    }

    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    private static func totalDiskSpace() -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else { return nil }
        return attrs[.systemSize] as? Int64
    }

    static let agentVersion: String = {
        // Use SDK version as agent version identifier
        return "backtrace-cocoa-2.1.0"
    }()
}

// MARK: - Data Multipart File Helper

extension Data {
    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            append(headerData)
        }
        append(data)
        if let crlf = "\r\n".data(using: .utf8) {
            append(crlf)
        }
    }
}

// NOTE: Bundle.displayName, .releaseVersionNumber, .buildVersionNumber are defined in
// Sources/Features/Extensions/Foundation+Extensions.swift — reused here.
