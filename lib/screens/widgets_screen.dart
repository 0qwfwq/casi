import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/models/widget_items.dart';
import 'package:casi/widgets/widget_screen_pills.dart';
import 'package:casi/widgets/alarm_creator.dart';
import 'package:casi/widgets/timer_creator.dart';
import 'package:casi/services/wallpaper_service.dart';

// Identifies a draggable item by its type and index within the parent's
// alarm/timer list. The index is stable for the duration of a drag.
// The Weather widget is a singleton pill (no list) — its index is unused.
class _WidgetRef {
  final String type; // 'alarm' | 'timer' | 'weather'
  final int index;
  const _WidgetRef(this.type, this.index);
}

enum _HoverZone { none, active, inactive, delete }

class WidgetsScreen extends StatefulWidget {
  final List<AppAlarm> alarms;
  final List<AppTimer> timers;
  final bool weatherActive;

  // Mutations are pushed to the parent which owns persistence. The parent
  // re-passes updated lists via constructor on rebuild.
  final void Function(int index, bool isActive) onSetAlarmActive;
  final void Function(int index, bool isActive) onSetTimerActive;
  final void Function(bool isActive) onSetWeatherActive;
  final void Function(int index) onDeleteAlarm;
  final void Function(int index) onDeleteTimer;
  final void Function(int fromIndex, int toIndex) onReorderAlarm;
  final void Function(int fromIndex, int toIndex) onReorderTimer;
  final void Function(List<String> labels) onCreateAlarms;
  final void Function(int totalSeconds) onCreateTimer;

  const WidgetsScreen({
    super.key,
    required this.alarms,
    required this.timers,
    required this.weatherActive,
    required this.onSetAlarmActive,
    required this.onSetTimerActive,
    required this.onSetWeatherActive,
    required this.onDeleteAlarm,
    required this.onDeleteTimer,
    required this.onReorderAlarm,
    required this.onReorderTimer,
    required this.onCreateAlarms,
    required this.onCreateTimer,
  });

