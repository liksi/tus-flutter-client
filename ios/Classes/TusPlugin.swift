import Flutter
import UIKit
import TUSKit
import os
public class TusPlugin: NSObject, FlutterPlugin {
    private static let channelName = "io.tus.flutter_service"
    private let channel: FlutterMethodChannel
    private var tusClient: TUSClient?
    private var configured = false
    private var configuredEndpointUrl: String?
    private var urlSessionConfiguration: URLSessionConfiguration?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: TusPlugin.channelName, binaryMessenger: registrar.messenger())
        let instance = TusPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "initWithEndpoint":
            self.initWithEndpoint(call, result)
        case "createUploadFromFile":
            self.createUploadFromFile(call, result)
        case "retryUpload":
            self.retryUpload(call, result)
        case "stopAndRemoveUpload":
            self.stopAndRemoveUpload(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initWithEndpoint(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
            let endpointUrlString = arguments["endpointUrl"] as? String,
            let endpointUrl = URL(string: endpointUrlString) else {
            result(FlutterError(code: "BAD_ARGS", message: "Missing or invalid 'endpointUrl'", details: nil))
            return
        }

        // Initialization
        let sessionIdentifier = UUID().uuidString
        do {
            self.tusClient = try TUSClient(
                server: endpointUrl,
                sessionIdentifier: sessionIdentifier,
                sessionConfiguration: .background(withIdentifier: sessionIdentifier),
                storageDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
                chunkSize: 0
            )

            self.tusClient!.delegate = self
            let remainingUploads = self.tusClient!.start()
            switch remainingUploads.count {
            case 0:
                print("No files to upload")
            case 1:
                print("Continuing uploading single file")
            case let nr:
                print("Continuing uploading \(nr) file(s)")
            }

            let storedUploads = try self.tusClient!.getStoredUploads()
            for storedUpload in storedUploads {
                print("\(storedUpload) Stored upload")
                print("\(storedUpload.uploadedRange?.upperBound ?? 0)/\(storedUpload.size) uploaded")
                try tusClient!.resume(id: storedUpload.id)
            }

            self.tusClient!.cleanup()
        } catch {
            assertionFailure("Could not fetch failed id's from disk, or could not instantiate TUSClient \(error)")
        }

        self.configuredEndpointUrl = endpointUrl.absoluteString
        self.configured = true

        print("Initialized TUSKit with endpoint \(endpointUrl.absoluteString)")
        result(["endpointUrl": endpointUrl.absoluteString])
    }

    private func createUploadFromFile(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        print("Create new upload from TUS flutter plugin")

        guard let tusClient = self.tusClient else {
            result(FlutterError(code: "NO_CLIENT", message: "TUSClient has not been initialized. Call 'initWithEndpoint' first.", details: nil))
            return
        }
        guard let arguments = call.arguments as? [String: Any],
            let fileUploadUrl = arguments["fileUploadUrl"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "Argument 'fileUploadUrl' is missing", details: nil))
            return
        }

        let fileURL = URL(fileURLWithPath: fileUploadUrl)
        let metadata = arguments["metadata"] as? [String: String] ?? [:]
        let headers = arguments["headers"] as? [String: String] ?? [:]
        
        print("Starting upload with metadata: \(metadata) and headers: \(headers) and fileURL \(fileURL)")
        
        do {
            try tusClient.uploadFileAt(filePath: fileURL, customHeaders: headers, context: metadata)
            result(["inProgress": true])
        } catch {
            result(FlutterError(code: "UPLOAD_ERROR", message: "Failed to create new upload: \(error.localizedDescription)", details: nil))
        }
    }

    private func retryUpload(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        print("Retrying upload from TUS flutter plugin")

        guard let tusClient = self.tusClient else {
            result(FlutterError(code: "NO_CLIENT", message: "TUSClient has not been initialized. Call 'initWithEndpoint' first.", details: nil))
            return
        }
        guard let arguments = call.arguments as? [String: Any],
            let uploadId = arguments["uploadId"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "Argument 'uploadId' is missing", details: nil))
            return
        }
        guard let arguments = call.arguments as? [String: Any],
            let fileUploadUrl = arguments["fileUploadUrl"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "Argument 'fileUploadUrl' is missing", details: nil))
            return
        }
        
        let fileURL = URL(fileURLWithPath: fileUploadUrl)
        let metadata = arguments["metadata"] as? [String: String] ?? [:]
        let headers = arguments["headers"] as? [String: String] ?? [:]

        print("Starting retryUpload with metadata: \(metadata) and headers: \(headers) and fileURL \(fileURL)")
        
        do {
            let retrySuccess = try tusClient.retry(id: UUID(uuidString: uploadId)!)
            if retrySuccess {
                result(["inProgress": true])
            } else {
                try tusClient.uploadFileAt(filePath: fileURL, customHeaders: headers, context: metadata)
                result(["inProgress": true])
            }
        } catch {
            result(FlutterError(code: "UPLOAD_ERROR", message: "Failed to manage the upload: \(error.localizedDescription)", details: nil))
        }
    }

    private func stopAndRemoveUpload(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let tusClient = self.tusClient else {
            result(FlutterError(code: "NO_CLIENT", message: "TUSClient has not been initialized. Call 'initWithEndpoint' first.", details: nil))
            return
        }
        guard let arguments = call.arguments as? [String: Any],
            let uploadId = arguments["uploadId"] as? UUID else {
            result(FlutterError(code: "BAD_ARGS", message: "Argument 'uploadId' is missing", details: nil))
            return
        }
        do {
            // Cancel the upload
            try tusClient.cancel(id: uploadId)
            tusClient.cleanup()
            result(["canceled": true])
        } catch {
            result(FlutterError(code: "CANCEL_ERROR", message: "Failed to cancel upload: \(error.localizedDescription)", details: nil))
        }
    }
}

