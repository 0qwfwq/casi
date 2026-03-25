import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:casi/design_system.dart';

class ScreenDock extends StatelessWidget {
  final bool isDragging;
  final bool showApps;

  final void Function(AppInfo)? onRemove;
  final void Function(AppInfo)? onUninstall;
  final VoidCallback? onCancel;

  final Widget? activePill;

  final Map<int, AppInfo> homeApps;
  final int maxHomeApps;
  final void Function(int index, AppInfo app)? onAppDropped;
  final void Function(AppInfo app)? onAppTap;
  final void Function(AppInfo app)? onDragStarted;
  final AppInfo? draggingApp;

  const ScreenDock({
    super.key,
    this.isDragging = false,
    this.showApps = true,
    this.onRemove,
    this.onUninstall,
    this.onCancel,
    this.activePill,
    this.homeApps = const {},
    this.maxHomeApps = 7,
    this.onAppDropped,
    this.onAppTap,
    this.onDragStarted,
    this.draggingApp,
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
                Icon(Icons.android, color: CASIColors.textPrimary, size: iconSize),
          )
        : Icon(Icons.android, color: CASIColors.textPrimary, size: iconSize);
  }

  Widget _buildHomeAppRow() {
    final appCount = homeApps.length;
    if (appCount == 0) return const SizedBox.shrink();

    double iconSize;
    double spacing;
    if (appCount <= 2) {
      iconSize = 44.0;
      spacing = CASISpacing.sm;
    } else if (appCount <= 5) {
      iconSize = 38.0;
      spacing = CASISpacing.sm;
    } else {
      iconSize = 38.0;
      spacing = CASISpacing.xs;
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
              onDragStarted: () => onDragStarted?.call(app),
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
          _buildGlassDragTarget(
            onAccept: (app) => onRemove?.call(app),
            onTap: draggingApp != null ? () => onRemove?.call(draggingApp!) : null,
            icon: Icons.close,
            label: 'Remove',
            hoverColor: CASIColors.alert,
          ),
          _buildCancelTarget(),
          _buildGlassDragTarget(
            onAccept: (app) => onUninstall?.call(app),
            onTap: draggingApp != null ? () => onUninstall?.call(draggingApp!) : null,
            icon: Icons.delete_outline,
            label: 'Uninstall',
            hoverColor: CASIColors.caution,
          ),
        ],
      ),
    );
  }

  Widget _buildCancelTarget() {
    return DragTarget<AppInfo>(
      onAcceptWithDetails: (_) => onCancel?.call(),
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: () => onCancel?.call(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: CASIGlass.blurStandard,
                sigmaY: CASIGlass.blurStandard,
              ),
              child: AnimatedContainer(
                duration: CASIMotion.micro,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isHovered
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    color: isHovered ? CASIColors.textPrimary : CASIColors.textSecondary,
                    size: CASIIcons.small,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassDragTarget({
    required void Function(AppInfo) onAccept,
    VoidCallback? onTap,
    required IconData icon,
    required String label,
    required Color hoverColor,
  }) {
    return DragTarget<AppInfo>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(
          borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: CASIGlass.blurStandard,
              sigmaY: CASIGlass.blurStandard,
            ),
            child: AnimatedContainer(
              duration: CASIMotion.micro,
              padding: const EdgeInsets.symmetric(
                horizontal: CASISpacing.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: isHovered
                    ? hoverColor.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
                border: Border.all(
                  color: isHovered
                      ? hoverColor.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: CASIElevation.card.borderAlpha),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isHovered ? hoverColor : CASIColors.textSecondary,
                    size: CASIIcons.small,
                  ),
                  const SizedBox(width: CASISpacing.sm),
                  Text(
                    label,
                    style: CASITypography.body2.copyWith(
                      color: isHovered ? hoverColor : CASIColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CASISpacing.xl + CASISpacing.sm,
        0,
        CASISpacing.xl + CASISpacing.sm,
        CASISpacing.xl + CASISpacing.sm,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Active pill (clock/alarm/timer/calendar)
            AnimatedOpacity(
              opacity: isDragging ? 0.0 : 1.0,
              duration: CASIMotion.micro,
              child: IgnorePointer(
                ignoring: isDragging,
                child: AnimatedSize(
                  duration: CASIMotion.micro,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSwitcher(
                    duration: CASIMotion.micro,
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
              duration: CASIMotion.micro,
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
