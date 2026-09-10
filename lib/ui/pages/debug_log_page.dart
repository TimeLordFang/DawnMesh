import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/diagnostics/diagnostic_report.dart';
import '../../core/platform/native_debug_log_channel.dart';
import '../../core/preferences/audio_tuning_settings_store.dart';
import '../../core/preferences/debug_log_settings_store.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_theme.dart';

class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key, required this.isNight});

  final bool isNight;

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  final _settings = DebugLogSettingsStore();
  final _audioSettings = AudioTuningSettingsStore();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<LogEntry>? _subscription;
  late bool _enabled;
  bool _saving = false;
  bool _audioProfileSaving = false;
  AudioTuningProfile _audioProfile = AudioTuningProfile.balanced;
  AudioTuningParameters _audioParameters = AudioTuningParameters.defaults(
    AudioTuningProfile.balanced,
  );
  LogLevel? _level;
  late List<LogEntry> _entries;

  @override
  void initState() {
    super.initState();
    _enabled = AppLog.isEnabled;
    _entries = AppLog.recent.reversed.toList();
    _subscription = AppLog.stream.listen((entry) {
      if (!mounted) return;
      setState(() {
        _entries.add(entry);
        if (_entries.length > AppLog.maxRetained) {
          _entries.removeAt(0);
        }
      });
      _scrollToEnd();
    });
    _searchController.addListener(_refreshSearch);
    _loadAudioProfile();
    if (_enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NativeDebugLogChannel.captureSystemSnapshot();
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  Future<void> _loadAudioProfile() async {
    final parameters = await _audioSettings.loadParameters();
    if (mounted) {
      setState(() {
        _audioProfile = parameters.profile;
        _audioParameters = parameters;
      });
    }
  }

  Future<void> _setAudioProfile(AudioTuningProfile profile) async {
    if (_audioProfileSaving || profile == _audioProfile) return;
    final previous = _audioProfile;
    setState(() {
      _audioProfile = profile;
      _audioProfileSaving = true;
    });
    final saved = await _audioSettings.save(profile);
    if (!mounted) return;
    setState(() {
      if (!saved) _audioProfile = previous;
      if (saved) _audioParameters = AudioTuningParameters.defaults(profile);
      _audioProfileSaving = false;
    });
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? s.audioTuningApplied : s.audioTuningSaveFailed),
      ),
    );
    if (saved) {
      AppLog.info('音频', '调优档位切换为 ${profile.wireName}');
    }
  }

  Future<bool> _setAudioParameters(AudioTuningParameters parameters) async {
    if (_audioProfileSaving) return false;
    setState(() => _audioProfileSaving = true);
    final saved = await _audioSettings.saveParameters(parameters);
    if (!mounted) return saved;
    setState(() {
      if (saved) {
        _audioParameters = parameters;
        _audioProfile = parameters.profile;
      }
      _audioProfileSaving = false;
    });
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? s.audioParametersApplied : s.audioTuningSaveFailed,
        ),
      ),
    );
    if (saved) AppLog.info('音频', '高级调优参数已即时应用：${parameters.toMap()}');
    return saved;
  }

  Future<void> _showAdvancedTuning() async {
    final s = AppStrings.of(context);
    var draft = _audioParameters;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: widget.isNight
          ? AppTheme.darkCardBg
          : AppTheme.lightCardBg,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(AudioTuningParameters value) =>
              setSheetState(() => draft = value);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.88,
            minChildSize: 0.55,
            maxChildSize: 0.96,
            builder: (_, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.audioAdvancedTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  s.audioAdvancedDescription,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                _TuningSlider(
                  label: s.audioHeadsetBitrate,
                  valueLabel: '${draft.headsetBitrate ~/ 1000} kbps',
                  value: draft.headsetBitrate.toDouble(),
                  min: 6000,
                  max: 16000,
                  divisions: 10,
                  onChanged: (v) =>
                      update(draft.copyWith(headsetBitrate: v.round())),
                ),
                _TuningSlider(
                  label: s.audioL2capCoalesce,
                  valueLabel: '${draft.l2capCoalesceMillis} ms',
                  value: draft.l2capCoalesceMillis.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) =>
                      update(draft.copyWith(l2capCoalesceMillis: v.round())),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.audioFlushEveryWrite),
                  subtitle: Text(s.audioFlushEveryWriteHint),
                  value: draft.flushEveryWrite,
                  onChanged: (v) => update(draft.copyWith(flushEveryWrite: v)),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.audioDropStale),
                  subtitle: Text(s.audioDropStaleHint),
                  value: draft.dropStaleRealtime,
                  onChanged: (v) =>
                      update(draft.copyWith(dropStaleRealtime: v)),
                ),
                _TuningSlider(
                  label: s.audioStaleDeadline,
                  valueLabel: '${draft.maxRealtimeAgeMillis} ms',
                  value: draft.maxRealtimeAgeMillis.toDouble(),
                  min: 20,
                  max: 300,
                  divisions: 14,
                  enabled: draft.dropStaleRealtime,
                  onChanged: (v) =>
                      update(draft.copyWith(maxRealtimeAgeMillis: v.round())),
                ),
                _TuningSlider(
                  label: s.audioPrebuffer,
                  valueLabel: '${draft.prebufferFrames * 20} ms',
                  value: draft.prebufferFrames.toDouble(),
                  min: 1,
                  max: 15,
                  divisions: 14,
                  onChanged: (v) {
                    final frames = v.round();
                    update(
                      draft.copyWith(
                        prebufferFrames: frames,
                        maxAdaptiveFrames: draft.maxAdaptiveFrames < frames
                            ? frames
                            : null,
                      ),
                    );
                  },
                ),
                _TuningSlider(
                  label: s.audioMaximumBuffer,
                  valueLabel: '${draft.maxBufferFrames * 20} ms',
                  value: draft.maxBufferFrames.toDouble(),
                  min: [
                    draft.prebufferFrames,
                    draft.maxAdaptiveFrames,
                    draft.maxPlayoutQueueFrames,
                  ].reduce((a, b) => a > b ? a : b).toDouble(),
                  max: 32,
                  divisions: 32 - [
                    draft.prebufferFrames,
                    draft.maxAdaptiveFrames,
                    draft.maxPlayoutQueueFrames,
                  ].reduce((a, b) => a > b ? a : b),
                  onChanged: (v) =>
                      update(draft.copyWith(maxBufferFrames: v.round())),
                ),
                _TuningSlider(
                  label: s.audioAdaptiveBuffer,
                  valueLabel: '${draft.maxAdaptiveFrames * 20} ms',
                  value: draft.maxAdaptiveFrames.toDouble(),
                  min: draft.prebufferFrames.toDouble(),
                  max: 32,
                  divisions: 32 - draft.prebufferFrames,
                  onChanged: (v) =>
                      update(draft.copyWith(maxAdaptiveFrames: v.round())),
                ),
                _TuningSlider(
                  label: s.audioLiveQueue,
                  valueLabel: '${draft.maxPlayoutQueueFrames * 20} ms',
                  value: draft.maxPlayoutQueueFrames.toDouble(),
                  min: 1,
                  max: draft.maxBufferFrames.toDouble(),
                  divisions: draft.maxBufferFrames - 1,
                  onChanged: (v) =>
                      update(draft.copyWith(maxPlayoutQueueFrames: v.round())),
                ),
                _TuningSlider(
                  label: s.audioStableDecay,
                  valueLabel:
                      '${(draft.stableFramesBeforeDecay * 20 / 1000).toStringAsFixed(1)} s',
                  value: draft.stableFramesBeforeDecay.toDouble(),
                  min: 10,
                  max: 500,
                  divisions: 49,
                  onChanged: (v) => update(
                    draft.copyWith(stableFramesBeforeDecay: v.round()),
                  ),
                ),
                _TuningSlider(
                  label: s.audioPlcLimit,
                  valueLabel: '${draft.maxConcealmentFrames * 20} ms',
                  value: draft.maxConcealmentFrames.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  onChanged: (v) =>
                      update(draft.copyWith(maxConcealmentFrames: v.round())),
                ),
                _TuningSlider(
                  label: s.audioTrackBuffer,
                  valueLabel: '${draft.audioTrackBufferFrames * 20} ms',
                  value: draft.audioTrackBufferFrames.toDouble(),
                  min: 1,
                  max: 12,
                  divisions: 11,
                  onChanged: (v) =>
                      update(draft.copyWith(audioTrackBufferFrames: v.round())),
                ),
                const SizedBox(height: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          update(AudioTuningParameters.defaults(draft.profile)),
                      child: Text(s.audioResetProfile),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _audioProfileSaving
                          ? null
                          : () async {
                              final saved = await _setAudioParameters(draft);
                              if (saved && sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                      icon: const Icon(Icons.save_rounded),
                      label: Text(s.audioApplyParameters),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  List<LogEntry> get _visibleEntries {
    final query = _searchController.text.trim().toLowerCase();
    return _entries
        .where((entry) {
          if (_level != null && entry.level != _level) return false;
          if (query.isEmpty) return true;
          return entry.tag.toLowerCase().contains(query) ||
              entry.message.toLowerCase().contains(query) ||
              '${entry.error ?? ''}'.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await _settings.save(enabled);
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).debugLogSaveFailed)),
      );
      return;
    }

    AppLog.setEnabled(enabled);
    setState(() {
      _enabled = enabled;
      _saving = false;
      if (!enabled) _entries.clear();
    });
    if (enabled) {
      AppLog.info('调试日志', '应用内调试日志已开启');
      await NativeDebugLogChannel.captureSystemSnapshot();
    }
  }

  void _clear() {
    AppLog.clear();
    setState(_entries.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).debugLogsCleared)),
    );
  }

  Future<void> _copy() async {
    final s = AppStrings.of(context);
    final entries = _visibleEntries;
    if (entries.isEmpty) return;
    final text = entries
        .map((entry) => DiagnosticSanitizer.sanitize(entry.toString()))
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.debugLogsCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final background = isNight ? AppTheme.darkBg : AppTheme.lightBg;
    final card = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final primary = isNight
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final secondary = isNight
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final border = isNight
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final entries = _visibleEntries;

    return Scaffold(
      backgroundColor: background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isNight
                ? const [AppTheme.nightAbyss, AppTheme.darkBg]
                : [
                    AppTheme.lightBg,
                    AppTheme.dawnCoral.withValues(alpha: 0.10),
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _LogHeader(
                title: s.debugLogsTitle,
                enabled: _enabled,
                statusLabel: _enabled
                    ? s.debugLoggingEnabled
                    : s.debugLoggingDisabled,
                primary: primary,
                secondary: secondary,
                onBack: () => Navigator.pop(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: card.withValues(alpha: isNight ? 0.88 : 0.94),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isNight ? 0.16 : 0.05,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color:
                              (_enabled ? const Color(0xFF4B9A8C) : secondary)
                                  .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          _enabled
                              ? Icons.terminal_rounded
                              : Icons.terminal_outlined,
                          color: _enabled ? const Color(0xFF4B9A8C) : secondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.debugLoggingSwitch,
                              style: TextStyle(
                                color: primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.debugLoggingDescription,
                              style: TextStyle(
                                color: secondary,
                                fontSize: 10.5,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: _enabled,
                        onChanged: _saving ? null : _setEnabled,
                        activeThumbColor: const Color(0xFF4B9A8C),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
                  decoration: BoxDecoration(
                    color: card.withValues(alpha: isNight ? 0.88 : 0.94),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: const Color(0xFF4B9A8C),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            s.audioTuningTitle,
                            style: TextStyle(
                              color: primary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _audioProfileSaving
                                ? null
                                : _showAdvancedTuning,
                            tooltip: s.audioAdvancedButton,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.tune_rounded, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AudioTuningProfile>(
                          segments: [
                            ButtonSegment(
                              value: AudioTuningProfile.lowLatency,
                              label: Text(s.audioTuningLow),
                              icon: const Icon(Icons.bolt_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: AudioTuningProfile.balanced,
                              label: Text(s.audioTuningBalanced),
                              icon: const Icon(Icons.balance_rounded, size: 16),
                            ),
                            ButtonSegment(
                              value: AudioTuningProfile.stable,
                              label: Text(s.audioTuningStable),
                              icon: const Icon(Icons.shield_rounded, size: 16),
                            ),
                          ],
                          selected: {_audioProfile},
                          showSelectedIcon: false,
                          onSelectionChanged: _audioProfileSaving
                              ? null
                              : (selection) =>
                                    _setAudioProfile(selection.single),
                          style: ButtonStyle(
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -2,
                            ),
                            textStyle: const WidgetStatePropertyAll(
                              TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        switch (_audioProfile) {
                          AudioTuningProfile.lowLatency =>
                            s.audioTuningLowDescription,
                          AudioTuningProfile.balanced =>
                            s.audioTuningBalancedDescription,
                          AudioTuningProfile.stable =>
                            s.audioTuningStableDescription,
                        },
                        style: TextStyle(
                          color: secondary,
                          fontSize: 10.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_enabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: primary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: s.searchDebugLogs,
                      hintStyle: TextStyle(color: secondary),
                      prefixIcon: Icon(Icons.search_rounded, color: secondary),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: s.clearSearch,
                              onPressed: _searchController.clear,
                              icon: Icon(Icons.close_rounded, color: secondary),
                            ),
                      filled: true,
                      fillColor: card.withValues(alpha: 0.78),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _filterChip(s.debugLogAll, null, primary, card),
                      _filterChip(
                        s.debugLogDebug,
                        LogLevel.debug,
                        primary,
                        card,
                      ),
                      _filterChip(s.debugLogInfo, LogLevel.info, primary, card),
                      _filterChip(
                        s.debugLogWarning,
                        LogLevel.warn,
                        primary,
                        card,
                      ),
                      _filterChip(
                        s.debugLogError,
                        LogLevel.error,
                        primary,
                        card,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.debugLogCount(entries.length),
                          style: TextStyle(color: secondary, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        tooltip: s.captureSystemSnapshot,
                        onPressed: NativeDebugLogChannel.captureSystemSnapshot,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.memory_rounded, size: 20),
                        color: primary,
                      ),
                      IconButton(
                        tooltip: s.copyDebugLogs,
                        onPressed: entries.isEmpty ? null : _copy,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy_all_rounded, size: 20),
                        color: primary,
                      ),
                      IconButton(
                        tooltip: s.clearDebugLogs,
                        onPressed: _entries.isEmpty ? null : _clear,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                        color: primary,
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: !_enabled
                    ? _EmptyLogs(
                        icon: Icons.power_settings_new_rounded,
                        title: s.debugLoggingDisabled,
                        detail: s.debugLogDisabledHint,
                        primary: primary,
                        secondary: secondary,
                      )
                    : entries.isEmpty
                    ? _EmptyLogs(
                        icon: Icons.hourglass_empty_rounded,
                        title: s.debugLogEmpty,
                        detail: s.debugLogEmptyHint,
                        primary: primary,
                        secondary: secondary,
                      )
                    : _ConsoleOutput(
                        entries: entries,
                        controller: _scrollController,
                        isNight: isNight,
                        secondary: secondary,
                        border: border,
                      ),
              ),
              if (_enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 3, 20, 8),
                  child: Text(
                    s.debugLogPrivacyNote,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, LogLevel? level, Color primary, Color card) {
    final selected = _level == level;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _level = level),
        selectedColor: widget.isNight
            ? AppTheme.nightSkyBlue
            : AppTheme.dawnCoral,
        backgroundColor: card,
        labelStyle: TextStyle(
          color: selected ? Colors.white : primary,
          fontSize: 10.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide.none,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
      ),
    );
  }
}

class _LogHeader extends StatelessWidget {
  const _LogHeader({
    required this.title,
    required this.enabled,
    required this.statusLabel,
    required this.primary,
    required this.secondary,
    required this.onBack,
  });

  final String title;
  final bool enabled;
  final String statusLabel;
  final Color primary;
  final Color secondary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: primary),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: primary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (enabled ? const Color(0xFF4B9A8C) : secondary).withValues(
                alpha: 0.14,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: enabled ? const Color(0xFF4B9A8C) : secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: enabled ? const Color(0xFF4B9A8C) : secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs({
    required this.icon,
    required this.title,
    required this.detail,
    required this.primary,
    required this.secondary,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color primary;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 36,
                    color: secondary.withValues(alpha: 0.65),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: TextStyle(
                      color: primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsoleOutput extends StatelessWidget {
  const _ConsoleOutput({
    required this.entries,
    required this.controller,
    required this.isNight,
    required this.secondary,
    required this.border,
  });

  final List<LogEntry> entries;
  final ScrollController controller;
  final bool isNight;
  final Color secondary;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      decoration: BoxDecoration(
        color: isNight ? const Color(0xFF0A111A) : const Color(0xFF172027),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SelectionArea(
        child: ListView.builder(
          controller: controller,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          itemCount: entries.length,
          itemBuilder: (context, index) =>
              _ConsoleLogLine(entry: entries[index], secondary: secondary),
        ),
      ),
    );
  }
}

class _ConsoleLogLine extends StatelessWidget {
  const _ConsoleLogLine({required this.entry, required this.secondary});

  final LogEntry entry;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final accent = switch (entry.level) {
      LogLevel.debug => const Color(0xFF8A98A6),
      LogLevel.info => const Color(0xFF72C6B5),
      LogLevel.warn => const Color(0xFFFFC06A),
      LogLevel.error => const Color(0xFFFF7882),
    };
    final time =
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}.'
        '${entry.time.millisecond.toString().padLeft(3, '0')}';
    final error = entry.error == null ? '' : '  ← ${entry.error}';
    const baseStyle = TextStyle(
      color: Color(0xFFE1E8EC),
      fontFamily: 'monospace',
      fontSize: 10.5,
      height: 1.35,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text: '$time ',
              style: TextStyle(color: secondary),
            ),
            TextSpan(
              text: '${entry.level.name.toUpperCase().padRight(5)} ',
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: '[${entry.tag}] ',
              style: const TextStyle(color: Color(0xFF8AB4F8)),
            ),
            TextSpan(text: entry.message),
            if (error.isNotEmpty)
              TextSpan(
                text: error,
                style: TextStyle(color: accent),
              ),
          ],
        ),
      ),
    );
  }
}

class _TuningSlider extends StatelessWidget {
  const _TuningSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                valueLabel,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions > 0 ? divisions : null,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
