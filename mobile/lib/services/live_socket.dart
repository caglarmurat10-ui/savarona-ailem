import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/config.dart';
import 'api_client.dart';

enum LiveConnectionState { connecting, live, reconnecting }

class LiveSocket {
  LiveSocket(this.api);
  final ApiClient api;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  Timer? _watchdog;
  DateTime? _lastPong;
  int _attempt = 0;
  bool _closed = false;
  bool _reconnecting = false;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  final _connectionState = StreamController<LiveConnectionState>.broadcast();
  Stream<LiveConnectionState> get connectionState => _connectionState.stream;
  LiveConnectionState _state = LiveConnectionState.connecting;
  LiveConnectionState get state => _state;

  void _setState(LiveConnectionState next) {
    if (_state == next) return;
    _state = next;
    _connectionState.add(next);
  }

  Future<void> start() async {
    _closed = false;
    await _connect();
  }

  Future<void> _connect() async {
    if (_closed) return;
    _reconnecting = false;
    _setState(_attempt == 0 ? LiveConnectionState.connecting : LiveConnectionState.reconnecting);
    try {
      final ticket = await api.createLiveTicket();
      final channel = WebSocketChannel.connect(AppConfig.wsUri(ticket));
      _channel = channel;
      await channel.ready;
      if (_closed) {
        await channel.sink.close();
        return;
      }
      _attempt = 0;
      _lastPong = DateTime.now();
      _setState(LiveConnectionState.live);
      await _sub?.cancel();
      _sub = channel.stream.listen((raw) {
        if (raw is! String) return;
        try {
          final value = jsonDecode(raw);
          if (value is Map) {
            final event = Map<String, dynamic>.from(value);
            if (event['type'] == 'pong' || event['type'] == 'connected') {
              _lastPong = DateTime.now();
            }
            if (event['type'] != 'pong') _events.add(event);
          }
        } catch (_) {}
      }, onDone: _scheduleReconnect, onError: (_) => _scheduleReconnect());
      _startWatchdog();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_closed || _state != LiveConnectionState.live) return;
      final last = _lastPong;
      if (last != null && DateTime.now().difference(last) > const Duration(seconds: 55)) {
        _channel?.sink.close();
        _scheduleReconnect();
        return;
      }
      try {
        _channel?.sink.add('ping');
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _scheduleReconnect() {
    if (_closed || _reconnecting) return;
    _reconnecting = true;
    _watchdog?.cancel();
    _setState(LiveConnectionState.reconnecting);
    if (_reconnect?.isActive == true) return;
    final seconds = [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)];
    _attempt++;
    _reconnect = Timer(Duration(seconds: seconds), _connect);
  }

  Future<void> stop() async {
    _closed = true;
    _reconnecting = false;
    _reconnect?.cancel();
    _watchdog?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
  }
}
