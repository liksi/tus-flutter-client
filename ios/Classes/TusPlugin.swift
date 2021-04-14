import Flutter
import TUSKit
import os

public class TusPlugin: NSObject, FlutterPlugin {
    private static let channelName = "io.tus.flutter_service"
    // invalidParameters = "Invalid Parameters"
    // fileName = "tuskit_example"

    let channel: FlutterMethodChannel
    private var urlSessionConfiguration: URLSessionConfiguration?

    private var configured = false
    private var configuredEndpointUrl = ""

    public static var registerPlugins: FlutterPluginRegistrantCallback?

    // MARK: Flutter
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: TusPlugin.channelName, binaryMessenger: registrar.messenger())

        let instance = TusPlugin(channel)

        registrar.addMethodCallDelegate(instance, channel: channel)
//        registrar.addApplicationDelegate(instance) // TODO: check if this can be used to enable background without modifying main application
    }

    init(_ channel: FlutterMethodChannel) {
        self.channel = channel
    }


    // MARK: Flutter method call handling
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Void {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "initWithEndpoint":
            self.initWithEndpoint(call, result)
        case "createUploadFromFile":
            self.createUploadFromFile(call, result)
        case "retryUpload":
            self.retryUploadWithId(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func retryUploadWithId(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any?]
        let newHeaders = arguments["headers"]

        let uploadId = arguments["uploadId"] as? String

        if (TUSClient.shared.currentUploads?.contains(where: {$0.id == uploadId}) ?? false) {
            let message = "Retry existing upload from TUS flutter plugin"
            if #available(iOS 10.0, *) {
                let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
                os_log("%{public}@", log: log, type: OSLogType.default, message)
            } else {
                print(message)
            }
            let upload = TUSClient.shared.currentUploads!.first(where: {$0.id == uploadId})!

            if let headers = newHeaders as? [String: String] {
                upload.customHeaders = headers
            }

            TUSClient.shared.retry(forUpload: upload)

            result(["inProgress": "true"])
            return
        } else {
            let message = "Create new upload from retry call from TUS flutter plugin"
            if #available(iOS 10.0, *) {
                let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
                os_log("%{public}@", log: log, type: OSLogType.default, message)
            } else {
                print(message)
            }
            createUploadFromFile(call, result)
        }
    }

    private func initWithEndpoint(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any?]
        let options = arguments["options"] as? [String: Any?]
        let headers = arguments["headers"] as? [String: String] ?? [:]

        let message = "Init TUSKit from TUS flutter plugin"
        if #available(iOS 10.0, *) {
            let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
            os_log("%{public}@", log: log, type: OSLogType.default, message)
        } else {
            print(message)
        }

        // TODO: rework on this section to check for existing "session"
        let endpointUrl = arguments["endpointUrl"] as! String
        if (!self.configured) {
            let message = "Configuring TUSKit from TUS flutter plugin"
            if #available(iOS 10.0, *) {
                let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
                os_log("%{public}@", log: log, type: OSLogType.default, message)
            } else {
                print(message)
            }
            self.configureURLSession(options)
            let config = TUSConfig(withUploadURLString: endpointUrl, andSessionConfig: self.urlSessionConfiguration!, withCustomHeaders: headers)
            config.logLevel = .All // options ?
            TUSClient.setup(with: config)
            TUSClient.shared.delegate = self
            // TODO: configurable chunksize
            // TUSClient.shared.chunkSize = // options ?
            self.configuredEndpointUrl = endpointUrl
            self.configured = true
        }
