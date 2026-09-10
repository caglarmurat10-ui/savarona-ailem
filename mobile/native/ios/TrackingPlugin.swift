import Flutter
import Foundation
import UIKit

final class TrackingPlugin: NSObject {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "savarona_ailem/tracking", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "status":
                LocationTracker.shared.refreshPermissionStatus()
                result(TrackingStatusStore.snapshot(queuedCount: LocationUploadQueue.shared.count()))
            case "requestPermissions":
                LocationTracker.shared.requestPermission { granted in DispatchQueue.main.async { result(granted) } }
            case "start":
                guard let args=call.arguments as? [String:Any], let api=args["apiBaseUrl"] as? String, let token=args["deviceToken"] as? String else { result(FlutterError(code:"invalid_args",message:"apiBaseUrl/deviceToken required",details:nil)); return }
                LocationTracker.shared.start(apiBaseUrl:api,deviceToken:token); result(nil)
            case "stop": LocationTracker.shared.stop(); result(nil)
            case "openAppSettings": if let url=URL(string:UIApplication.openSettingsURLString){DispatchQueue.main.async{UIApplication.shared.open(url)}}; result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
}
