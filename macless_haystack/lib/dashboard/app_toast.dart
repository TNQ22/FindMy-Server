import 'dart:async';
import 'package:flutter/material.dart';

class AppToast {
  static OverlayEntry? _currentEntry;
  static _ToastWidgetState? _currentWidgetState;

  static void show(
    BuildContext context, {
    required Widget content,
    IconData? icon,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Immediately remove previous entry so animations don't clobber each other
    if (_currentEntry != null) {
      try {
        _currentEntry!.remove();
      } catch (_) {}
      _currentEntry = null;
      _currentWidgetState = null;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ?? (isDark ? Colors.grey.shade900 : Colors.teal.shade800);

    late OverlayEntry newEntry;
    newEntry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        key: UniqueKey(),
        content: content,
        icon: icon,
        backgroundColor: bg,
        duration: duration,
        onRemove: () {
          try {
            newEntry.remove();
          } catch (_) {}
          if (_currentEntry == newEntry) {
            _currentEntry = null;
            _currentWidgetState = null;
          }
        },
        onStateCreated: (state) {
          if (_currentEntry == newEntry) {
            _currentWidgetState = state;
          }
        },
      ),
    );

    _currentEntry = newEntry;
    overlay.insert(newEntry);
  }

  static void showText(
    BuildContext context,
    String text, {
    IconData? icon,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      context,
      content: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      icon: icon,
      backgroundColor: backgroundColor,
      duration: duration,
    );
  }

  static void dismiss() {
    if (_currentWidgetState != null && _currentWidgetState!.mounted) {
      _currentWidgetState!.fadeOutAndRemove();
    } else {
      if (_currentEntry != null) {
        try {
          _currentEntry!.remove();
        } catch (_) {}
        _currentEntry = null;
        _currentWidgetState = null;
      }
    }
  }
}

class _ToastWidget extends StatefulWidget {
  final Widget content;
  final IconData? icon;
  final Color backgroundColor;
  final Duration duration;
  final VoidCallback onRemove;
  final void Function(_ToastWidgetState state)? onStateCreated;

  const _ToastWidget({
    super.key,
    required this.content,
    this.icon,
    required this.backgroundColor,
    required this.duration,
    required this.onRemove,
    this.onStateCreated,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  Timer? _timer;
  bool _isHovered = false;
  int _activePointers = 0;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call(this);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward();
    _startDismissTimer(widget.duration);
  }

  void _startDismissTimer(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () {
      if (!_isHovered && _activePointers == 0 && mounted) {
        fadeOutAndRemove();
      }
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _resumeTimer() {
    if (!_isHovered && _activePointers == 0) {
      _startDismissTimer(const Duration(milliseconds: 2500));
    }
  }

  void fadeOutAndRemove() {
    if (_isDismissing) return;
    _isDismissing = true;
    _timer?.cancel();
    if (!mounted) {
      widget.onRemove();
      return;
    }
    _animController.reverse().then((_) {
      widget.onRemove();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: bottomPadding > 0 ? bottomPadding + 65 : 75,
      left: 16,
      right: 16,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: MouseRegion(
                onEnter: (_) {
                  _isHovered = true;
                  _pauseTimer();
                },
                onExit: (_) {
                  _isHovered = false;
                  _resumeTimer();
                },
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) {
                    _activePointers++;
                    _pauseTimer();
                  },
                  onPointerUp: (_) {
                    _activePointers = (_activePointers - 1).clamp(0, 99);
                    if (_activePointers == 0) {
                      _resumeTimer();
                    }
                  },
                  onPointerCancel: (_) {
                    _activePointers = (_activePointers - 1).clamp(0, 99);
                    if (_activePointers == 0) {
                      _resumeTimer();
                    }
                  },
                  child: Dismissible(
                    key: const Key('app_toast_dismissible'),
                    direction: DismissDirection.horizontal,
                    onDismissed: (_) {
                      widget.onRemove();
                    },
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: widget.backgroundColor.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: widget.content,
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: fadeOutAndRemove,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  color: Colors.white.withOpacity(0.85),
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
