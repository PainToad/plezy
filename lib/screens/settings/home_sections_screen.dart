import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/dpad_reorder_mixin.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../providers/discover_provider.dart';
import '../../services/settings_service.dart';
import '../../utils/home_sections.dart';
import '../../widgets/app_icon.dart';

class HomeSectionsScreen extends StatefulWidget {
  const HomeSectionsScreen({super.key});

  @override
  State<HomeSectionsScreen> createState() => _HomeSectionsScreenState();
}

class _HomeSectionsScreenState extends State<HomeSectionsScreen>
    with DpadReorderListMixin<MediaHub, HomeSectionsScreen> {
  final _focusNode = FocusNode(debugLabel: 'home_sections');
  final _scrollController = ScrollController();
  List<MediaHub> _sections = [];
  late final DiscoverProvider _discover;
  late Set<String> _hidden;
  late List<String> _savedOrder;

  @override
  List<MediaHub> get reorderItems => _sections;
  @override
  set reorderItems(List<MediaHub> value) => _sections = value;
  @override
  int get lastReorderColumn => 1;
  @override
  ScrollController get reorderScrollController => _scrollController;
  @override
  void onReorderMoveConfirmed() => _save();
  @override
  void onReorderColumnActivated(int column, int index) => _toggle(index);

  @override
  void initState() {
    super.initState();
    final settings = SettingsService.instance;
    _savedOrder = List.of(settings.read(SettingsService.homeSectionOrder));
    _hidden = settings.read(SettingsService.hiddenHomeSections).toSet();
    _discover = context.read<DiscoverProvider>();
    _discover.addListener(_refreshSections);
    _refreshSections();
  }

  void _refreshSections() {
    if (movingIndex != null) return;
    final discover = _discover;
    final seen = <String>{};
    final sections = arrangeHomeSections(
      [
        MediaHub(
          id: 'continue_watching',
          identifier: continueWatchingSectionKey,
          title: t.discover.continueWatching,
          type: 'mixed',
          items: const [],
        ),
        ...discover.hubs,
      ].where((hub) => seen.add(homeSectionKey(hub))).toList(),
      _savedOrder,
      const [],
    );
    if (mounted) setState(() => _sections = sections);
  }

  void _save() {
    // Keep temporarily unavailable rows in the saved sequence, in their slots.
    final visibleKeys = _sections.map(homeSectionKey).toList();
    final active = visibleKeys.toSet();
    final reordered = visibleKeys.iterator;
    final order = <String>[
      for (final key in _savedOrder)
        if (!active.contains(key)) key else if (reordered.moveNext()) reordered.current,
    ];
    while (reordered.moveNext()) {
      order.add(reordered.current);
    }
    _savedOrder = order;
    final hidden = _hidden.toList();
    final settings = SettingsService.instance;
    unawaited(settings.write(SettingsService.homeSectionOrder, order));
    unawaited(settings.write(SettingsService.hiddenHomeSections, hidden));
  }

  void _toggle(int index) {
    final key = homeSectionKey(_sections[index]);
    setState(() {
      if (!_hidden.remove(key)) _hidden.add(key);
    });
    _save();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() => _sections.insert(newIndex, _sections.removeAt(oldIndex)));
    _save();
  }

  @override
  void dispose() {
    _discover.removeListener(_refreshSections);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = InputModeTracker.isKeyboardMode(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Home screen sections')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Drag to reorder sections. Use the eye button to hide or show a section. On TV, select a row to move it; press Right to change visibility.',
            ),
          ),
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              autofocus: keyboard,
              descendantsAreFocusable: !keyboard,
              onKeyEvent: keyboard ? handleReorderKeyEvent : null,
              child: ReorderableListView.builder(
                scrollController: _scrollController,
                onReorderItem: _reorder,
                itemCount: _sections.length,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final section = _sections[index];
                  final shown = !_hidden.contains(homeSectionKey(section));
                  final selected = keyboard && index == focusedIndex;
                  return ListTile(
                    key: ValueKey(homeSectionKey(section)),
                    selected: selected,
                    selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: AppIcon(movingIndex == index ? Symbols.swap_vert_rounded : Symbols.drag_handle_rounded),
                    ),
                    title: Text(section.title),
                    subtitle: Text(shown ? 'Shown' : 'Hidden'),
                    onTap: () => _toggle(index),
                    trailing: IconButton(
                      tooltip: shown ? 'Hide section' : 'Show section',
                      icon: AppIcon(shown ? Symbols.visibility_rounded : Symbols.visibility_off_rounded),
                      color: selected && focusedColumn == 1 ? Theme.of(context).colorScheme.primary : null,
                      onPressed: () => _toggle(index),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
