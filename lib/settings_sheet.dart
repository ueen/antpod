// lib/settings_sheet.dart
//
// The settings: a sheet from the about bubble that opens part way up and
// extends to full height when scrolled. Import & export sit at the bottom.
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';
import 'app_settings.dart';
import 'backup.dart';
import 'l10n/app_localizations.dart';
import 'player_provider.dart';

/// Saving files and opening the downloads folder: MainActivity.kt.
const _files = MethodChannel('antpod/files');

/// What a backup carries besides the library: the sheet's switches, and the
/// player's speed, skip intervals and last episode.
const _backupKeys = [...AppSettings.keys, ...PlayerProvider.prefKeys];

bool? _dynamicColors;

/// Whether the device has wallpaper colours (Android 12+), asked once.
Future<bool> _hasDynamicColors() async {
  if (_dynamicColors case final known?) return known;
  var has = false;
  if (Platform.isAndroid) {
    try {
      has = await DynamicColorPlugin.getCorePalette() != null;
    } catch (_) {}
  }
  return _dynamicColors = has;
}

/// A line under the import & export tiles: how the last one went.
typedef _Status = ({String text, bool error});

Future<void> showSettingsSheet(BuildContext context) async {
  // Known before the sheet opens, so the Material You switch doesn't pop in.
  final dynamicColors = await _hasDynamicColors();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      snap: true,
      snapSizes: const [0.6],
      builder: (_, controller) =>
          _SettingsSheet(controller: controller, dynamicColors: dynamicColors),
    ),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.controller, required this.dynamicColors});

  /// The sheet's: scrolling up first extends it to full height.
  final ScrollController controller;
  final bool dynamicColors;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  final _statusKey = GlobalKey();

  /// An import or export is running: their tiles are off meanwhile.
  bool _busy = false;

  /// Feeds loaded of all, while an import subscribes.
  ({int done, int total})? _progress;

  _Status? _status;

  /// No app could open the downloads folder: its tile says so.
  bool _downloadsFailed = false;

  // ── Import & export ───────────────────────────────────────────────────────

  /// Runs [task] with the import & export tiles off and shows the status it
  /// returns (null: none, e.g. when the picker was cancelled); [failed] when
  /// it throws. Once the sheet is closed, the status goes to a snackbar.
  Future<void> _run(Future<_Status?> Function() task, {required String failed}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _progress = null;
      _status = null;
    });
    _Status? status;
    try {
      status = await task();
    } catch (e) {
      debugPrint('[settings] $e');
      status = (text: failed, error: true);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _progress = null;
        _status = status;
      });
      if (status != null) _revealStatus();
    } else if (status != null) {
      messenger?.showSnackBar(SnackBar(content: Text(status.text)));
    }
  }

  void _onProgress(int done, int total) {
    if (!mounted) return;
    final first = _progress == null;
    setState(() => _progress = (done: done, total: total));
    if (first) _revealStatus();
  }

  /// Scrolls the status line into view: it sits under the last tile.
  void _revealStatus() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final status = _statusKey.currentContext;
        if (status == null || !status.mounted) return;
        Scrollable.ensureVisible(status,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      });

  Future<void> _exportBackup(Rect? origin) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    return _run(failed: l10n.exportFailed, () async {
      final prefs = await SharedPreferences.getInstance();
      final text = await Backup.export(db, prefs, settingKeys: _backupKeys);
      return _save(Backup.fileName(DateTime.now()), 'application/json', text,
          origin: origin, l10n: l10n);
    });
  }

  Future<void> _importBackup() {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final settings = context.read<AppSettings>();
    final player = context.read<PlayerProvider>();
    return _run(failed: l10n.importUnreadable, () async {
      final text = await _pickText();
      if (text == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final ImportReport report;
      try {
        report = await Backup.import(db, prefs, text,
            settingKeys: _backupKeys, onProgress: _onProgress);
      } on FormatException catch (e) {
        final newer = e.message == 'a newer version';
        return (text: newer ? l10n.importNewerBackup : l10n.importNotBackup, error: true);
      }
      settings.reload();
      await player.reloadSettings();
      return (text: _describe(report, l10n), error: false);
    });
  }

  Future<void> _exportOpml(Rect? origin) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    return _run(failed: l10n.exportFailed, () async {
      final text = Opml.build(await db.getAllPodcasts());
      return _save(Opml.fileName(DateTime.now()), 'text/x-opml', text,
          origin: origin, l10n: l10n);
    });
  }

  Future<void> _importOpml() {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    return _run(failed: l10n.importUnreadable, () async {
      final text = await _pickText();
      if (text == null) return null;
      try {
        final report = await Opml.import(db, text, onProgress: _onProgress);
        return (text: _describe(report, l10n), error: false);
      } on FormatException {
        return (text: l10n.importNotOpml, error: true);
      }
    });
  }

  /// The text of a file the user picks; null when they cancel.
  static Future<String?> _pickText() async {
    final file = await openFile();
    return file?.readAsString();
  }

  static String _describe(ImportReport r, AppLocalizations l10n) => [
        l10n.importSubscribed(r.subscribed),
        if (r.episodes > 0) l10n.importEpisodes(r.episodes),
        if (r.failed > 0) l10n.importFailed(r.failed),
      ].join(' · ');

  /// Writes [text] to a temp file named [name] and lets the user put it
  /// somewhere: the system's save dialog on Android, the share sheet (Save
  /// to Files, AirDrop…) on iOS, whose popover on an iPad points at [origin].
  static Future<_Status?> _save(String name, String mime, String text,
      {required Rect? origin, required AppLocalizations l10n}) async {
    final file = File('${(await getTemporaryDirectory()).path}/$name');
    await file.writeAsString(text);
    try {
      if (Platform.isAndroid) {
        final saved = await _files.invokeMethod<bool>(
            'saveFile', {'name': name, 'mime': mime, 'path': file.path});
        return saved == true ? (text: l10n.exportSaved, error: false) : null;
      }
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        sharePositionOrigin: origin,
      ));
      return null;
    } finally {
      file.delete().ignore();
    }
  }

  // ── Downloads folder ──────────────────────────────────────────────────────

  Future<void> _openDownloads() async {
    bool opened;
    try {
      opened = await _files.invokeMethod<bool>('openDownloads') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[settings] downloads folder: $e');
      opened = false;
    }
    if (mounted) setState(() => _downloadsFailed = !opened);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<AppSettings>();
    return ListView(
      controller: widget.controller,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
      children: [
        // Part of the list, so dragging it moves the sheet too.
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 32, height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Text(l10n.settings,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        _header(l10n.settingsAppearance, cs),
        _theme(l10n, cs, settings),
        if (widget.dynamicColors)
          _switch(cs,
              icon: Icons.palette_rounded,
              title: l10n.settingsMaterialYou,
              subtitle: l10n.settingsMaterialYouSub,
              value: settings.materialYou,
              onChanged: (v) => settings.materialYou = v),
        _header(l10n.settingsPlayback, cs),
        _switch(cs,
            icon: Icons.replay_10_rounded,
            title: l10n.settingsRewindOnResume,
            subtitle: l10n.settingsRewindOnResumeSub,
            value: settings.rewindOnResume,
            onChanged: (v) => settings.rewindOnResume = v),
        _switch(cs,
            icon: Icons.done_all_rounded,
            title: l10n.settingsMarkPlayedNearEnd,
            subtitle: l10n.settingsMarkPlayedNearEndSub,
            value: settings.markPlayedNearEnd,
            onChanged: (v) => settings.markPlayedNearEnd = v),
        _header(l10n.settingsDownloads, cs),
        _switch(cs,
            icon: Icons.auto_delete_rounded,
            title: l10n.settingsDeletePlayed,
            subtitle: l10n.settingsDeletePlayedSub,
            value: settings.deletePlayedDownloads,
            onChanged: (v) => settings.deletePlayedDownloads = v),
        // iOS has no place for an app's files in the Files app without
        // opening up all of its documents.
        if (Platform.isAndroid)
          _tile(cs,
              icon: Icons.folder_open_rounded,
              title: l10n.settingsDownloadsFolder,
              subtitle: _downloadsFailed
                  ? l10n.settingsDownloadsFolderFailed
                  : l10n.settingsDownloadsFolderSub,
              subtitleError: _downloadsFailed,
              trailing: Icon(Icons.open_in_new_rounded, size: 20, color: cs.onSurfaceVariant),
              onTap: (_) => _openDownloads()),
        _header(l10n.settingsNetwork, cs),
        _switch(cs,
            icon: Icons.travel_explore_rounded,
            title: 'Apple Podcasts',
            subtitle: l10n.settingsAppleApiSub,
            value: settings.appleApi,
            onChanged: (v) => settings.appleApi = v),
        _header(l10n.settingsImportExport, cs),
        _tile(cs,
            icon: Icons.save_alt_rounded,
            title: l10n.exportBackup,
            subtitle: l10n.exportBackupSub,
            enabled: !_busy,
            onTap: (tile) => _exportBackup(_originOf(tile))),
        _tile(cs,
            icon: Icons.settings_backup_restore_rounded,
            title: l10n.importBackup,
            subtitle: l10n.importBackupSub,
            enabled: !_busy,
            onTap: (_) => _importBackup()),
        _tile(cs,
            icon: Icons.output_rounded,
            title: l10n.exportOpml,
            subtitle: l10n.exportOpmlSub,
            enabled: !_busy,
            onTap: (tile) => _exportOpml(_originOf(tile))),
        _tile(cs,
            icon: Icons.input_rounded,
            title: l10n.importOpml,
            subtitle: l10n.importOpmlSub,
            enabled: !_busy,
            onTap: (_) => _importOpml()),
        KeyedSubtree(key: _statusKey, child: _statusLine(l10n, cs)),
      ],
    );
  }

  Widget _header(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
        child: Text(text, style: TextStyle(
            color: cs.primary, fontSize: 14, fontWeight: FontWeight.w600)),
      );

  /// System, light or dark: three segments under the title.
  Widget _theme(AppLocalizations l10n, ColorScheme cs, AppSettings settings) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: Icon(Icons.contrast_rounded, color: cs.primary),
        title: Text(l10n.settingsTheme),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l10n.settingsThemeSystem)),
                ButtonSegment(value: ThemeMode.light, label: Text(l10n.settingsThemeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l10n.settingsThemeDark)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.themeMode = s.single,
            ),
          ),
        ),
      );

  Widget _switch(ColorScheme cs, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        secondary: Icon(icon, color: cs.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      );

  /// [onTap] gets the tile's context, for the share popover's origin.
  Widget _tile(ColorScheme cs, {
    required IconData icon,
    required String title,
    required String subtitle,
    required void Function(BuildContext tile) onTap,
    bool enabled = true,
    bool subtitleError = false,
    Widget? trailing,
  }) =>
      Builder(
        builder: (tile) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          enabled: enabled,
          leading: Icon(icon,
              color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.38)),
          title: Text(title),
          subtitle: Text(subtitle,
              style: subtitleError ? TextStyle(color: cs.error) : null),
          trailing: trailing,
          onTap: () => onTap(tile),
        ),
      );

  static Rect? _originOf(BuildContext tile) {
    final box = tile.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The import's progress while it loads feeds, else how the last import
  /// or export went.
  Widget _statusLine(AppLocalizations l10n, ColorScheme cs) {
    final progress = _progress;
    final status = _status;
    final Widget? line;
    if (progress != null) {
      line = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress.total > 0 ? progress.done / progress.total : null,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 8),
          Text(l10n.importProgress(progress.done, progress.total),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ],
      );
    } else if (_busy) {
      line = LinearProgressIndicator(borderRadius: BorderRadius.circular(2));
    } else if (status != null) {
      final color = status.error ? cs.error : cs.onSurfaceVariant;
      line = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 20, color: status.error ? cs.error : cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(status.text,
              style: TextStyle(color: color, fontSize: 13, height: 1.4))),
        ],
      );
    } else {
      line = null;
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: line == null
          ? const SizedBox(width: double.infinity)
          : Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 8), child: line),
    );
  }
}
