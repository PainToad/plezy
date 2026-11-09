import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../../focus/focusable_action_bar.dart';
import '../../focus/input_mode_tracker.dart';
import '../../navigation/main_screen_scope.dart';
import '../../mixins/tab_visibility_aware.dart';
import '../../media/ids.dart';
import '../../media/media_library.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings_builder.dart';
import '../../utils/app_logger.dart';
import '../../utils/platform_detector.dart';
import '../../utils/content_utils.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/library_management_sheet.dart';
import '../../services/media_list_playback_launcher.dart';
import '../../services/storage_service.dart';
import '../../mixins/refreshable.dart';
import '../../i18n/strings.g.dart';
import 'library_server_label.dart';
import 'state_messages.dart';
import 'tabs/library_browse_tab.dart';
import 'tabs/base_library_tab.dart';

enum LibraryTabType { recommended, browse, collections, playlists, genres }

/// Library pages expose Browse only, including shared and music libraries.
List<LibraryTabType> visibleLibraryTabs(MediaLibrary library) => const [LibraryTabType.browse];

class LibrariesScreen extends StatefulWidget {
  final VoidCallback? onLibraryOrderChanged;
  final ValueChanged<String>? onLibrarySelected;

  const LibrariesScreen({super.key, this.onLibraryOrderChanged, this.onLibrarySelected});

  @override
  State<LibrariesScreen> createState() => _LibrariesScreenState();
}

