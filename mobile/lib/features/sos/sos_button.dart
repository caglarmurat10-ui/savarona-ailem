import 'package:flutter/material.dart';

class SosButton extends StatefulWidget {
  const SosButton({super.key, required this.onSos});
  final Future<void> Function() onSos;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 2);
  late final AnimationController _hold = AnimationController(vsync: this, duration: _holdDuration);
  bool _sending = false;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _onHoldStart() async {
    if (_sending) return;
    await _hold.forward(from: 0);
    if (!mounted || _hold.value < 1.0) return;
    setState(() => _sending = true);
    try {
      await widget.onSos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOS aileye iletildi')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onHoldCancel() {
    if (_hold.isAnimating) _hold.stop();
    if (_hold.value < 1.0) _hold.reset();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _onHoldStart(),
      onTapUp: (_) => _onHoldCancel(),
      onTapCancel: _onHoldCancel,
      child: AnimatedBuilder(
        animation: _hold,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 58,
              child: FilledButton.icon(
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  disabledBackgroundColor: Theme.of(context).colorScheme.error,
                  disabledForegroundColor: Theme.of(context).colorScheme.onError,
                ),
                icon: const Icon(Icons.sos_rounded),
                label: Text(_sending ? 'Gönderiliyor…' : 'SOS — 2 SANİYE BASILI TUT'),
              ),
            ),
            if (_hold.value > 0 && _hold.value < 1.0)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _hold.value,
                  child: Container(color: Colors.white.withValues(alpha: 0.35)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
