import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics/app_log.dart';
import '../../core/diagnostics/diagnostic_report.dart';
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
  final _searchController = TextEditingController();
  StreamSubscription<LogEntry>? _subscription;
  late bool _enabled;
  bool _saving = false;
  LogLevel? _level;
  late List<LogEntry> _entries;

  @override
  void initState() {
    super.initState();
    _enabled = AppLog.isEnabled;
    _entries = AppLog.recent;
    _subscription = AppLog.stream.listen((entry) {
      if (!mounted) return;
      setState(() {
        _entries.insert(0, entry);
        if (_entries.length > AppLog.maxRetained) {
          _entries.removeLast();
        }
      });
    });
    _searchController.addListener(_refreshSearch);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

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
    final text = entries.reversed
        .map((entry) => DiagnosticSanitizer.sanitize(entry.toString()))
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.debugLogsCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isNight = widget.isNight;
    final background = isNight ? AppTheme.darkBg : AppTheme.lightBg;
    final card = isNight ? AppTheme.darkCardBg : AppTheme.lightCardBg;
    final primary =
        isNight ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final secondary =
        isNight ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final border =
        isNight
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
            colors:
                isNight
                    ? const [AppTheme.nightAbyss, AppTheme.darkBg]
                    : [
                      AppTheme.lightBg,
                      AppTheme.sunsetCoral.withValues(alpha: 0.10),
                    ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _LogHeader(
                title: s.debugLogsTitle,
                enabled: _enabled,
                statusLabel:
                    _enabled ? s.debugLoggingEnabled : s.debugLoggingDisabled,
                primary: primary,
                secondary: secondary,
                onBack: () => Navigator.pop(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: card.withValues(alpha: isNight ? 0.88 : 0.94),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isNight ? 0.16 : 0.05,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (_enabled
                                  ? const Color(0xFF4B9A8C)
                                  : secondary)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          _enabled
                              ? Icons.terminal_rounded
                              : Icons.terminal_outlined,
                          color: _enabled ? const Color(0xFF4B9A8C) : secondary,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.debugLoggingSwitch,
                              style: TextStyle(
                                color: primary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.debugLoggingDescription,
                              style: TextStyle(
                                color: secondary,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: _enabled,
                        onChanged: _saving ? null : _setEnabled,
                        activeColor: const Color(0xFF4B9A8C),
                      ),
                    ],
                  ),
                ),
              ),
              if (_enabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: primary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: s.searchDebugLogs,
                      hintStyle: TextStyle(color: secondary),
                      prefixIcon: Icon(Icons.search_rounded, color: secondary),
                      suffixIcon:
                          _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                tooltip: s.clearSearch,
                                onPressed: _searchController.clear,
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: secondary,
                                ),
                              ),
                      filled: true,
                      fillColor: card.withValues(alpha: 0.78),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.debugLogCount(entries.length),
                          style: TextStyle(color: secondary, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        tooltip: s.copyDebugLogs,
                        onPressed: entries.isEmpty ? null : _copy,
                        icon: const Icon(Icons.copy_all_rounded),
                        color: primary,
                      ),
                      IconButton(
                        tooltip: s.clearDebugLogs,
                        onPressed: _entries.isEmpty ? null : _clear,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        color: primary,
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child:
                    !_enabled
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
                        : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: entries.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 9),
                          itemBuilder:
                              (context, index) => _LogEntryCard(
                                entry: entries[index],
                                isNight: isNight,
                                primary: primary,
                                secondary: secondary,
                                card: card,
                                border: border,
                              ),
                        ),
              ),
              if (_enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Text(
                    s.debugLogPrivacyNote,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondary, fontSize: 11),
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
        selectedColor:
            widget.isNight ? AppTheme.nightSkyBlue : AppTheme.sunsetCoral,
        backgroundColor: card,
        labelStyle: TextStyle(
          color: selected ? Colors.white : primary,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: secondary.withValues(alpha: 0.65)),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: primary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({
    required this.entry,
    required this.isNight,
    required this.primary,
    required this.secondary,
    required this.card,
    required this.border,
  });

  final LogEntry entry;
  final bool isNight;
  final Color primary;
  final Color secondary;
  final Color card;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final accent = switch (entry.level) {
      LogLevel.debug => secondary,
      LogLevel.info => const Color(0xFF4B9A8C),
      LogLevel.warn => const Color(0xFFD99A68),
      LogLevel.error => const Color(0xFFD8666F),
    };
    final levelLabel = entry.level.name.toUpperCase();
    final time =
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}.'
        '${entry.time.millisecond.toString().padLeft(3, '0')}';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: card.withValues(alpha: isNight ? 0.76 : 0.90),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  levelLabel,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.tag,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  color: secondary,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SelectableText(
            entry.message,
            style: TextStyle(color: primary, fontSize: 13, height: 1.4),
          ),
          if (entry.error != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              '${entry.error}',
              style: TextStyle(
                color: accent.withValues(alpha: 0.88),
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