  @override
  State<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends State<WidgetsScreen> {
  _HoverZone _hover = _HoverZone.none;
  bool _isDragging = false;
  bool _isAddMenuOpen = false;
  // Creator popup: 'alarm' | 'timer' | null
  String? _creatorMode;

  // Wallpaper used as the refraction source for every liquid-glass pill
  // rendered inside this screen. Initialized once and reused — every pill
  // call site reads from [_wallpaperService.buildBackground].
  final WallpaperService _wallpaperService = WallpaperService();

  // Local mirror of the weather pill's active flag. Alarms/timers are
  // mutable objects in a list we hold by reference, so filtering them
  // always reflects current state; a plain bool captured from the parent
  // would stay frozen after this route was pushed, so we track it here.
  late bool _weatherActive = widget.weatherActive;

  static const int _maxAlarms = 9;
  static const int _maxTimers = 9;

  bool get _atAlarmLimit => widget.alarms.length >= _maxAlarms;
  bool get _atTimerLimit => widget.timers.length >= _maxTimers;

  List<AppAlarm> get _activeAlarms =>
      widget.alarms.where((a) => a.isActive).toList();
  List<AppAlarm> get _inactiveAlarms =>
      widget.alarms.where((a) => !a.isActive).toList();
  List<AppTimer> get _activeTimers =>
      widget.timers.where((t) => t.isActive).toList();
  List<AppTimer> get _inactiveTimers =>
      widget.timers.where((t) => !t.isActive).toList();

  int _alarmGlobalIndex(AppAlarm a) =>
      widget.alarms.indexWhere((x) => identical(x, a));
  int _timerGlobalIndex(AppTimer t) =>
      widget.timers.indexWhere((x) => identical(x, t));

  @override
  void initState() {
    super.initState();
    _wallpaperService.initialize();
  }

  @override
  void dispose() {
    _wallpaperService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Blurred wallpaper behind everything. The parent pushes this
          // screen over the home route, so the wallpaper shows through.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSection(
                            title: "Active",
                            zone: _HoverZone.active,
                            alarms: _activeAlarms,
                            timers: _activeTimers,
                            includeWeather: _weatherActive,
                            isActiveSection: true,
                          ),
                          const SizedBox(height: 28),
                          _buildSection(
                            title: "Inactive",
                            zone: _HoverZone.inactive,
                            alarms: _inactiveAlarms,
                            timers: _inactiveTimers,
                            includeWeather: !_weatherActive,
                            isActiveSection: false,
                          ),
                          SizedBox(height: screenHeight * 0.1),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom-right: add/delete circular button
          Positioned(
            right: 24,
            bottom: 24 + media.padding.bottom,
            child: _buildAddOrDeleteButton(),
          ),
          // Add menu sits above the + button. Hosted at the scaffold level
          // (not inside the button's Stack) so its hit-test bounds aren't
          // clipped by the 56×56 button frame.
          if (_isAddMenuOpen && !_isDragging && _creatorMode == null)
            Positioned(
              right: 24,
              bottom: 24 + media.padding.bottom + 70,
              child: _buildAddMenu(),
            ),
          // Bottom-left: glass back button
          Positioned(
            left: 24,
            bottom: 24 + media.padding.bottom,
            child: _buildCheckButton(),
          ),
          // Creator overlay
          if (_creatorMode != null) _buildCreatorPopup(screenHeight),
        ],
      ),
    );
  }

  // ─── Sections ──────────────────────────────────────────────────────────

  Widget _buildSection({
    required String title,
    required _HoverZone zone,
    required List<AppAlarm> alarms,
    required List<AppTimer> timers,
    required bool includeWeather,
    required bool isActiveSection,
  }) {
    final hasContent =
        alarms.isNotEmpty || timers.isNotEmpty || includeWeather;
    final showingGhost = _isDragging && _hover == zone;
    final ghostColor =
        isActiveSection ? CASIColors.confirm : CASIColors.alert;

    return DragTarget<_WidgetRef>(
      onWillAcceptWithDetails: (details) {
        setState(() => _hover = zone);
        return true;
      },
      onLeave: (_) {
        if (_hover == zone) setState(() => _hover = _HoverZone.none);
      },
      onAcceptWithDetails: (details) {
        _handleSectionDrop(details.data, isActiveSection);
      },
      builder: (context, candidateData, rejectedData) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (!hasContent && !showingGhost)
                _buildEmptyHint(isActiveSection)
              else
                _buildPillGrid(
                  alarms: alarms,
                  timers: timers,
                  includeWeather: includeWeather,
                  showGhost: showingGhost,
                  ghostColor: ghostColor,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyHint(bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        isActive
            ? "Drag widgets here to show them on your home screen."
            : "Inactive widgets are hidden from the home screen.",
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildPillGrid({
    required List<AppAlarm> alarms,
    required List<AppTimer> timers,
    required bool includeWeather,
    required bool showGhost,
    required Color ghostColor,
  }) {
    // Build the ordered list of tiles (alarms first, then timers — matches
    // grouping in the home schedule row). The Weather pill, when present
    // in this section, sits at the end so it never displaces user-created
    // pills.
    final tiles = <Widget>[];

    for (final a in alarms) {
      final globalIdx = _alarmGlobalIndex(a);
      tiles.add(_draggableAlarmTile(a, globalIdx));
    }
    for (final t in timers) {
      final globalIdx = _timerGlobalIndex(t);
      tiles.add(_draggableTimerTile(t, globalIdx));
    }
    if (includeWeather) {
      tiles.add(_draggableWeatherTile());
    }
    if (showGhost) {
      tiles.add(GhostPill(color: ghostColor));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += 2) {
          final left = tiles[i];
          final right = i + 1 < tiles.length ? tiles[i + 1] : null;
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              children: [
                SizedBox(width: tileWidth, child: left),
                const SizedBox(width: gap),
                SizedBox(
                  width: tileWidth,
                  child: right ?? const SizedBox.shrink(),
                ),
              ],
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }

  Widget _draggableAlarmTile(AppAlarm alarm, int globalIndex) {
    final ref = _WidgetRef('alarm', globalIndex);
    return _wrapAsDraggable(
      ref: ref,
      pill: WidgetScreenAlarmPill(
        alarm: alarm,
        backgroundWidget: _wallpaperService.buildBackground(),
      ),
    );
  }

  Widget _draggableTimerTile(AppTimer timer, int globalIndex) {
    final ref = _WidgetRef('timer', globalIndex);
    return _wrapAsDraggable(
      ref: ref,
      pill: WidgetScreenTimerPill(
        timer: timer,
        backgroundWidget: _wallpaperService.buildBackground(),
      ),
    );
  }

  // Weather is a singleton widget — there's no list, so the index is
  // unused. It uses the same drag mechanics as other pills, but the
  // bottom-right delete drop zone refuses it (see _buildAddOrDeleteButton).
  Widget _draggableWeatherTile() {
    const ref = _WidgetRef('weather', 0);
    return _wrapAsDraggable(
      ref: ref,
      pill: WidgetScreenWeatherPill(
        backgroundWidget: _wallpaperService.buildBackground(),
      ),
    );
  }

  Widget _wrapAsDraggable({
    required _WidgetRef ref,
    required Widget pill,
  }) {
    // DragTarget nesting: each pill is itself a drop target so that
    // dropping another pill onto it performs an in-section swap.
    return DragTarget<_WidgetRef>(
      onWillAcceptWithDetails: (details) {
        // Only accept for swap if same type (alarm↔alarm, timer↔timer)
        // and different index. Section change is handled by the section
        // DragTarget, so we only intercept same-section swaps here.
        final other = details.data;
        if (other.type != ref.type) return false;
        if (other.index == ref.index) return false;
        return _sameSection(ref, other);
      },
      onAcceptWithDetails: (details) {
        _handleSwap(details.data, ref);
      },
      builder: (context, candidate, rejected) {
        return LongPressDraggable<_WidgetRef>(
          data: ref,
          delay: const Duration(milliseconds: 200),
          onDragStarted: () => setState(() => _isDragging = true),
          onDragEnd: (_) => setState(() {
            _isDragging = false;
            _hover = _HoverZone.none;
          }),
          onDraggableCanceled: (_, _) => setState(() {
            _isDragging = false;
            _hover = _HoverZone.none;
          }),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.9,
              child: SizedBox(
                width: _pillFeedbackWidth(context),
                child: pill,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: pill),
          child: pill,
        );
      },
    );
  }

  double _pillFeedbackWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return (w - 80 - 12) / 2;
  }

  bool _sameSection(_WidgetRef a, _WidgetRef b) {
    return _refIsActive(a) == _refIsActive(b);
  }

  bool _refIsActive(_WidgetRef ref) {
    switch (ref.type) {
      case 'alarm':
        return widget.alarms[ref.index].isActive;
      case 'timer':
        return widget.timers[ref.index].isActive;
      case 'weather':
        return _weatherActive;
    }
    return false;
  }

  void _handleSectionDrop(_WidgetRef ref, bool isActive) {
    switch (ref.type) {
      case 'alarm':
        widget.onSetAlarmActive(ref.index, isActive);
        break;
      case 'timer':
        widget.onSetTimerActive(ref.index, isActive);
        break;
      case 'weather':
        setState(() => _weatherActive = isActive);
        widget.onSetWeatherActive(isActive);
        break;
    }
  }

  void _handleSwap(_WidgetRef from, _WidgetRef to) {
    if (from.type != to.type) return;
    if (from.type == 'alarm') {
      widget.onReorderAlarm(from.index, to.index);
    } else {
      widget.onReorderTimer(from.index, to.index);
    }
  }

  // ─── Bottom-left: + / - / delete drop zone ────────────────────────────

  Widget _buildAddOrDeleteButton() {
    return DragTarget<_WidgetRef>(
      // Refuse Weather drops — the Weather widget is permanent and can
      // only move between Active and Inactive.
      onWillAcceptWithDetails: (details) {
        if (details.data.type == 'weather') return false;
        setState(() => _hover = _HoverZone.delete);
        return true;
      },
      onLeave: (_) {
        if (_hover == _HoverZone.delete) {
          setState(() => _hover = _HoverZone.none);
        }
      },
      onAcceptWithDetails: (details) {
        if (details.data.type == 'alarm') {
          widget.onDeleteAlarm(details.data.index);
        } else if (details.data.type == 'timer') {
          widget.onDeleteTimer(details.data.index);
        }
      },
      builder: (context, candidate, rejected) {
        final isDelete = _isDragging;
        return GestureDetector(
          onTap: () {
            if (isDelete) return;
            if (_creatorMode != null) return;
            setState(() => _isAddMenuOpen = !_isAddMenuOpen);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isDelete
                      ? CASIColors.alert
                      : CASIColors.accentPrimary)
                  .withValues(alpha: 0.2),
              border: Border.all(
                color: (isDelete
                        ? CASIColors.alert
                        : CASIColors.accentPrimary)
                    .withValues(alpha: 0.65),
                width: 1.5,
              ),
            ),
            child: Icon(
              isDelete
                  ? Icons.delete_outline_rounded
                  : Icons.add_rounded,
              color: isDelete
                  ? CASIColors.alert
                  : CASIColors.accentPrimary,
              size: isDelete ? 28 : 30,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _addMenuItem(
          label: "Alarm",
          icon: Icons.alarm,
          color: CASIColors.confirm,
          enabled: !_atAlarmLimit,
          onTap: () {
            setState(() {
              _isAddMenuOpen = false;
              _creatorMode = 'alarm';
            });
          },
        ),
        const SizedBox(height: 10),
        _addMenuItem(
          label: "Timer",
          icon: Icons.hourglass_empty,
          color: CASIColors.caution,
          enabled: !_atTimerLimit,
          onTap: () {
            setState(() {
              _isAddMenuOpen = false;
              _creatorMode = 'timer';
            });
          },
        ),
      ],
    );
  }

  Widget _addMenuItem({
    required String label,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: GlassSurface.pill(
        cornerRadius: 26,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: enabled ? color : CASIColors.textTertiary, size: 20),
            const SizedBox(width: 10),
            Text(
              enabled ? label : "$label (max)",
              style: TextStyle(
                color: enabled ? Colors.white : CASIColors.textTertiary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bottom-right: close button ───────────────────────────────────────

  Widget _buildCheckButton() {
    return GestureDetector(
      onTap: () {
        if (_creatorMode != null) {
          setState(() => _creatorMode = null);
          return;
        }
        Navigator.of(context).maybePop();
      },
      child: GlassSurface.pill(
        cornerRadius: 28,
        width: 56,
        height: 56,
        child: const Center(
          child: Icon(
            Icons.chevron_left_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  // ─── Creator overlay ──────────────────────────────────────────────────

  Widget _buildCreatorPopup(double screenHeight) {
    final popupHeight = screenHeight * 0.5;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _creatorMode = null),
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: SizedBox(
                height: popupHeight,
                child: GlassSurface.modal(
                  cornerRadius: 32,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: _creatorMode == 'alarm'
                      ? AlarmCreator(
                          onSave: (labels) {
                            widget.onCreateAlarms(labels);
                            setState(() => _creatorMode = null);
                          },
                          onCancel: () =>
                              setState(() => _creatorMode = null),
                        )
                      : TimerCreator(
                          onSave: (total) {
                            widget.onCreateTimer(total);
                            setState(() => _creatorMode = null);
                          },
                          onCancel: () =>
                              setState(() => _creatorMode = null),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
