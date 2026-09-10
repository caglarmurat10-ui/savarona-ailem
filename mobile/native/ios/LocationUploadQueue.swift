import Foundation

struct QueuedSample: Codable {
    let id:UUID; let sequenceNo:Int64; let capturedAt:Int64; let lat:Double; let lng:Double; let accuracyM:Double?; let speedMps:Double?; let headingDeg:Double?; let batteryPct:Int?; let activity:String?
    func toJson()->Data{ var p:[String:Any]=["sequence_no":sequenceNo,"captured_at":capturedAt,"lat":lat,"lng":lng]; if let v=accuracyM{p["accuracy_m"]=v};if let v=speedMps{p["speed_mps"]=v};if let v=headingDeg{p["heading_deg"]=v};if let v=batteryPct{p["battery_pct"]=v};if let v=activity{p["activity"]=v};return (try? JSONSerialization.data(withJSONObject:p)) ?? Data() }
}
final class LocationUploadQueue {
    static let shared=LocationUploadQueue(); static let maxRows=500; private let fileURL:URL; private let queue=DispatchQueue(label:"com.savarona.ailem.upload-queue")
    private init(){let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0];try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);fileURL=dir.appendingPathComponent("savarona_tracking_queue.json")}
    private func readAll()->[QueuedSample]{guard let d=try? Data(contentsOf:fileURL) else{return []};return (try? JSONDecoder().decode([QueuedSample].self,from:d)) ?? []}
    private func writeAll(_ items:[QueuedSample]){guard let d=try? JSONEncoder().encode(items) else{return};try? d.write(to:fileURL,options:.atomic)}
    func enqueue(_ sample:QueuedSample){queue.sync{var items=readAll();items.append(sample);if items.count>Self.maxRows{items.removeFirst(items.count-Self.maxRows)};writeAll(items)}}
    func peekOldest()->QueuedSample?{queue.sync{readAll().first}}
    func remove(id:UUID){queue.sync{var items=readAll();items.removeAll{$0.id==id};writeAll(items)}}
    func count()->Int{queue.sync{readAll().count}}
}