class _LibrariesScreenState extends State<LibrariesScreen>
    with Refreshable, ManualRefreshable, FullRefreshable, FocusableTab, LibraryLoadable, TabVisibilityAware {
  final _browseTabKey = GlobalKey();

  String? _selectedLibraryGlobalKey;

  bool suppressAutoFocus = false;

  /// Whether a post-frame [_initializeWithLibraries] is already queued.
  bool _initializeScheduled = false;

  /// Track which tabs have loaded data (used to trigger focus after tab restore)
  final Set<int> _loadedTabs = {};

  /// Whether the browse tab has active filters (badges the Library options icon)
  bool _browseFiltersActive = false;

  final _libraryDropdownKey = GlobalKey<AppMenuButtonState<String>>();

  final _actionBarKey = GlobalKey<FocusableActionBarState>();

  final ScrollController _outerScrollController = ScrollController();

  /// Reveal the floating header by jumping the outer NestedScrollView back
  /// to offset 0. The outer position is preserved across content changes
  /// (library switch, library reload, filter/sort change), so any time the
  /// inner is reset to the top we must explicitly resync the outer — the
  /// natural delta-surrender coordination only fires on user scroll gestures.
  ///
  /// Iterates `positions` rather than reading `offset` because the controller
  /// is shared between the simple CustomScrollView (loading/empty/error) and
  /// the NestedScrollView (selected library), and during the transition both
  /// can briefly be attached — `offset` would throw on `_positions.single`.
  void _resetOuterScroll() {
    if (!_outerScrollController.hasClients) return;
    for (final position in _outerScrollController.positions) {
      if (position.pixels > 0) {
        position.jumpTo(0);
      }
    }
  }

  /// Return from Browse to the visible library toolbar.
  void focusTabBar() {
    setState(() => suppressAutoFocus = true);
    _resetOuterScroll();
    _actionBarKey.currentState?.requestFocusOnFirst();
  }

  @override
  void initState() {
    super.initState();

    _scheduleInitializeWithLibraries();
  }

  /// Run [_initializeWithLibraries] after the current frame, at most once per
  /// frame. Besides the mount, the build schedules it whenever libraries are
  /// on hand but none is selected: a first load that found none returns early,
  /// and nothing else selects one when they arrive later — on phones the
  /// library dropdown only renders once a library is selected, so the body
  /// would stay blank.
  void _scheduleInitializeWithLibraries() {
    if (_initializeScheduled) return;
    _initializeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScheduled = false;
      if (!mounted) return;
      _initializeWithLibraries();
    });
  }

  /// Initialize the screen with libraries from the provider.
  /// This handles initial library selection and content loading.
  ///
  /// An existing selection is authoritative. A sidebar library selection that
  /// mounts this screen (`MainScreen._selectLibrary`) applies its target from a
  /// post-frame callback registered *before* the one in [initState], so this
  /// runs second and must not replace the requested library — which may be
  /// hidden, and so is never the saved or topmost-visible default — with a
  /// default. The re-checks cover the reverse interleaving, where a selection
  /// lands while this is suspended on an await ([refresh]'s stale-resume
  /// entry point).
  Future<void> _initializeWithLibraries() async {
    if (_selectedLibraryGlobalKey != null) return;

    final librariesProvider = context.read<LibrariesProvider>();
    final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
    await hiddenLibrariesProvider.ensureInitialized();
    if (!mounted || _selectedLibraryGlobalKey != null) return;
    final allLibraries = librariesProvider.libraries;

    if (allLibraries.isEmpty) {
      // No libraries available yet
      return;
    }

    final hiddenKeys = hiddenLibrariesProvider.hiddenLibraryKeys;
    final visibleLibraries = allLibraries.where((lib) => !hiddenKeys.contains(lib.globalKey)).toList();

    final storage = await StorageService.getInstance();
    if (!mounted || _selectedLibraryGlobalKey != null) return;
    final savedLibraryKey = storage.getSelectedLibraryKey();

    String? libraryGlobalKeyToLoad;
    if (savedLibraryKey != null) {
      final libraryExists = visibleLibraries.any((lib) => lib.globalKey == savedLibraryKey);
      if (libraryExists) {
        libraryGlobalKeyToLoad = savedLibraryKey;
      }
    }

    if (libraryGlobalKeyToLoad == null && visibleLibraries.isNotEmpty) {
      libraryGlobalKeyToLoad = visibleLibraries.first.globalKey;
    }

    if (libraryGlobalKeyToLoad != null) {
      unawaited(_loadLibraryContent(libraryGlobalKeyToLoad));
    }
  }

  /// Focus the first item in the currently active tab.
  /// Used for initial load and tab switching - focuses the grid content directly.
  ///
  /// While loading, park focus on the toolbar until content arrives.
  void _focusCurrentTab({bool awaitLoad = false}) {
    if (!InputModeTracker.isKeyboardMode(context)) return;

    // Re-enable auto-focus since user is navigating into tab content
    // Only call setState if the value actually changes to avoid unnecessary rebuilds
    if (suppressAutoFocus) {
      setState(() {
        suppressAutoFocus = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tabState = _browseTabKey.currentState;
      if (tabState != null) {
        _focusTabContent(tabState, awaitLoad: awaitLoad);
      } else {
        // State not available yet, retry after another frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusCurrentTabImmediate(awaitLoad: awaitLoad);
        });
      }
    });
  }

  /// Focus without additional frame delay (used for retry)
  void _focusCurrentTabImmediate({bool awaitLoad = false}) {
    final tabState = _browseTabKey.currentState;
    if (tabState != null) {
      _focusTabContent(tabState, awaitLoad: awaitLoad);
    }
  }

  void _focusTabContent(State tabState, {required bool awaitLoad}) {
    // Keep automatic focus enabled while the toolbar holds focus during a load.
    if (awaitLoad && tabState is BaseLibraryTabState && tabState.isLoading) {
      _resetOuterScroll();
      _actionBarKey.currentState?.requestFocusOnFirst();
      return;
    }
    (tabState as dynamic).focusContentOrChrome();
  }

  void _showBrowseOptionsForCurrentTab() {
    final tabState = _browseTabKey.currentState;
    if (tabState != null) (tabState as dynamic).showBrowseOptionsSheet();
  }

  /// Handle when the browse tab's active-filter state changes
  void _handleBrowseFiltersActiveChanged(bool active) {
    if (_browseFiltersActive == active) return;
    setState(() => _browseFiltersActive = active);
  }

  /// Handle when a tab's data has finished loading
  void _handleTabDataLoaded(int tabIndex) {
    _loadedTabs.add(tabIndex);

    if (suppressAutoFocus) return;

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !suppressAutoFocus) {
          _focusCurrentTab();
        }
      });
    }
  }

  /// Called by parent when the Libraries screen becomes visible.
  /// If the active tab has already loaded data (often the case after preloading
  /// while on another main tab), re-request focus so the first item is focused
  /// once the screen is actually shown. A tab still loading gets its content
  /// focused when the load lands instead.
  @override
  void focusActiveTabIfReady() {
    if (_selectedLibraryGlobalKey == null) return;
    _focusCurrentTab(awaitLoad: true);
  }

  @override
  void dispose() {
    _outerScrollController.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Widget _buildBrowseContent(MediaLibrary library, {required bool canGroupByFolders}) {
    return LibraryBrowseTab(
      key: _browseTabKey,
      library: library,
      canGroupByFolders: canGroupByFolders,
      isActive: true,
      suppressAutoFocus: suppressAutoFocus,
      onDataLoaded: () => _handleTabDataLoaded(0),
      onBack: focusTabBar,
      onResetScroll: _resetOuterScroll,
      onFiltersActiveChanged: _handleBrowseFiltersActiveChanged,
    );
  }

  /// Notify parent that library order changed
  void _notifyLibraryOrderChanged() {
    widget.onLibraryOrderChanged?.call();
  }

  /// Public method to load a library by key (called from MainScreen side nav)
  @override
  void loadLibraryByKey(String libraryGlobalKey) {
    _loadLibraryContent(libraryGlobalKey);
  }

  Future<void> _loadLibraryContent(String libraryGlobalKey) async {
    final librariesProvider = context.read<LibrariesProvider>();
    final allLibraries = librariesProvider.libraries;

    // Resolve from allLibraries — hidden libraries are still navigable from the
    // sidebar's "Hidden libraries" section.
    final selectedLibrary = allLibraries.where((lib) => lib.globalKey == libraryGlobalKey).firstOrNull;
    if (selectedLibrary == null) return;

    final isLibraryChange = _selectedLibraryGlobalKey != libraryGlobalKey;

    _updateState(() {
      _selectedLibraryGlobalKey = libraryGlobalKey;
      _loadedTabs.clear();
    });
    widget.onLibrarySelected?.call(libraryGlobalKey);

    // Reveal the toolbar when switching libraries.
    if (isLibraryChange) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _resetOuterScroll();
      });
    }

    // Persist selection after the visible state is consistent.
    final storage = await StorageService.getInstance();
    if (!mounted || _selectedLibraryGlobalKey != libraryGlobalKey) return;
    await storage.saveSelectedLibraryKey(libraryGlobalKey);
    if (!mounted || _selectedLibraryGlobalKey != libraryGlobalKey) return;

    // Ignore saved tabs from earlier versions: every library opens Browse.
    // The Browse load may have finished while saving the library selection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedLibraryGlobalKey == libraryGlobalKey && _loadedTabs.contains(0)) {
        _focusCurrentTab();
      }
    });
  }

  /// Refetch content in place (stale-resume sweep from MainScreen, #2043).
  ///
  /// With a library on screen this refetches its instantiated tabs — the same
  /// action as the toolbar refresh button. Selecting the saved library again
  /// would not: the tab widgets are keyed on stable GlobalKeys and only reload
  /// when the library's globalKey changes. Without a selection yet (provider
  /// was empty at startup) it re-runs initialization instead.
  @override
  void refresh() {
    if (_selectedLibraryGlobalKey == null) {
      _initializeWithLibraries();
      return;
    }
    _refreshSelectedLibraryTabs();
  }

  /// Returning to the Libraries tab consumes push-marked staleness (#1646)
  /// for the visible library tab only; hidden tabs consume on their own
  /// activation, and a library switch reloads unconditionally anyway.
  @override
  void onTabShown() {
    if (_selectedLibraryGlobalKey == null) return;
    final Object? tabState = _browseTabKey.currentState;
    if (tabState is BaseLibraryTabState) tabState.refreshIfLibraryContentStale();
  }

  @override
  // ignore: no-empty-block - visibility mixin contract; nothing to pause.
  void onTabHidden() {}

  /// The toolbar refresh. Without a selected library the screen is showing the
  /// provider's empty or error state, and there are no tabs to refetch: reload
  /// the library list itself (the build selects one once they arrive).
  @override
  void manualRefresh() {
    if (_selectedLibraryGlobalKey == null) {
      unawaited(context.read<LibrariesProvider>().refresh());
      return;
    }
    _refreshSelectedLibraryTabs();
  }

  void _refreshSelectedLibraryTabs() {
    final Object? browse = _browseTabKey.currentState;
    if (browse is Refreshable) browse.refresh();
  }

  // Public method to fully reload all content (for profile switches)
  @override
  void fullRefresh() {
    appLogger.d('LibrariesScreen.fullRefresh() called - reloading all content');
    setState(() {
      _selectedLibraryGlobalKey = null;
    });

    // Reinitialize with current libraries from provider
    _initializeWithLibraries();
  }

  Future<void> _toggleLibraryVisibility(MediaLibrary library) async {
    if (!mounted) return;
    final librariesProvider = context.read<LibrariesProvider>();
    final hiddenLibrariesProvider = Provider.of<HiddenLibrariesProvider>(context, listen: false);
    final isHidden = hiddenLibrariesProvider.hiddenLibraryKeys.contains(library.globalKey);

    if (isHidden) {
      await hiddenLibrariesProvider.unhideLibrary(library.globalKey);
    } else {
      final isCurrentlySelected = _selectedLibraryGlobalKey == library.globalKey;

      await hiddenLibrariesProvider.hideLibrary(library.globalKey);

      // If we just hid the selected library, select the first visible one
      if (isCurrentlySelected) {
        // Compute visible libraries after hiding
        final allLibraries = librariesProvider.libraries;
        final visibleLibraries = allLibraries
            .where((lib) => !hiddenLibrariesProvider.hiddenLibraryKeys.contains(lib.globalKey))
            .toList();

        if (visibleLibraries.isNotEmpty) {
          unawaited(_loadLibraryContent(visibleLibraries.first.globalKey));
        }
      }
    }
  }

  void _showLibraryManagementSheet() {
    showLibraryManagementSheet(
      context,
      onOrderChanged: _notifyLibraryOrderChanged,
      onToggleVisibility: _toggleLibraryVisibility,
    );
  }

  AppMenuHeader<String> _buildLibraryServerHeaderMenuItem(MediaLibrary library, String serverKey) {
    return AppMenuHeader<String>(
      child: LibraryServerLabel(
        library: library,
        fallbackServerName: serverKey,
        badgeSize: 12,
        style: libraryServerHeaderStyle(context),
        constrainText: true,
      ),
    );
  }

  AppMenuItem<String> _buildLibraryMenuItem(MediaLibrary library, {required bool showServerName}) {
    final isSelected = library.globalKey == _selectedLibraryGlobalKey;
    return AppMenuItem<String>(
      value: library.globalKey,
      icon: ContentTypeHelper.getLibraryIcon(library.kind.id),
      label: library.title,
      selected: isSelected,
      subtitleWidget: showServerName
          ? LibraryServerLabel(
              library: library,
              badgeSize: 10,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              ),
              constrainText: true,
            )
          : null,
    );
  }

  /// Build dropdown menu entries via the shared server-label policy.
  List<AppMenuEntry<String>> _buildGroupedLibraryMenuItems(
    List<MediaLibrary> visibleLibraries, {
    required bool groupByServer,
  }) {
    return buildLibraryServerEntries<AppMenuEntry<String>>(
      visibleLibraries,
      groupByServer: groupByServer,
      buildHeader: _buildLibraryServerHeaderMenuItem,
      buildItem: (library, {required bool showServerName}) =>
          _buildLibraryMenuItem(library, showServerName: showServerName),
    );
  }

  /// Build the app bar title - either dropdown on mobile or simple title on desktop
  Widget _buildAppBarTitle(
    List<MediaLibrary> visibleLibraries,
    MediaLibrary? selectedLibrary, {
    required bool groupByServer,
  }) {
    // No selection at all, or visible list is empty AND we're not browsing a hidden library
    if (_selectedLibraryGlobalKey == null || (visibleLibraries.isEmpty && selectedLibrary == null)) {
      return Text(t.libraries.title);
    }

    if (PlatformDetector.shouldUseSideNavigation(context)) {
      return Text(selectedLibrary?.title ?? t.libraries.title);
    }

    // On mobile, show the dropdown
    return _buildLibraryDropdownTitle(visibleLibraries, groupByServer: groupByServer);
  }

  Widget _buildLibraryDropdownTitle(List<MediaLibrary> visibleLibraries, {required bool groupByServer}) {
    final selectedLibrary =
        visibleLibraries.where((lib) => lib.globalKey == _selectedLibraryGlobalKey).firstOrNull ??
        visibleLibraries.firstOrNull;
    if (selectedLibrary == null) return Text(t.libraries.title);

    return AppMenuButton<String>(
      key: _libraryDropdownKey,
      tooltip: t.libraries.selectLibrary,
      adaptiveSheet: true,
      onSelected: (libraryGlobalKey) {
        _loadLibraryContent(libraryGlobalKey);
      },
      entriesBuilder: (context) => _buildGroupedLibraryMenuItems(visibleLibraries, groupByServer: groupByServer),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: .min,
          children: [
            AppIcon(ContentTypeHelper.getLibraryIcon(selectedLibrary.kind.id), fill: 1, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: librariesSpanMultipleServers(visibleLibraries) && selectedLibrary.serverName != null
                  ? Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      children: [
                        Text(
                          selectedLibrary.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        LibraryServerLabel(
                          library: selectedLibrary,
                          badgeSize: 10,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                          ),
                          constrainText: true,
                        ),
                      ],
                    )
                  : Text(
                      selectedLibrary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
            ),
            const SizedBox(width: 4),
            const AppIcon(Symbols.arrow_drop_down_rounded, fill: 1, size: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingValueBuilder<bool>(
      pref: SettingsService.groupLibrariesByServer,
      builder: (context, groupByServerSetting, _) => _buildContent(context, groupByServerSetting),
    );
  }

  Widget _buildContent(BuildContext context, bool groupByServerSetting) {
    final librariesProvider = context.watch<LibrariesProvider>();
    final allLibraries = librariesProvider.libraries;
    final isLoadingLibraries = librariesProvider.isLoading;
    final librariesErrorMessage = librariesProvider.errorMessage;

    // Watch for hidden libraries changes to trigger rebuild
    final hiddenLibrariesProvider = context.watch<HiddenLibrariesProvider>();
    final hiddenKeys = hiddenLibrariesProvider.hiddenLibraryKeys;

    // Compute visible libraries (filtered from all libraries)
    final visibleLibraries = allLibraries.where((lib) => !hiddenKeys.contains(lib.globalKey)).toList();

    // Resolve selected library defensively — may be null if server temporarily dropped during refresh
    final selectedLibrary = _selectedLibraryGlobalKey != null
        ? allLibraries.where((lib) => lib.globalKey == _selectedLibraryGlobalKey).firstOrNull
        : null;

    final showBrowseOptionsAction = selectedLibrary != null && PlatformDetector.isMobile(context);
    final canSelectedLibraryGroupByFolders = context.select<MultiServerProvider, bool>((provider) {
      if (selectedLibrary == null || selectedLibrary.isShared) return false;
      final serverId = serverIdOrNull(selectedLibrary.serverId);
      if (serverId == null) return false;
      return provider.getClientForServer(serverId)?.capabilities.folderGrouping ?? false;
    });

    List<FocusableAction> appBarActions() => [
      if (allLibraries.isNotEmpty)
        FocusableAction(
          icon: Symbols.edit_rounded,
          tooltip: t.libraries.manageLibraries,
          onPressed: _showLibraryManagementSheet,
        ),
      if (showBrowseOptionsAction)
        FocusableAction(
          icon: Symbols.tune_rounded,
          tooltip: t.libraries.libraryOptions,
          onPressed: _showBrowseOptionsForCurrentTab,
          // Badge the icon with a dot while the browse tab has active filters
          // (issue #1470). A null child keeps the default rendering.
          child: _browseFiltersActive
              ? IconButton(
                  tooltip: t.libraries.libraryOptions,
                  onPressed: _showBrowseOptionsForCurrentTab,
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const AppIcon(Symbols.tune_rounded, fill: 1),
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      if (selectedLibrary != null && MediaListPlaybackLauncher.canShuffleLibrary(selectedLibrary))
        FocusableAction(
          icon: Symbols.shuffle_rounded,
          tooltip: t.libraries.shuffleLibrary,
          onPressed: () => unawaited(MediaListPlaybackLauncher.shuffleLibrary(context, selectedLibrary)),
        ),
      FocusableAction(icon: Symbols.refresh_rounded, tooltip: t.common.refresh, onPressed: manualRefresh),
    ];

    Widget appBar({required bool floating}) => DesktopSliverAppBar(
      title: _buildAppBarTitle(visibleLibraries, selectedLibrary, groupByServer: groupByServerSetting),
      // When showing the tab content, let the app bar float away with the
      // content. Otherwise (loading / empty / error states) keep it pinned so
      // it stays visible over the centered state widget.
      pinned: !floating,
      floating: floating,
      snap: floating,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actions: [
        FocusableActionBar(
          key: _actionBarKey,
          onNavigateLeft: () => MainScreenFocusScope.focusSidebarOf(context),
          onNavigateDown: _focusCurrentTab,
          actions: appBarActions(),
        ),
      ],
    );

    Widget buildSimpleScroll({required Widget body}) {
      return CustomScrollView(
        controller: _outerScrollController,
        slivers: [
          appBar(floating: false),
          SliverFillRemaining(child: body),
        ],
      );
    }

    Widget body;
    if (isLoadingLibraries) {
      body = buildSimpleScroll(body: const Center(child: CircularProgressIndicator()));
    } else if (librariesErrorMessage != null && visibleLibraries.isEmpty && selectedLibrary == null) {
      body = buildSimpleScroll(
        body: ErrorStateWidget(
          message: librariesErrorMessage,
          icon: Symbols.error_outline_rounded,
          onRetry: manualRefresh,
        ),
      );
    } else if (visibleLibraries.isEmpty && selectedLibrary == null) {
      body = buildSimpleScroll(
        body: allLibraries.isEmpty
            ? EmptyStateWidget(message: t.libraries.noLibrariesFound, icon: Symbols.video_library_rounded)
            : EmptyStateWidget(
                message: t.libraries.allLibrariesHidden,
                icon: Symbols.visibility_off_rounded,
                onAction: _showLibraryManagementSheet,
                actionLabel: t.libraries.manageLibraries,
                actionIcon: Symbols.edit_rounded,
              ),
      );
    } else if (selectedLibrary != null) {
      body = NestedScrollView(
        controller: _outerScrollController,
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: appBar(floating: true),
          ),
        ],
        body: KeyedSubtree(
          key: ValueKey(_selectedLibraryGlobalKey),
          child: _buildBrowseContent(selectedLibrary, canGroupByFolders: canSelectedLibraryGroupByFolders),
        ),
      );
    } else {
      if (_selectedLibraryGlobalKey == null) _scheduleInitializeWithLibraries();
      body = buildSimpleScroll(body: const SizedBox.shrink());
    }

    // Browse draws its own scrollbar for the nested inner scroll view.
    final scrollBody = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: body,
    );

    return Scaffold(body: scrollBody);
  }
}
