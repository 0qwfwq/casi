import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';

class ScreenDock extends StatelessWidget {
  final bool isDragging;
  final bool showApps;

  final void Function(AppInfo)? onRemove;
  final void Function(AppInfo)? onUninstall;

  final Widget? activePill;

  final Map<int, AppInfo> homeApps;
  final int maxHomeApps;
  final void Function(int index, AppInfo app)? onAppDropped;
  final void Function(AppInfo app)? onAppTap;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  const ScreenDock({
    super.key,
    this.isDragging = false,
    this.showApps = true,
    this.onRemove,
    this.onUninstall,
    this.activePill,
    this.homeApps = const {},
    this.maxHomeApps = 7,
    this.onAppDropped,
    this.onAppTap,
    this.onDragStarted,
    this.onDragEnded,
  });

  Widget _buildAppIcon(AppInfo app, double iconSize) {
    final hasIcon = app.icon != null && app.icon!.isNotEmpty;
    return hasIcon
        ? Image.memory(
            app.icon!,
            width: iconSize,
            height: iconSize,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.android, color: Colors.white, size: iconSize),
          )
        : Icon(Icons.android, color: Colors.white, size: iconSize);
  }

  Widget _buildHomeAppRow() {
    final appCount = homeApps.length;
    if (appCount == 0) return const SizedBox.shrink();

    double iconSize;
    double spacing;
    if (appCount <= 2) {
      iconSize = 44.0;
      spacing = 6.0;
    } else if (appCount <= 5) {
      iconSize = 38.0;
      spacing = 6.0;
    } else {
      iconSize = 38.0;
      spacing = 3.0;
    }

    final sortedEntries = homeApps.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: sortedEntries.map((entry) {
        final app = entry.value;
        final index = entry.key;
        return DragTarget<AppInfo>(
          onAcceptWithDetails: (details) =>
              onAppDropped?.call(index, details.data),
          builder: (context, candidateData, rejectedData) {
            return LongPressDraggable<AppInfo>(
              data: app,
              onDragStarted: () => onDragStarted?.call(),
              onDragEnd: (_) => onDragEnded?.call(),
              feedback: Material(
                color: Colors.transparent,
                child: _buildAppIcon(app, iconSize),
              ),
              childWhenDragging: SizedBox(width: iconSize + spacing * 2, height: iconSize),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing),
                child: InkWell(
                  onTap: () => onAppTap?.call(app),
                  borderRadius: BorderRadius.circular(12),
                  child: _buildAppIcon(app, iconSize),
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildDragTargets() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          DragTarget<AppInfo>(
            onAcceptWithDetails: (details) => onRemove?.call(details.data),
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isHovered
                      ? Colors.red.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text("Remove", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              );
            },
          ),
          DragTarget<AppInfo>(
            onAcceptWithDetails: (details) => onUninstall?.call(details.data),
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isHovered
                      ? Colors.orange.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text("Uninstall", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40.0, 0, 40.0, 40.0),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Active pill (clock/alarm/timer/calendar)
            AnimatedOpacity(
              opacity: isDragging ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: IgnorePointer(
                ignoring: isDragging,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 100),
                    transitionBuilder: (child, animation) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.5),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOutQuart)),
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: activePill != null
                        ? KeyedSubtree(
                            key: const ValueKey('active_pill'),
                            child: activePill!,
                          )
                        : const SizedBox.shrink(key: ValueKey('empty_pill')),
                  ),
                ),
              ),
            ),

            // Home app row + drag targets
            AnimatedOpacity(
              opacity: showApps ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 100),
              child: IgnorePointer(
                ignoring: !showApps,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDragging) _buildDragTargets(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: _buildHomeAppRow(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
