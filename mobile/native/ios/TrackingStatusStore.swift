import Foundation

enum TrackingStatusStore {
    private static let defaults=UserDefaults.standard
    private static let keyPermissionState="savarona.permissionState", keyTrackingActive="savarona.trackingActive", keyTrackingRequested="savarona.trackingRequested", keyLastSendAttempt="savarona.lastSendAttemptAt", keyLastSendSuccess="savarona.lastSendSuccessAt", keyLastError="savarona.lastError", keyApiBaseUrl="savarona.apiBaseUrl", keySequence="savarona.sequenceCounter"
    static func setPermissionState(_ state:String){defaults.set(state,forKey:keyPermissionState)}
    static func permissionState()->String{defaults.string(forKey:keyPermissionState) ?? "not_requested"}
    static func setTrackingActive(_ active:Bool){defaults.set(active,forKey:keyTrackingActive)}
    static func setTrackingRequested(_ requested:Bool){defaults.set(requested,forKey:keyTrackingRequested)}
    static var trackingRequested:Bool{defaults.bool(forKey:keyTrackingRequested)}
    static var trackingActive:Bool{defaults.bool(forKey:keyTrackingActive)}
    static func markSendAttempt(){defaults.set(Date().timeIntervalSince1970*1000,forKey:keyLastSendAttempt)}
    static func markSendSuccess(){defaults.set(Date().timeIntervalSince1970*1000,forKey:keyLastSendSuccess);defaults.removeObject(forKey:keyLastError)}
    static func setLastError(_ message:String?){defaults.set(message,forKey:keyLastError)}
    static func saveCredentials(apiBaseUrl:String,deviceToken:String){defaults.set(apiBaseUrl,forKey:keyApiBaseUrl);_ = KeychainCredentialStore.saveDeviceToken(deviceToken)}
    static var apiBaseUrl:String?{defaults.string(forKey:keyApiBaseUrl)}
    static var deviceToken:String?{KeychainCredentialStore.readDeviceToken()}
    static func nextSequenceNo()->Int64{let current=(defaults.object(forKey:keySequence) as? NSNumber)?.int64Value ?? 0;let updated=current+1;defaults.set(NSNumber(value:updated),forKey:keySequence);return updated}
    static func snapshot(queuedCount:Int)->[String:Any]{var r:[String:Any]=["permissionState":permissionState(),"trackingActive":trackingActive,"trackingRequested":trackingRequested,"queuedCount":queuedCount];if let v=defaults.object(forKey:keyLastSendAttempt) as? Double{r["lastSendAttemptAt"]=v};if let v=defaults.object(forKey:keyLastSendSuccess) as? Double{r["lastSendSuccessAt"]=v};if let v=defaults.string(forKey:keyLastError){r["lastError"]=v};return r}
}
