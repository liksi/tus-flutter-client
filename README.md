# tus-flutter-client
[![Protocol](https://img.shields.io/badge/tus_protocol-v1.0.0-blue.svg?style=flat)](http://tus.io/protocols/resumable-upload.html)

A Flutter plugin to upload files using the [tus resumable upload protocol](https://tus.io):
* [TUSKit](https://github.com/tus/TUSKit) on iOS
* [tus-android-client](https://github.com/tus/tus-android-client) on Android

## Features
* Supports multiple upload endpoints.
* Callbacks for the following events: Progress, Completed and Error.

## Pull Requests and Issues
Pull requests are always welcome! 

## Installation

### Flutter project

Add the following to your `pubspec.yml`
```yaml
dependencies:
  #...
  tus: 0.0.1
    git:
      url: https://github.com/liksi/tus-flutter-client
      ref: master
```

### iOS

To lock the TUSKit version use by this plugin, add this to your podfile:
```ruby
# "fork" of method flutter_install_ios_plugin_pods (in fluttertools podhelpers.rb) to customize plugin behavior
def flutter_install_ios_plugin_pods(ios_application_path = nil)
 # defined_in_file is set by CocoaPods and is a Pathname to the Podfile.
  ios_application_path ||= File.dirname(defined_in_file.realpath) if self.respond_to?(:defined_in_file)
  raise 'Could not find iOS application path' unless ios_application_path

  # Prepare symlinks folder. We use symlinks to avoid having Podfile.lock
  # referring to absolute paths on developers' machines.

  symlink_dir = File.expand_path('.symlinks', ios_application_path)
  system('rm', '-rf', symlink_dir) # Avoid the complication of dependencies like FileUtils.

  symlink_plugins_dir = File.expand_path('plugins', symlink_dir)
  system('mkdir', '-p', symlink_plugins_dir)

  plugins_file = File.join(ios_application_path, '..', '.flutter-plugins-dependencies')
  plugin_pods = flutter_parse_plugins_file(plugins_file)
  plugin_pods.each do |plugin_hash|
    plugin_name = plugin_hash['name']
    plugin_path = plugin_hash['path']

    if (plugin_name && plugin_path)
        symlink = File.join(symlink_plugins_dir, plugin_name)
        File.symlink(plugin_path, symlink)

        if plugin_name == 'tus'
           pod 'TUSKit', :git => 'https://github.com/tus/TUSKit', :commit => 'ea038960dda1899031cfde93c659f0e64a912821' # This commit ref can be replaced as you like
           pod plugin_name, :path => File.join('.symlinks', 'plugins', plugin_name, 'ios')
        else
            pod plugin_name, :path => File.join('.symlinks', 'plugins', plugin_name, 'ios')
        end
    end
  end
end
```

And run `pod update` in iOS folder if you have already compiled your app once, else just process as usual for a flutter app.

## Getting Started
```dart
import 'package:tus/tus.dart';

// Create tus client
var tusD = Tus(endpointUrl);

// Setup tus headers
tusD.headers = <String, String>{
  "Authorization": authorizationHeader,
};

// Initialize the tus client
var response = await tusD.initializeWithEndpoint();
response.forEach((dynamic key, dynamic value) {
  print("[$key] $value");
});

// Callbacks for tus events
tusD.onError = (String error, Tus tus) {
  print(error);
  setState(() {
    progressBar = 0.0;
    inProgress = true;
    resultText = error;
  });
};

tusD.onProgress =
    (int bytesWritten, int bytesTotal, double progress, Tus tus) {
  setState(() {
    progressBar = (bytesWritten / bytesTotal);
  });
};

tusD.onComplete = (String result, Tus tus) {
  print("File can be found: $result");
  setState(() {
    inProgress = true;
    progressBar = 1.0;
    resultText = result;
  });
};

// Trigger file upload.
//
await tusD.createUploadFromFile(
    path, // local path on device i.e. /storage/.../image.jpg
    metadata: <String, String>{ // additional metadata 
      "test": "message",
    },
);

// Get the result from your onComplete callback
```

## Future Work
* [ ] Write tests and code coverage
* [ ] tus client for the web

## License
MIT