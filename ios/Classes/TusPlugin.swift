import Flutter
import TUSKit

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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initWithEndpoint(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any?]
        let options = arguments["options"] as? [String: Any?]

        // TODO: rework on this section to check for existing "session"
        let endpointUrl = arguments["endpointUrl"] as! String
        if (!self.configured) {
            self.configureURLSession(options)
            let config = TUSConfig(withUploadURLString: endpointUrl, andSessionConfig: self.urlSessionConfiguration!)
            config.logLevel = .All // options ?
            TUSClient.setup(with: config)
            TUSClient.shared.delegate = self
            // TODO: configurable chunksize
            // TUSClient.shared.chunkSize = // options ?
            TUSClient.shared.status = .ready
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
//            if #available(iOS 13.0, *) {
//                self.urlSessionConfiguration?.allowsExpensiveNetworkAccess = true
//                self.urlSessionConfiguration?.allowsConstrainedNetworkAccess = true
//            }

            if #available(iOS 9.0, *) {
                self.urlSessionConfiguration?.shouldUseExtendedBackgroundIdleMode = true
            }
        } else {
            self.urlSessionConfiguration = URLSessionConfiguration.default
        }

        self.urlSessionConfiguration?.sessionSendsLaunchEvents = true
        self.urlSessionConfiguration?.allowsCellularAccess = allowsCellularAccess
        if #available(iOS 11.0, *) {
            self.urlSessionConfiguration?.waitsForConnectivity = true // TODO: check this (and the associated delegate method)
        }
    }

    private func createUploadFromFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let arguments = call.arguments as! [String: Any?]
        let options = arguments["options"] as? [String: Any?]

        if (!self.configured) {
            result(["error": "You must configure TUS before calling upload, use initWithEndpoint method"])
            return
        }

        let fileUploadUrlString = arguments["fileUploadUrl"] as! String
        let fileUploadUrl = URL(fileURLWithPath: fileUploadUrlString)
        let fileNameExt = fileUploadUrlString.components(separatedBy: ".")
        guard let fileName = fileNameExt[fileNameExt.count - 2].components(separatedBy: "/").last else {
            result(["error": "Cannot infer file name from fileUploadUrl"])
            return
        }
        guard var fileType = fileNameExt.last else {
            result(["error": "Cannot infer file extension from fileUploadUrl"])
            return
        }
        fileType = "." + fileType
        guard let headers = arguments["headers"] as? [String: String] else { // Not mandatory anymore
            result(["error": "You must set headers for TUS"])
            return
        }
        let metadata = arguments["metadata"] as? [String: String]

        // arguments["retry"]

        // if currentUploads does not contain "fileName as id" then create new tusupload object
        var upload: TUSUpload
        if (TUSClient.shared.currentUploads?.contains(where: {$0.id == fileName}) ?? false) {
            upload = TUSClient.shared.currentUploads!.first(where: {$0.id == fileName})!
            if (upload.status == .error) { // TODO: switch on upload state
                TUSClient.shared.pause(forUpload: upload)
            } else if (upload.status == .uploading) {
                TUSClient.shared.pause(forUpload: upload)
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

        self.channel.invokeMethod("resultBlock", arguments: a)
        // result(a) ???
    }

    public func TUSFailure(forUpload upload: TUSUpload?, withResponse response: TUSResponse?, andError error: Error?) {
        var a = [String: String]()
        a["endpointUrl"] = self.configuredEndpointUrl
        a["error"] = error as? String ?? response?.message ?? "No message for failure"

        self.channel.invokeMethod("failureBlock", arguments: a)
    }
}
