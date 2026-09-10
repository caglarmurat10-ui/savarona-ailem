import 'package:flutter_test/flutter_test.dart';
import 'package:savarona_ailem/models/member_location.dart';

void main() {
  test('heartbeat updates presence without rewriting GPS sample time', () {
    final captured = DateTime.now().subtract(const Duration(minutes: 1));
    final m = MemberLocation(memberId:'m1',name:'Murat',lat:36.2,lng:29.6,speedMps:20,locationAt:captured,lastSeenAt:captured);
    final updated=m.copyWithLive({'type':'heartbeat','member_id':'m1','ts':DateTime.now().millisecondsSinceEpoch,'battery_pct':70});
    expect(updated.locationAt,captured); expect(updated.batteryPct,70); expect(updated.liveSpeedKmh,isNull);
  });
  test('permission_lost suppresses live speed',(){final m=MemberLocation(memberId:'m1',name:'Murat',speedMps:10,locationAt:DateTime.now(),permissionState:'permission_lost');expect(m.liveSpeedKmh,isNull);});
}