//        TUSClient.shared.resumeAll()

        result(["endpointUrl": endpointUrl])
    }

    private func configureURLSession(_ options: [String: Any?]?) {
        let backgroundEnabled = options?["enableBackground"] as? String == "true"
        let allowsCellularAccess = options?["allowsCellularAccess"] as? String == "true"

        if (backgroundEnabled) {
            self.urlSessionConfiguration = URLSessionConfiguration.background(withIdentifier: TusPlugin.channelName)
            self.urlSessionConfiguration?.httpMaximumConnectionsPerHost = 1

            // TODO: check following properties
            if #available(iOS 13.0, *) {
                self.urlSessionConfiguration?.allowsExpensiveNetworkAccess = true
                self.urlSessionConfiguration?.allowsConstrainedNetworkAccess = true
            }

            if #available(iOS 9.0, *) {
                self.urlSessionConfiguration?.shouldUseExtendedBackgroundIdleMode = true
            }
        } else {
            self.urlSessionConfiguration = URLSessionConfiguration.default
        }

        self.urlSessionConfiguration?.sessionSendsLaunchEvents = true
        self.urlSessionConfiguration?.allowsCellularAccess = allowsCellularAccess
        
        if #available(iOS 11.0, *) {
            // TODO: check this (and the associated delegate method)
            // NOTE: delegate taskIsWaitingForConnectivity is never called for background tasks
            self.urlSessionConfiguration?.waitsForConnectivity = true
        }
    }

    private func createUploadFromFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let message = "Create new upload from TUS flutter plugin"
        if #available(iOS 10.0, *) {
            let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
            os_log("%{public}@", log: log, type: OSLogType.default, message)
        } else {
            print(message)
        }

        let arguments = call.arguments as! [String: Any?]

        guard self.configured else {
            result(["error": "Missing configuration", "reason": "You must configure TUS before calling upload, use initWithEndpoint method"])
            return
        }

        guard let fileUploadUrlString = arguments["fileUploadUrl"] as? String else {
            result(["error": "Argument missing", "reason": "Argument fileUploadUrl is missing"])
            return
        }
        let fileUploadUrl = URL(fileURLWithPath: fileUploadUrlString)
        let fileNameExt = fileUploadUrl.lastPathComponent.components(separatedBy: ".")
        guard let fileName = fileNameExt.first else {
            result(["error": "Argument malformed", "reason": "Cannot infer file name from fileUploadUrl"])
            return
        }
        guard var fileType = fileNameExt.last else {
            result(["error": "Argument malformed", "reason": "Cannot infer file extension from fileUploadUrl"])
            return
        }
        fileType = "." + fileType
        guard let headers = arguments["headers"] as? [String: String] else { // Not mandatory anymore
            result(["error": "Missing argument", "reason": "Argument for TUS headers is missing"])
            return
        }
        let metadata = arguments["metadata"] as? [String: String]

        // arguments["retry"]

        var upload: TUSUpload

        // if currentUploads does not contain "fileName as id" then create new tusupload object
        if (TUSClient.shared.currentUploads?.contains(where: {$0.id == fileName}) ?? false) {
            upload = TUSClient.shared.currentUploads!.first(where: {$0.id == fileName})!
            switch upload.status {
                case .new, .paused, .created, .enqueued:
                    break
                case .error:
                    TUSClient.shared.pause(forUpload: upload) { pausedUpload in
                        pausedUpload.metadata = metadata ?? [String: String]()
                        TUSClient.shared.createOrResume(forUpload: pausedUpload, withCustomHeaders: headers)
                        result(["inProgress": "true"])
                    }
                    return
                case .uploading: // TODO: check for .uploading status (should happen only in few specific hard to debug cases, e. g. when background session launched but delegate not called)
                    TUSClient.shared.pause(forUpload: upload) { pausedUpload in
                        result(["error": "Cannot handle current upload state.",
                        "reason": "Trying to recreate a .uploading object. Use retry instead"])
                    }
                    return
                default:
                    result(["error": "Cannot handle current upload state.",
                            "reason": "Upload exists and has unhandled status \(upload.status?.rawValue ?? "unknown")"])
                    return
            }
        } else {
            upload = TUSUpload(withId: fileName, andFilePathURL: fileUploadUrl, andFileType: fileType)
        }

        upload.metadata = metadata ?? [String: String]()
        TUSClient.shared.createOrResume(forUpload: upload, withCustomHeaders: headers)
        result(["inProgress": "true"])
    }
}

extension TusPlugin: TUSDelegate {
    public func TUSProgress(bytesUploaded uploaded: Int, bytesRemaining remaining: Int) {
    }

    public func TUSProgress(forUpload upload: TUSUpload, bytesUploaded uploaded: Int, bytesRemaining remaining: Int) {
        var a = [String: String]()
        a["bytesWritten"] = String(uploaded)
        a["bytesTotal"] = String(remaining) // Misnaming in TUSKit v2.0.0 release, "remaining" is effectively "total"
        a["endpointUrl"] = self.configuredEndpointUrl

        self.channel.invokeMethod("progressBlock", arguments: a)
    }

    public func TUSSuccess(forUpload upload: TUSUpload) {
        
        var a = [String: String]()
        a["endpointUrl"] = self.configuredEndpointUrl
        a["resultUrl"] = upload.uploadLocationURL?.absoluteString

        let message = "TUSSuccess delegate called from TUS flutter plugin with arguments: \(a)"
        if #available(iOS 10.0, *) {
            let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
            os_log("%{public}@", log: log, type: OSLogType.default, message)
        } else {
            print(message)
        }

        self.channel.invokeMethod("resultBlock", arguments: a)
        // result(a) ???
    }

    public func TUSFailure(forUpload upload: TUSUpload?, withResponse response: TUSResponse?, andError error: Error?) {
        var a = [String: String]()
        a["endpointUrl"] = self.configuredEndpointUrl
        a["error"] = error as? String ?? response?.message ?? "No message for failure"

        let message = "TUSFailure delegate called from TUS flutter plugin with arguments: \(a)"
        if #available(iOS 10.0, *) {
            let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
            os_log("%{public}@", log: log, type: OSLogType.default, message)
        } else {
            print(message)
        }

        self.channel.invokeMethod("failureBlock", arguments: a)
    }

    public func TUSAuthRequired(forUpload upload: TUSUpload?) {
        var a = [String: String]()
        a["endpointUrl"] = self.configuredEndpointUrl
        a["uploadId"] = upload?.id ?? ""

        if (upload == nil) {
            a["error"] = "Auth required but no upload provided"
        }

        let message = "TUSAuthRequired delegate called from TUS flutter plugin with arguments: \(a)"
        if #available(iOS 10.0, *) {
            let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
            os_log("%{public}@", log: log, type: OSLogType.default, message)
        } else {
            print(message)
        }

        self.channel.invokeMethod("authRequiredBlock", arguments: a)
    }
}
