// Copyright 2020 Lionell Yip. All rights reserved.

import 'dart:core';

import 'package:flutter/services.dart';

typedef void OnCompleteCallback(String result, String uploadId);
typedef void OnProgressCallback(int bytesWritten, int bytesTotal, double progress, String uploadId);
typedef void OnErrorCallback(String error, String uploadId);
typedef void OnAuthRequiredCallback(String uploadId);

// The Tus Flutter client.
//
// Each tus flutter client supports one endpoint url to upload files to.
// If you need multiple tus upload endpoints, instantiate multiple tus clients.
class Tus {
  static const MethodChannel _channel = const MethodChannel('io.tus.flutter_service');

  // The endpoint url.
  final String endpointUrl;
  OnProgressCallback? onProgress;
  OnCompleteCallback? onComplete;
  OnErrorCallback? onError;
  OnAuthRequiredCallback? onAuthRequired;

  // Flag to ensure that the tus client is initialized.
  bool isInitialized = false;

  // Headers for client-wide uploads.
  Map<String, String> headers = Map<String, String>();

  // Number of retries before giving up. Defaults to infinite retries.
  int retry = -1;

  // [iOS-only] Allows cellular access for uploads.
  bool allowsCellularAccess;
  // [iOS-only] Configure for background tasks
  bool enableBackground;

  Tus(this.endpointUrl,
      {this.onProgress,
      this.onComplete,
      this.onError,
      Map<String, String>? headers,
      this.allowsCellularAccess = true,
      this.enableBackground = true}) : this.headers = headers ?? Map<String, String>() {
    _channel.setMethodCallHandler(this.handler);
  }

  // Handles the method calls from the native side.
  Future<Null> handler(MethodCall call) {
    // Ensure that the endpointUrl provided from the MethodChannel is the same
    // as the flutter client.
    switch (call.method) {
      case "progressBlock":
      case "resultBlock":
      case "failureBlock":
      case "authRequiredBlock":
        if (call.arguments["endpointUrl"] != endpointUrl) {
          // This method call is not meant for this client.
          return Future.value(null);
        }
        break;
    }

    // Trigger the onProgress callback if the callback is provided.
    if (call.method == "progressBlock") {
      var bytesWritten = int.tryParse(call.arguments["bytesWritten"]) ?? 0;
      var bytesTotal = int.tryParse(call.arguments["bytesTotal"]) ?? 0;
      var uploadId = call.arguments["uploadId"] ?? "";

      if (onProgress != null) {
        double progress = bytesWritten / bytesTotal;
        onProgress!(bytesWritten, bytesTotal, progress, uploadId);
      }
    }

    // Trigger the onComplete callback if the callback is provided.
    if (call.method == "resultBlock") {
      var resultUrl = call.arguments["resultUrl"];
      var uploadId = call.arguments["uploadId"] ?? "";

      if (onComplete != null) {
        onComplete!(resultUrl, uploadId);
      }
    }

    // Triggers the onError callback if the callback is provided.
    if (call.method == "failureBlock") {
      var error = call.arguments["error"] ?? "";
      var uploadId = call.arguments["uploadId"] ?? "";

      if (onError != null) {
        onError!(error, uploadId);
      }
    }

    // Triggers the onAuthRequired callback if the callback is provided
    if (call.method == "authRequiredBlock") {
      var uploadId = call.arguments["uploadId"] ?? "";
      if (onAuthRequired != null) {
        onAuthRequired!(uploadId);
      }
    }
    return Future.value(null);
  }

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  Future<void> retryUpload(String uploadId, String fileToUpload, {Map<String, String>? metadata}) async {
    if (!isInitialized) {
      await initializeWithEndpoint();
    }

    // Ensures that metadata is not null by providing an empty map, if not
    // provided by the user.
    if (metadata == null) {
      metadata = Map<String, String>();
    }

    var argRetry = metadata["retry"] ?? retry.toString();

    try {
      var result = await _channel.invokeMethod("retryUpload", <String, dynamic>{
        "uploadId": uploadId,
        "endpointUrl": endpointUrl,
        "fileUploadUrl": fileToUpload,
        "retry": argRetry,
        "headers": headers,
        "metadata": metadata,
      });

      if (result.containsKey("error")) {
        throw Exception("${result["error"]} { ${result["reason"]} }");
      }

      return result;
    } catch (error) {
      throw error;
    }
  }

  Future<void> stopUpload({required String uploadId, required String fileBeingUploaded}) async {
    var result = await _channel.invokeMethod("stopAndRemoveUpload", {
      "uploadId": uploadId,
      "fileUploadUrl": fileBeingUploaded
    });

    if (result.containsKey("error")) {
      throw Exception("Error stopping upload $uploadId : ${result["error"]} { ${result["reason"]} }");
    }
    return result;
  }

  // Initialize the tus client on the native side.
  Future<Map> initializeWithEndpoint() async {
    if (isInitialized) return {};

    var response = await _channel.invokeMethod("initWithEndpoint", <String, dynamic>{
      "endpointUrl": endpointUrl,
      "headers": headers,
      "options": <String, String>{
        "allowsCellularAccess": allowsCellularAccess.toString(),
        "enableBackground": enableBackground.toString(),
      },
    });

    isInitialized = true;

    return response;
  }

  // Performs a file upload using the tus protocol. Provide a [fileToUpload].
  // Optionally, you can provide [metadata] to enrich the file upload.
  // Note that filename is provided in the [metadata] upon upload.
  Future<dynamic> createUploadFromFile(String fileToUpload, {Map<String, String>? metadata}) async {
    if (!isInitialized) {
      await initializeWithEndpoint();
    }

    // Ensures that metadata is not null by providing an empty map, if not
    // provided by the user.
    if (metadata == null) {
      metadata = Map<String, String>();
    }

    var argRetry = metadata["retry"] ?? retry.toString();

    try {
      var result = await _channel.invokeMapMethod("createUploadFromFile", <String, dynamic>{
        "endpointUrl": endpointUrl,
        "fileUploadUrl": fileToUpload,
        "retry": argRetry,
        "headers": headers,
        "metadata": metadata,
      });

      if (result?.containsKey("error") ?? false) {
        throw Exception("${result!["error"]} { ${result!["reason"]} }");
      }

      return result;
    } catch (error) {
      throw error;
    }
  }
}