extension TusPlugin: TUSClientDelegate {
    public func progressFor(id: UUID, context: [String : String]?, bytesUploaded: Int, totalBytes: Int, client: TUSKit.TUSClient) {
        print("Upload progress for \(id) \(bytesUploaded)/\(totalBytes) bytes uploaded")

        var args = [String: String]()
        args["endpointUrl"] = self.configuredEndpointUrl
        args["bytesWritten"] = String(bytesUploaded)
        args["bytesTotal"] = String(totalBytes)
        args["uploadId"] = context!["uuid"]

        self.channel.invokeMethod("progressBlock", arguments: args)
    }
    
    public func didStartUpload(id: UUID, context: [String : String]?, client: TUSKit.TUSClient) {
        print("Upload start for \(id)")
    }
    
    public func didFinishUpload(id: UUID, url: URL, context: [String : String]?, client: TUSKit.TUSClient) {
        print("Upload finished for \(id)")

        var args = [String: String]()
        args["endpointUrl"] = self.configuredEndpointUrl
        args["resultUrl"] = url.absoluteString
        args["uploadId"] = context!["uuid"]

        self.channel.invokeMethod("resultBlock", arguments: args)
    }
    
    public func uploadFailed(id: UUID, error: Error, context: [String : String]?, client: TUSKit.TUSClient) {
        print("Upload failed for \(id)")

        var args = [String: String]()
        args["endpointUrl"] = self.configuredEndpointUrl
        args["error"] = error.localizedDescription
        args["uploadId"] = context!["uuid"]

        self.channel.invokeMethod("failureBlock", arguments: args)
    }
    
    public func fileError(error: TUSKit.TUSClientError, client: TUSKit.TUSClient) {
        print("Upload file error \(error)")
    }
    
    public func totalProgress(bytesUploaded: Int, totalBytes: Int, client: TUSKit.TUSClient) {
        //print("Upload total progress \(bytesUploaded)")
    }
}
