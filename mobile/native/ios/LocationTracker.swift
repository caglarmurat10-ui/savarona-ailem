import CoreLocation
import Foundation
import UIKit

private enum SpeedProfile {
    case vehicle, walking, stationary
    var distanceFilter: CLLocationDistance { switch self { case .vehicle:return 15; case .walking:return 10; case .stationary:return 50 } }
    var accuracy: CLLocationAccuracy { switch self { case .vehicle,.walking:return kCLLocationAccuracyBest; case .stationary:return kCLLocationAccuracyHundredMeters } }
    var activityLabel: String { switch self { case .vehicle:return "automotive"; case .walking:return "walking"; case .stationary:return "stationary" } }
}

final class LocationTracker: NSObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()
    private let manager = CLLocationManager()
    private var backgroundSession: AnyObject?
    private var currentProfile: SpeedProfile?
    private var flushBackoff: TimeInterval = 2
    private var flushScheduled = false
    private var heartbeatTimer: Timer?
    private var pendingPermissionCompletion: ((Bool) -> Void)?

    private override init() {
        super.init(); manager.delegate=self; manager.desiredAccuracy=kCLLocationAccuracyBest; manager.distanceFilter=10
        manager.activityType = .automotiveNavigation; manager.pausesLocationUpdatesAutomatically=false
        manager.allowsBackgroundLocationUpdates=true; manager.showsBackgroundLocationIndicator=true
    }

    func requestPermission(completion:@escaping(Bool)->Void){ pendingPermissionCompletion=completion; if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestAlwaysAuthorization() } }

    func start(apiBaseUrl:String, deviceToken:String){
        TrackingStatusStore.saveCredentials(apiBaseUrl:apiBaseUrl,deviceToken:deviceToken); TrackingStatusStore.setTrackingRequested(true)
        guard authorized else { refreshPermissionStatus(); TrackingStatusStore.setTrackingActive(false); return }
        TrackingStatusStore.setPermissionState("granted_always")
        if #available(iOS 17.0, *) { backgroundSession=CLBackgroundActivitySession() }
        manager.startUpdatingLocation(); TrackingStatusStore.setTrackingActive(true); startHeartbeat(); scheduleFlush(after:0)
    }

    func stop(){ TrackingStatusStore.setTrackingRequested(false); pauseTracking() }
    private func pauseTracking(){ manager.stopUpdatingLocation(); if #available(iOS 17.0, *){(backgroundSession as? CLBackgroundActivitySession)?.invalidate()}; backgroundSession=nil; heartbeatTimer?.invalidate(); heartbeatTimer=nil; TrackingStatusStore.setTrackingActive(false) }

    func restoreIfAuthorized(){ guard authorized, let api=TrackingStatusStore.apiBaseUrl, let token=TrackingStatusStore.deviceToken, TrackingStatusStore.trackingRequested else{return}; start(apiBaseUrl:api,deviceToken:token) }

    func refreshPermissionStatus(){ switch manager.authorizationStatus { case .authorizedAlways:TrackingStatusStore.setPermissionState("granted_always"); case .authorizedWhenInUse:TrackingStatusStore.setPermissionState("granted_when_in_use"); case .denied,.restricted:TrackingStatusStore.setPermissionState(TrackingStatusStore.trackingRequested ? "permission_lost":"denied"); case .notDetermined:TrackingStatusStore.setPermissionState("not_requested"); @unknown default:TrackingStatusStore.setPermissionState("not_requested") } }
    private var authorized:Bool { manager.authorizationStatus == .authorizedAlways }

    func locationManager(_ manager:CLLocationManager,didChangeAuthorization status:CLAuthorizationStatus){
        switch status {
        case .authorizedAlways:
            pendingPermissionCompletion?(true); pendingPermissionCompletion=nil; TrackingStatusStore.setPermissionState("granted_always")
            if TrackingStatusStore.trackingRequested && !TrackingStatusStore.trackingActive, let api=TrackingStatusStore.apiBaseUrl, let token=TrackingStatusStore.deviceToken { start(apiBaseUrl:api,deviceToken:token) }
        case .authorizedWhenInUse:
            pendingPermissionCompletion?(false); pendingPermissionCompletion=nil; TrackingStatusStore.setPermissionState("granted_when_in_use"); if TrackingStatusStore.trackingRequested { pauseTracking(); sendHeartbeat() }
        case .denied,.restricted:
            pendingPermissionCompletion?(false); pendingPermissionCompletion=nil; let was=TrackingStatusStore.trackingRequested; TrackingStatusStore.setPermissionState(was ? "permission_lost":"denied"); if was { pauseTracking(); sendHeartbeat() }
        case .notDetermined: TrackingStatusStore.setPermissionState("not_requested")
        @unknown default: pendingPermissionCompletion?(false); pendingPermissionCompletion=nil; TrackingStatusStore.setPermissionState("not_requested")
        }
    }

    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]){
        guard let location=locations.last else{return}; let speed=location.speed >= 0 ? location.speed:nil
        let profile:SpeedProfile = { if let s=speed, s>=8{return .vehicle}; if let s=speed, s>=0.5{return .walking}; return .stationary }()
        applyProfile(profile)
        let sample=QueuedSample(id:UUID(),sequenceNo:TrackingStatusStore.nextSequenceNo(),capturedAt:Int64(location.timestamp.timeIntervalSince1970*1000),lat:location.coordinate.latitude,lng:location.coordinate.longitude,accuracyM:location.horizontalAccuracy>=0 ? location.horizontalAccuracy:nil,speedMps:speed,headingDeg:location.course>=0 ? location.course:nil,batteryPct:currentBatteryPct(),activity:profile.activityLabel)
        LocationUploadQueue.shared.enqueue(sample)
    }

    private func applyProfile(_ profile:SpeedProfile){ guard currentProfile != profile else{return}; currentProfile=profile; manager.distanceFilter=profile.distanceFilter; manager.desiredAccuracy=profile.accuracy }
    private func currentBatteryPct()->Int?{ UIDevice.current.isBatteryMonitoringEnabled=true; let level=UIDevice.current.batteryLevel; return level>=0 ? Int(level*100):nil }

    private func startHeartbeat(){ heartbeatTimer?.invalidate(); sendHeartbeat(); heartbeatTimer=Timer.scheduledTimer(withTimeInterval:30,repeats:true){[weak self]_ in self?.sendHeartbeat()} }
    private func sendHeartbeat(){
        guard let api=TrackingStatusStore.apiBaseUrl, let token=TrackingStatusStore.deviceToken, let url=URL(string:api.hasSuffix("/") ? "\(api)v1/heartbeat":"\(api)/v1/heartbeat") else{return}
        let permission:String; switch manager.authorizationStatus { case .authorizedAlways:permission="granted_always"; case .authorizedWhenInUse:permission="granted_when_in_use"; case .denied,.restricted:permission=TrackingStatusStore.trackingRequested ? "permission_lost":"denied"; default:permission="not_requested" }
        var payload:[String:Any]=["permission_state":permission,"app_state":TrackingStatusStore.trackingActive ? "tracking":"permission_lost"]; if let b=currentBatteryPct(){payload["battery_pct"]=b}
        guard JSONSerialization.isValidJSONObject(payload), let data=try? JSONSerialization.data(withJSONObject:payload) else{return}
        var req=URLRequest(url:url,timeoutInterval:8); req.httpMethod="POST"; req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization"); req.httpBody=data
        URLSession(configuration:.ephemeral).dataTask(with:req).resume()
    }

    private func scheduleFlush(after delay:TimeInterval){ guard !flushScheduled else{return}; flushScheduled=true; DispatchQueue.main.asyncAfter(deadline:.now()+delay){[weak self] in self?.flushScheduled=false; self?.flushOnce()} }
    private func flushOnce(){
        guard TrackingStatusStore.apiBaseUrl != nil, TrackingStatusStore.deviceToken != nil else{return}; guard authorized else{refreshPermissionStatus();scheduleFlush(after:10);return}; guard let item=LocationUploadQueue.shared.peekOldest() else{scheduleFlush(after:2);return}
        send(item){[weak self] outcome in guard let self else{return}; switch outcome { case .delivered,.alreadyDelivered:LocationUploadQueue.shared.remove(id:item.id);TrackingStatusStore.markSendSuccess();self.flushBackoff=2;self.scheduleFlush(after:0); case .failed(let msg):TrackingStatusStore.setLastError(msg);self.flushBackoff=min(self.flushBackoff*2,60);self.scheduleFlush(after:self.flushBackoff) } }
    }
    private enum SendOutcome{case delivered,alreadyDelivered,failed(String)}
    private func send(_ item:QueuedSample,completion:@escaping(SendOutcome)->Void){
        guard let api=TrackingStatusStore.apiBaseUrl, let token=TrackingStatusStore.deviceToken, let url=URL(string:api.hasSuffix("/") ? "\(api)v1/location":"\(api)/v1/location") else{completion(.failed("invalid_config"));return}
        TrackingStatusStore.markSendAttempt(); var req=URLRequest(url:url,timeoutInterval:10);req.httpMethod="POST";req.setValue("application/json",forHTTPHeaderField:"Content-Type");req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization");req.httpBody=item.toJson()
        URLSession(configuration:.ephemeral).dataTask(with:req){_,response,error in if let error{completion(.failed((error as NSError).domain));return}; switch (response as? HTTPURLResponse)?.statusCode {case 200:completion(.delivered);case 409:completion(.alreadyDelivered);case let code:completion(.failed("http_\(code ?? -1)"))}}.resume()
    }
}
