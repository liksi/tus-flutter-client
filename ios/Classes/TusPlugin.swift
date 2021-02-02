import Flutter
import TUSKit

public class TusPlugin: NSObject, FlutterPlugin, TUSDelegate {
    private static let channelName = "io.tus.flutter_service"
    // invalidParameters = "Invalid Parameters"
    // fileName = "tuskit_example"

    let channel: FlutterMethodChannel
    let urlSessionConfiguration: URLSessionConfiguration

    var configured = false
    var configuredEndpointUrl = ""

    public static var registerPlugins: FlutterPluginRegistrantCallback?

    // MARK: Flutter
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: TusPlugin.channelName, binaryMessenger: registrar.messenger())

        let instance = TusPlugin(channel)

        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance) // TODO: check if this can be used to enable background without modifying main application
    }

    init(_ channel: FlutterMethodChannel) {
        self.channel = channel
        self.urlSessionConfiguration = URLSessionConfiguration.default // TODO: change for "background" with an identifier
        self.urlSessionConfiguration.httpMaximumConnectionsPerHost = 1
        self.urlSessionConfiguration.allowsCellularAccess = true
        self.urlSessionConfiguration.sessionSendsLaunchEvents = true
        if #available(iOS 11.0, *) {
            self.urlSessionConfiguration.waitsForConnectivity = true
        }
    }

    // MARK: ApplicationDelegate
    public func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        NSLog("Session with identifier: %@ called application delegate in flutter tus plugin", identifier)
        // TODO: handle pause when killed
        return true
    }

    // MARK: TUSDelegate
    public func TUSProgress(bytesUploaded uploaded: Int, bytesRemaining remaining: Int) {
        var a = [String: String]()
        a["bytesWritten"] = String(uploaded)
        a["bytesTotal"] = String(remaining) // Misnaming in TUSKit v2.0.0 release, "remaining" is effectively "total"
        a["endpointUrl"] = self.configuredEndpointUrl

        self.channel.invokeMethod("progressBlock", arguments: a)
    }

    public func TUSProgress(forUpload upload: TUSUpload, bytesUploaded uploaded: Int, bytesRemaining remaining: Int) {
        // This delegate method is not called from TUSKit v2.0.0 release
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
        a["error"] = error as? String

        self.channel.invokeMethod("failureBlock", arguments: a)
    }

    // MARK: Flutter method call handling
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Void {
        let arguments = call.arguments as! [String: Any?]
        let options = arguments["options"] as? [String: Any?]

        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "initWithEndpoint":
            self.initWithEndpoint(arguments, result)
        case "createUploadFromFile":
            self.createUploadFromFile(arguments, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initWithEndpoint(_ arguments: [String: Any?], _ result: @escaping FlutterResult) {
        // TODO: rework on this section to check for existing "session"
        let endpointUrl = arguments["endpointUrl"] as! String
        if (!self.configured) {
            var config = TUSConfig(withUploadURLString: endpointUrl, andSessionConfig: self.urlSessionConfiguration)
            config.logLevel = TUSLogLevel.Debug // options ?
            self.urlSessionConfiguration.allowsCellularAccess = true // options ?
            TUSClient.setup(with: config)
            TUSClient.shared.delegate = self
            // TUSClient.shared.chunkSize =
            self.configuredEndpointUrl = endpointUrl
            self.configured = true
        }
        TUSClient.shared.resumeAll() // retryAll() ?
        result(["endpointUrl": endpointUrl])
    }

    private func createUploadFromFile(_ arguments: [String: Any?], _ result: @escaping FlutterResult) {
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
        guard let headers = arguments["headers"] as? [String: String] else {
            result(["error": "You must set headers for TUS"])
            return
        }
        let metadata = arguments["metadata"] as? [String: String]

        // arguments["retry"]

        let uploadFile = TUSUpload(withId: fileName, andFilePathURL: fileUploadUrl, andFileType: fileType)
        uploadFile.metadata = metadata ?? [String: String]()
        TUSClient.shared.createOrResume(forUpload: uploadFile, withCustomHeaders: headers)
        result(["inProgress": "true"])
    }
}
