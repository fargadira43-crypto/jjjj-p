import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

class ProjectNode {
  final String path;
  final bool isFolder;
  final String? extension;

  const ProjectNode({
    required this.path,
    required this.isFolder,
    this.extension,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'isFolder': isFolder,
        'extension': extension,
      };
}

class EditorScreen extends StatefulWidget {
  final String? initialCode;
  final String? initialFileName;
  final int? jumpToLine;
  const EditorScreen(
      {super.key, this.initialCode, this.initialFileName, this.jumpToLine});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late TextEditingController _codeController;
  late ScrollController _verticalScrollController;
  late ScrollController _lineNumbersScrollController;
  late ScrollController _horizontalScrollController;
  late ScrollController _highlightScrollController;
  late ScrollController _smartBarScrollController;
  late FocusNode _editorFocusNode;
  Timer? _autoSaveTimer;
  String projectName = "my_project";

  String _activeTab = 'HTML';
  // تصنيف الكيبورد الذكي مستقل عن الملف المفتوح.
  // تغييره يبدّل الاختصارات فقط ولا يبدّل HTML/CSS/JS داخل المحرر.
  String _smartCategory = 'HTML';

  // ملفات المشروع الثلاثة: HTML هو الملف الافتراضي عند فتح المحرر.
  final Map<String, String> _fileContents = {
    'HTML': '',
    'CSS': '',
    'JS': '',
  };
  final Map<String, String> _fileNames = {
    'HTML': 'index.html',
    'CSS': 'style.css',
    'JS': 'script.js',
  };
  final Map<String, String> _projectImages = {};
  // Custom TTF fonts uploaded from the Drag & Drop Editor's sidebar font
  // uploader. Keyed by file name (e.g. "MyFont.ttf"), value is the
  // "data:font/ttf;base64,...." payload. Exported into the project ZIP's
  // /fonts folder alongside /images — see _exportProjectZip below.
  final Map<String, String> _projectFonts = {};
  final Map<String, List<String>> _undoStacks = {
    'HTML': <String>[],
    'CSS': <String>[],
    'JS': <String>[],
  };
  final Map<String, List<String>> _redoStacks = {
    'HTML': <String>[],
    'CSS': <String>[],
    'JS': <String>[],
  };

  // ------------------------------------------------------------------
  //  MULTI-FILE SUPPORT (side navigation drawer)
  // ------------------------------------------------------------------
  // Real filename -> content, for every HTML/CSS/JS file the project has
  // — not just the single file currently open in each HTML/CSS/JS slot.
  // _fileContents/_undoStacks/_redoStacks above still work exactly as
  // before and always reflect whichever file is "open" per type; this
  // map is where every OTHER file's content lives while it's not open.
  final Map<String, String> _fileContentsMulti = {};
  final Map<String, List<String>> _undoStacksMulti = {};
  final Map<String, List<String>> _redoStacksMulti = {};
  // Which real filename is currently loaded into each type's editor slot.
  final Map<String, String> _activeFileNameByType = {
    'HTML': 'index.html',
    'CSS': 'style.css',
    'JS': 'script.js',
  };
  // Every file that exists per type, in creation order — drives the
  // drawer's file list.
  final Map<String, List<String>> _filesByType = {
    'HTML': ['index.html'],
    'CSS': ['style.css'],
    'JS': ['script.js'],
  };
  // Uploaded assets that aren't html/css/js (anything from "Upload File":
  // videos, PDFs, etc.). Images/fonts keep using _projectImages/
  // _projectFonts above so the existing export-to-ZIP folders keep
  // working unchanged; this covers everything else.
  final Map<String, String> _projectOtherAssets = {};

  // ------------------------------------------------------------------
  // HIERARCHICAL PROJECT FILE SYSTEM
  // ------------------------------------------------------------------
  // Canonical storage for the VS Code-style tree. Paths always use `/`.
  final Set<String> _projectFolders = <String>{};
  final Map<String, String> _projectCodeFiles = <String, String>{};
  final Map<String, String> _projectAssetFiles = <String, String>{};
  final Set<String> _expandedFolders = <String>{};
  String _selectedTreePath = '';
  String _selectedFolderPath = '';


  bool _isChangingFile = false;
  bool _isSplitScreen = false;
  bool _isFindOpen = false;
  late TextEditingController _findController;
  String _findQuery = '';
  int _findIndex = 0;
  List<int> _findMatches = [];
  bool _showColorBar = false;
  late WebViewController _splitPreviewController;

  final List<String> _colorPalette = const [
    '#000000',
    '#FFFFFF',
    '#FF0000',
    '#00FF00',
    '#0000FF',
    '#FFFF00',
    '#00FFFF',
    '#FF00FF',
    '#FFA500',
    '#800080',
    '#008000',
    '#808080',
    '#FFC0CB',
    '#A52A2A',
    '#008080',
    '#FFD700',
    '#4B0082',
    '#EE82EE',
    '#9192C2',
    '#1E90FF',
    '#32CD32',
    '#DC143C',
    '#00CED1',
    '#FF1493',
  ];

  // متغيرات الإضافات الجديدة
  // المشاريع الجديدة تبدأ بدون حفظ تلقائي.
  // يتم استبدال هذه القيمة عند تحميل مشروع محفوظ لديه إعداد سابق.
  bool _isAutoSaveEnabled = false;
  bool _isLightMode = false;
  bool? _autoSaveFromProjectData;
  bool _hasLoadedFileNames = false;
  bool _hasLoadedMultiFile = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    projectName = widget.initialFileName ?? "my_project";
    if (projectName.contains('.')) {
      projectName = projectName.substring(0, projectName.lastIndexOf('.'));
    }

    _loadInitialProjectData();
    _ensureHierarchicalFileSystem();

    // Default File: the primary HTML file is always named index.html
    // when the editor opens, unless a saved project already had its own
    // custom file names.
    if (!_hasLoadedFileNames) {
      _fileNames['HTML'] = 'index.html';
    }
    if (_fileContents['HTML']!.isEmpty) {
      _fileContents['HTML'] = _defaultTemplate();
    }
    // Seed the multi-file maps so the drawer's file list and the
    // classic single-file editor slots start out in sync — but only for
    // a brand-new project; a reloaded multi-file project already has
    // its own file list from _loadInitialProjectData and must not be
    // reset back down to one file per type.
    if (!_hasLoadedMultiFile) {
      _activeFileNameByType['HTML'] = _fileNames['HTML']!;
      _activeFileNameByType['CSS'] = _fileNames['CSS']!;
      _activeFileNameByType['JS'] = _fileNames['JS']!;
      _filesByType['HTML'] = [_fileNames['HTML']!];
      _filesByType['CSS'] = [_fileNames['CSS']!];
      _filesByType['JS'] = [_fileNames['JS']!];
      _fileContentsMulti[_fileNames['HTML']!] = _fileContents['HTML']!;
      _fileContentsMulti[_fileNames['CSS']!] = _fileContents['CSS']!;
      _fileContentsMulti[_fileNames['JS']!] = _fileContents['JS']!;
    } else {
      // Make sure the file the project was last showing per type is
      // actually loaded into the classic single-file cache too.
      for (final type in ['HTML', 'CSS', 'JS']) {
        final activeName = _activeFileNameByType[type]!;
        if (!_filesByType[type]!.contains(activeName)) {
          _activeFileNameByType[type] = _filesByType[type]!.first;
        }
        _fileContents[type] =
            _fileContentsMulti[_activeFileNameByType[type]!] ?? '';
        _fileNames[type] = _activeFileNameByType[type]!;
      }
    }
    _ensureHierarchicalFileSystem();
    _syncLegacyFileMaps();
    _syncLegacyAssets();
    final initialExtension =
        (widget.initialFileName ?? '').split('.').last.toLowerCase();
    if (initialExtension == 'css') {
      _activeTab = 'CSS';
    } else if (initialExtension == 'js') {
      _activeTab = 'JS';
    } else {
      _activeTab = 'HTML';
    }
    _codeController =
        TextEditingController(text: _fileContents[_activeTab] ?? '');

    _verticalScrollController = ScrollController();
    _lineNumbersScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    _highlightScrollController = ScrollController();
    _smartBarScrollController = ScrollController();
    _editorFocusNode = FocusNode();
    _findController = TextEditingController();

    _undoStacks['HTML']!.add(_fileContents['HTML']!);
    _undoStacks['CSS']!.add(_fileContents['CSS']!);
    _undoStacks['JS']!.add(_fileContents['JS']!);
    _undoStacksMulti[_fileNames['HTML']!] = _undoStacks['HTML']!;
    _undoStacksMulti[_fileNames['CSS']!] = _undoStacks['CSS']!;
    _undoStacksMulti[_fileNames['JS']!] = _undoStacks['JS']!;
    _redoStacksMulti[_fileNames['HTML']!] = _redoStacks['HTML']!;
    _redoStacksMulti[_fileNames['CSS']!] = _redoStacks['CSS']!;
    _redoStacksMulti[_fileNames['JS']!] = _redoStacks['JS']!;

    // تحميل حالة الحفظ التلقائي الخاصة بهذا المشروع والوضع النهاري للـ Editor
    _loadProjectSettings();

    // الاستماع للتغييرات في المحرر لتنفيذ الحفظ التلقائي إذا كان مفعلًا
    _codeController.addListener(_onCodeChanged);

    _verticalScrollController.addListener(() {
      if (_lineNumbersScrollController.hasClients) {
        _lineNumbersScrollController.jumpTo(_verticalScrollController.offset);
      }
      if (_highlightScrollController.hasClients &&
          (_highlightScrollController.offset - _verticalScrollController.offset)
                  .abs() >
              0.5) {
        _highlightScrollController.jumpTo(
          _verticalScrollController.offset.clamp(
            0.0,
            _highlightScrollController.position.maxScrollExtent,
          ),
        );
      }
    });

    if (widget.jumpToLine != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLine(widget.jumpToLine!);
      });
    }
  }

  // بعض الشاشات كانت ترسل JSON المشروع كاملًا إلى المحرر على أنه HTML.
  // نفكّه هنا حتى يبقى كل ملف منفصلًا ولا يظهر JSON داخل محرر HTML.
  void _loadInitialProjectData() {
    final rawCode = widget.initialCode?.trim() ?? '';
    if (rawCode.isEmpty) {
      _fileContents['HTML'] = _defaultTemplate();
      _fileContents['CSS'] = '';
      _fileContents['JS'] = '';
      return;
    }

    try {
      final decoded = jsonDecode(rawCode);
      if (decoded is Map && decoded['files'] is Map) {
        final files = decoded['files'] as Map;
        _fileContents['HTML'] = files['HTML']?.toString() ?? '';
        _fileContents['CSS'] = files['CSS']?.toString() ?? '';
        _fileContents['JS'] = files['JS']?.toString() ?? '';

        if (widget.initialFileName == null &&
            decoded['projectName'] is String) {
          projectName = decoded['projectName'] as String;
          if (projectName.contains('.')) {
            projectName =
                projectName.substring(0, projectName.lastIndexOf('.'));
          }
        }

        if (decoded['fileNames'] is Map) {
          final names = decoded['fileNames'] as Map;
          _hasLoadedFileNames = true;
          for (final tab in ['HTML', 'CSS', 'JS']) {
            final name = names[tab];
            if (name is String && name.trim().isNotEmpty) {
              _fileNames[tab] = name;
            }
          }
        }

        if (decoded['images'] is Map) {
          final images = decoded['images'] as Map;
          for (final entry in images.entries) {
            if (entry.key is String && entry.value is String) {
              _projectImages[entry.key as String] = entry.value as String;
            }
          }
        }

        if (decoded['fonts'] is Map) {
          final fonts = decoded['fonts'] as Map;
          for (final entry in fonts.entries) {
            if (entry.key is String && entry.value is String) {
              _projectFonts[entry.key as String] = entry.value as String;
            }
          }
        }

        // Multi-File Preview: restore every extra HTML/CSS/JS file (and
        // any general asset) from a project this editor itself saved
        // previously. Older saves — or a project handed off from the
        // Drag & Drop Editor — simply won't have these keys, and the
        // single HTML/CSS/JS file loaded above still works exactly as
        // before in that case.
        if (decoded['filesByType'] is Map && decoded['filesMulti'] is Map) {
          final filesByType = decoded['filesByType'] as Map;
          final filesMulti = decoded['filesMulti'] as Map;
          bool ok = false;
          for (final type in ['HTML', 'CSS', 'JS']) {
            final list = filesByType[type];
            if (list is List && list.isNotEmpty) {
              _filesByType[type] =
                  list.map((e) => e.toString()).toList(growable: true);
              ok = true;
            }
          }
          for (final entry in filesMulti.entries) {
            if (entry.key is String && entry.value is String) {
              _fileContentsMulti[entry.key as String] = entry.value as String;
            }
          }
          if (decoded['activeFileNameByType'] is Map) {
            final active = decoded['activeFileNameByType'] as Map;
            for (final type in ['HTML', 'CSS', 'JS']) {
              final name = active[type];
              if (name is String && name.trim().isNotEmpty) {
                _activeFileNameByType[type] = name;
              }
            }
          }
          if (decoded['otherAssets'] is Map) {
            final other = decoded['otherAssets'] as Map;
            for (final entry in other.entries) {
              if (entry.key is String && entry.value is String) {
                _projectOtherAssets[entry.key as String] =
                    entry.value as String;
              }
            }
          }
          _hasLoadedMultiFile = ok;
        }

        if (decoded['autoSave'] is bool) {
          _autoSaveFromProjectData = decoded['autoSave'] as bool;
        }
        if (decoded['projectFolders'] is List) {
          _projectFolders.addAll((decoded['projectFolders'] as List).map((e) => _normalizeProjectPath(e.toString())));
        }
        if (decoded['projectCodeFiles'] is Map) {
          final files = decoded['projectCodeFiles'] as Map;
          for (final e in files.entries) if (e.key is String && e.value is String) _projectCodeFiles[_normalizeProjectPath(e.key as String)] = e.value as String;
          if (_projectCodeFiles.isNotEmpty) _hasLoadedMultiFile = true;
        }
        if (decoded['projectAssetFiles'] is Map) {
          final assets = decoded['projectAssetFiles'] as Map;
          for (final e in assets.entries) if (e.key is String && e.value is String) _projectAssetFiles[_normalizeProjectPath(e.key as String)] = e.value as String;
        }
        if (decoded['expandedFolders'] is List) _expandedFolders.addAll((decoded['expandedFolders'] as List).map((e) => _normalizeProjectPath(e.toString())));
        _normalizeEmbeddedBase64Images();
        return;
      }
    } catch (_) {
      // إذا لم يكن النص JSON، فهو كود HTML عادي.
    }

    _fileContents['HTML'] = widget.initialCode!;
    _fileContents['CSS'] = '';
    _fileContents['JS'] = '';
    _normalizeEmbeddedBase64Images();
  }

  // صور Base64 المضمّنة داخل كود HTML (القادمة من شاشات أو مشاريع قديمة)
  // تبقى وظيفتها معطّلة للمحرر. نستخرجها إلى _projectImages — التي يدعمها
  // الحفظ والتصدير ZIP والمعاينة — ونستبدلها في الكود بمرجع قصير
  // images/<name>. هكذا تعمل الصور مع المشاريع المختلفة لكن نص المحرر يبقى
  // خفيفًا ويتحمل 10-20 صورة دون بطء أو تجمّد.
  void _normalizeEmbeddedBase64Images() {
    final html = _fileContents['HTML'];
    if (html == null || !html.contains('base64,')) return;

    final dataUrlPattern = RegExp(
      r'data:image/[A-Za-z0-9.+-]+;base64,([A-Za-z0-9+/=]+)',
    );

    final used = _projectImages.keys.toSet();
    final buffer = StringBuffer();
    var cursor = 0;
    var counter = 1;

    for (final match in dataUrlPattern.allMatches(html)) {
      var name = 'image_$counter.png';
      while (used.contains(name)) {
        counter++;
        name = 'image_$counter.png';
      }
      counter++;
      used.add(name);

      _projectImages[name] = match.group(0)!;
      buffer.write(html.substring(cursor, match.start));
      buffer.write('images/$name');
      cursor = match.end;
    }

    buffer.write(html.substring(cursor));
    _fileContents['HTML'] = buffer.toString();
  }

  // تحميل الإعدادات المحفوظة مسبقاً
  Future<void> _loadProjectSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // تحميل الوضع النهاري/الليلي الخاص بالمحرر العام
    bool savedLightMode = prefs.getBool('editor_light_mode') ?? false;

    // الأولوية لإعداد الحفظ المحفوظ داخل بيانات المشروع نفسها.
    // المفتاح القديم يبقى كخطة رجوع للمشاريع القديمة.
    bool savedAutoSave = _autoSaveFromProjectData ??
        prefs.getBool('auto_save_$projectName') ??
        false;

    setState(() {
      _isLightMode = savedLightMode;
      _isAutoSaveEnabled = savedAutoSave;
    });
  }

  // الحفظ التلقائي للمشروع كاملًا: HTML + CSS + JS.
  // لا يحفظ الصفحة الحالية فقط، بل يجمع آخر محتوى للملفات الثلاثة.
  void _onCodeChanged() {
    if (_isChangingFile) return;

    final code = _codeController.text;
    _fileContents[_activeTab] = code;
    _fileContentsMulti[_activeFileNameByType[_activeTab]!] = code;
    _projectCodeFiles[_activeFileNameByType[_activeTab]!] = code;

    final undo = _undoStacks[_activeTab]!;
    if (undo.isEmpty || undo.last != code) {
      undo.add(code);
      if (undo.length > 100) undo.removeAt(0);
    }
    _redoStacks[_activeTab]!.clear();

    if (_isAutoSaveEnabled) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        await _saveCurrentProjectToStorage();
      });
    }

    if (_isSplitScreen) {
      _updateSplitPreview();
    }

    if (mounted) setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureCaretVisibleHorizontally();
    });
  }

  void _switchFile(String tab) {
    if (_activeTab == tab) return;

    _fileContents[_activeTab] = _codeController.text;
    _fileContentsMulti[_activeFileNameByType[_activeTab]!] =
        _codeController.text;
    _projectCodeFiles[_activeFileNameByType[_activeTab]!] = _codeController.text;

    if (_isAutoSaveEnabled) {
      _autoSaveTimer?.cancel();
      _saveCurrentProjectToStorage();
    }

    _activeTab = tab;

    _isChangingFile = true;
    _codeController.text = _fileContents[tab] ?? '';
    _codeController.selection =
        TextSelection.collapsed(offset: _codeController.text.length);
    _isChangingFile = false;

    _undoStacks[tab] ??= <String>[_codeController.text];
    if (_undoStacks[tab]!.isEmpty) {
      _undoStacks[tab]!.add(_codeController.text);
    }

    _findQuery = '';
    _findController.clear();
    _findMatches = [];
    _findIndex = 0;

    setState(() {});
    if (_isSplitScreen) _updateSplitPreview();
  }

  // Multi-File Preview support: opens any real project file (there can
  // be several per type — index.html, about.html, style.css, ...),
  // saving whatever was open before into its own slot in
  // _fileContentsMulti/_undoStacksMulti first, exactly like _switchFile
  // does for the classic single-file-per-type case, but also handling
  // switching to a *different file of the same type* (which _switchFile
  // alone can't do, since it early-returns when the type doesn't change).
  String _normalizeProjectPath(String raw) {
    var value = raw.trim().replaceAll('\\', '/');
    while (value.startsWith('/')) value = value.substring(1);
    while (value.contains('//')) value = value.replaceAll('//', '/');
    final parts = <String>[];
    for (final part in value.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    return parts.join('/');
  }

  String _parentPath(String path) {
    final normalized = _normalizeProjectPath(path);
    final i = normalized.lastIndexOf('/');
    return i <= 0 ? '' : normalized.substring(0, i);
  }

  String _baseName(String path) {
    final normalized = _normalizeProjectPath(path);
    final i = normalized.lastIndexOf('/');
    return i == -1 ? normalized : normalized.substring(i + 1);
  }

  String _extensionOf(String path) {
    final name = _baseName(path);
    final i = name.lastIndexOf('.');
    return i == -1 ? '' : name.substring(i + 1).toLowerCase();
  }

  bool _isCodePath(String path) => const {'html', 'css', 'js'}.contains(_extensionOf(path));

  void _ensureFolderParents(String path) {
    var parent = _parentPath(path);
    while (parent.isNotEmpty) {
      _projectFolders.add(parent);
      parent = _parentPath(parent);
    }
  }

  void _ensureHierarchicalFileSystem() {
    // Migrate the old flat multi-file structure exactly once into paths.
    if (_projectCodeFiles.isEmpty) {
      for (final type in ['HTML', 'CSS', 'JS']) {
        for (final name in (_filesByType[type] ?? const <String>[])) {
          final path = _normalizeProjectPath(name);
          final content = _fileContentsMulti[name] ??
              (name == _activeFileNameByType[type] ? _fileContents[type] : null) ?? '';
          _projectCodeFiles[path] = content;
          _ensureFolderParents(path);
        }
      }
    }
    for (final e in _projectImages.entries) {
      _projectAssetFiles.putIfAbsent('images/${_normalizeProjectPath(e.key)}', () => e.value);
    }
    for (final e in _projectFonts.entries) {
      _projectAssetFiles.putIfAbsent('fonts/${_normalizeProjectPath(e.key)}', () => e.value);
    }
    for (final e in _projectOtherAssets.entries) {
      _projectAssetFiles.putIfAbsent('assets/${_normalizeProjectPath(e.key)}', () => e.value);
    }
    for (final path in _projectCodeFiles.keys) _ensureFolderParents(path);
    for (final path in _projectAssetFiles.keys) _ensureFolderParents(path);
  }

  void _syncLegacyFileMaps() {
    for (final type in ['HTML', 'CSS', 'JS']) {
      _filesByType[type]!.clear();
    }
    _fileContentsMulti.clear();
    for (final path in _projectCodeFiles.keys) {
      final type = _typeOfFilename(path);
      _filesByType[type]!.add(path);
      _fileContentsMulti[path] = _projectCodeFiles[path] ?? '';
    }
    for (final type in ['HTML', 'CSS', 'JS']) {
      _filesByType[type]!.sort();
      final active = _activeFileNameByType[type];
      if (active == null || !_projectCodeFiles.containsKey(active)) {
        _activeFileNameByType[type] = _filesByType[type]!.isNotEmpty
            ? _filesByType[type]!.first
            : '';
      }
      _fileNames[type] = _activeFileNameByType[type] ?? '';
      _fileContents[type] = _projectCodeFiles[_fileNames[type]] ?? '';
    }
  }

  void _putProjectCodeFile(String path, String content) {
    final normalized = _normalizeProjectPath(path);
    _projectCodeFiles[normalized] = content;
    _ensureFolderParents(normalized);
    _syncLegacyFileMaps();
  }

  void _putProjectAsset(String path, String dataUrl) {
    final normalized = _normalizeProjectPath(path);
    _projectAssetFiles[normalized] = dataUrl;
    _ensureFolderParents(normalized);
    _syncLegacyAssets();
  }

  void _syncLegacyAssets() {
    _projectImages.clear();
    _projectFonts.clear();
    _projectOtherAssets.clear();
    for (final e in _projectAssetFiles.entries) {
      final ext = _extensionOf(e.key);
      final name = _baseName(e.key);
      if (const {'png','jpg','jpeg','gif','webp','svg'}.contains(ext)) {
        _projectImages[e.key.startsWith('images/') ? name : e.key] = e.value;
      } else if (const {'ttf','otf','woff','woff2'}.contains(ext)) {
        _projectFonts[e.key.startsWith('fonts/') ? name : e.key] = e.value;
      } else {
        _projectOtherAssets[e.key.startsWith('assets/') ? name : e.key] = e.value;
      }
    }
  }

  String _resolveProjectPath(String fromFile, String reference) {
    var ref = reference.trim();
    if (ref.isEmpty || ref.startsWith('data:') || ref.startsWith('http://') ||
        ref.startsWith('https://') || ref.startsWith('//') || ref.startsWith('#') ||
        ref.startsWith('mailto:') || ref.startsWith('tel:') || ref.startsWith('javascript:')) {
      return ref;
    }
    ref = Uri.decodeComponent(ref.split('#').first.split('?').first);
    if (ref.startsWith('/')) ref = ref.substring(1);
    final base = _parentPath(fromFile);
    return _normalizeProjectPath(base.isEmpty ? ref : '$base/$ref');
  }

  String _mimeForPath(String path) {
    switch (_extensionOf(path)) {
      case 'html': return 'text/html';
      case 'css': return 'text/css';
      case 'js': return 'text/javascript';
      case 'svg': return 'image/svg+xml';
      case 'png': return 'image/png';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'webm': return 'video/webm';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'pdf': return 'application/pdf';
      case 'ttf': return 'font/ttf';
      case 'otf': return 'font/otf';
      case 'woff': return 'font/woff';
      case 'woff2': return 'font/woff2';
      default: return 'application/octet-stream';
    }
  }

  String _dataUrlForProjectPath(String path) => _projectAssetFiles[path] ?? '';

  String _rewritePreviewReferences(String source, String currentFile) {
    var result = source;
    final allAssets = Map<String, String>.from(_projectAssetFiles);
    final allCode = Map<String, String>.from(_projectCodeFiles);
    final replacements = <String, String>{};
    for (final e in allAssets.entries) {
      replacements[e.key] = e.value;
      final relative = _relativeProjectPath(currentFile, e.key);
      replacements[relative] = e.value;
      replacements['./$relative'] = e.value;
      replacements['/$e.key'] = e.value;
    }
    for (final e in allCode.entries) {
      final relative = _relativeProjectPath(currentFile, e.key);
      // Code files are inlined by the preview engine where the browser would fetch them.
      replacements[e.key] = e.value;
      replacements[relative] = e.value;
      replacements['./$relative'] = e.value;
    }
    return result;
  }

  String _relativeProjectPath(String fromFile, String target) {
    final from = _normalizeProjectPath(fromFile).split('/')..removeLast();
    final to = _normalizeProjectPath(target).split('/');
    while (from.isNotEmpty && to.isNotEmpty && from.first == to.first) {
      from.removeAt(0); to.removeAt(0);
    }
    return '${List.filled(from.length, '..').join('/')}${from.isNotEmpty && to.isNotEmpty ? '/' : ''}${to.join('/')}';
  }

  String _typeOfFilename(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot == -1 ? '' : filename.substring(dot + 1).toLowerCase();
    if (ext == 'css') return 'CSS';
    if (ext == 'js') return 'JS';
    return 'HTML';
  }

  void _openMultiFile(String filename) {
    final path = _normalizeProjectPath(filename);
    if (!_isCodePath(path)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Only .html, .css, and .js files can be opened in the code editor.'),
      ));
      return;
    }
    _ensureHierarchicalFileSystem();
    final String type = _typeOfFilename(path);
    final String? currentFile = _activeFileNameByType[_activeTab];
    if (currentFile != null && currentFile.isNotEmpty) {
      _projectCodeFiles[currentFile] = _codeController.text;
      _fileContentsMulti[currentFile] = _codeController.text;
      _fileContents[_activeTab] = _codeController.text;
    }
    _activeTab = type;
    _activeFileNameByType[type] = path;
    _fileNames[type] = path;
    final content = _projectCodeFiles[path] ?? _fileContentsMulti[path] ?? '';
    _fileContents[type] = content;
    _selectedTreePath = path;
    _selectedFolderPath = _parentPath(path);
    _isChangingFile = true;
    _codeController.text = content;
    _codeController.selection = TextSelection.collapsed(offset: content.length);
    _isChangingFile = false;
    _undoStacksMulti.putIfAbsent(path, () => <String>[content]);
    _redoStacksMulti.putIfAbsent(path, () => <String>[]);
    _undoStacks[type] = _undoStacksMulti[path]!;
    _redoStacks[type] = _redoStacksMulti[path]!;
    _findQuery = '';
    _findController.clear();
    _findMatches = [];
    _findIndex = 0;
    setState(() {});
    if (_isSplitScreen) _updateSplitPreview();
  }

  void _undo() {
    final stack = _undoStacks[_activeTab]!;
    if (stack.length <= 1) return;

    final current = _codeController.text;
    _redoStacks[_activeTab]!.add(current);
    stack.removeLast();

    _isChangingFile = true;
    _codeController.text = stack.last;
    _codeController.selection =
        TextSelection.collapsed(offset: _codeController.text.length);
    _isChangingFile = false;

    _fileContents[_activeTab] = _codeController.text;
    _fileContentsMulti[_activeFileNameByType[_activeTab]!] =
        _codeController.text;
    _projectCodeFiles[_activeFileNameByType[_activeTab]!] = _codeController.text;
    if (_isSplitScreen) _updateSplitPreview();
    setState(() {});
  }

  void _redo() {
    final redo = _redoStacks[_activeTab]!;
    if (redo.isEmpty) return;

    final next = redo.removeLast();
    _undoStacks[_activeTab]!.add(next);

    _isChangingFile = true;
    _codeController.text = next;
    _codeController.selection =
        TextSelection.collapsed(offset: _codeController.text.length);
    _isChangingFile = false;

    _fileContents[_activeTab] = next;
    _fileContentsMulti[_activeFileNameByType[_activeTab]!] = next;
    _projectCodeFiles[_activeFileNameByType[_activeTab]!] = next;
    if (_isSplitScreen) _updateSplitPreview();
    setState(() {});
  }

  void _showFindDialog() {
    setState(() {
      _isFindOpen = true;
      _findController.clear();
      _findQuery = '';
      _findMatches = [];
      _findIndex = 0;
    });
  }

  void _closeFind() {
    setState(() {
      _isFindOpen = false;
      _findController.clear();
      _findQuery = '';
      _findMatches = [];
      _findIndex = 0;
    });
  }

  void _updateFindMatches(String query) {
    _findQuery = query;
    _findMatches = [];
    _findIndex = 0;
    if (query.isNotEmpty) {
      final text = _codeController.text.toLowerCase();
      final needle = query.toLowerCase();
      int startAt = 0;
      while (true) {
        final index = text.indexOf(needle, startAt);
        if (index == -1) break;
        _findMatches.add(index);
        startAt = index + needle.length;
      }
      if (_findMatches.isNotEmpty) _selectFindMatch(0);
    }
    setState(() {});
  }

  // لا يتم البحث أثناء الكتابة. ينفّذ البحث فقط بعد اكتمال الكلمة
  // والضغط على زر البحث أو زر Enter من لوحة المفاتيح.
  void _runFindSearch() {
    _updateFindMatches(_findController.text.trim());
  }

  void _selectFindMatch(int index) {
    if (_findMatches.isEmpty || _findQuery.isEmpty) return;

    _findIndex = index % _findMatches.length;
    final start = _findMatches[_findIndex];
    final end = start + _findQuery.length;

    // ينقل المؤشر إلى الكلمة ويحددها داخل المحرر.
    _editorFocusNode.requestFocus();
    _codeController.selection = TextSelection(
      baseOffset: start,
      extentOffset: end,
    );

    // ينقل المحرر تلقائيًا إلى مكان الكلمة المحددة.
    final line = _codeController.text.substring(0, start).split('\n').length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToLine(line);
    });
  }

  void _nextFind() {
    if (_findMatches.isEmpty) return;
    _selectFindMatch(_findIndex + 1);
    setState(() {});
  }

  void _previousFind() {
    if (_findMatches.isEmpty) return;
    _selectFindMatch(
        (_findIndex - 1 + _findMatches.length) % _findMatches.length);
    setState(() {});
  }

  // Robust Multi-File Preview: bundles every HTML/CSS/JS file the
  // project has into one self-contained document a WebView can render
  // (WebView.loadHtmlString can't fetch other files from disk, so this
  // is still the entry point — it just now looks at *all* files of each
  // type instead of only the single active one).
  String _buildPreviewHtml() {
    _ensureHierarchicalFileSystem();
    final htmlPaths = _projectCodeFiles.keys.where((p) => _extensionOf(p) == 'html').toList()..sort();
    final entryFile = htmlPaths.contains('index.html')
        ? 'index.html'
        : (_activeFileNameByType['HTML']?.isNotEmpty == true
            ? _activeFileNameByType['HTML']!
            : (htmlPaths.isNotEmpty ? htmlPaths.first : ''));
    var result = _projectCodeFiles[entryFile] ?? _fileContents['HTML'] ?? '';
    if (entryFile.isEmpty) return result;

    // Resolve linked stylesheets and scripts by their real project paths.
    final linkRe = RegExp(r"""(<link\b[^>]*?href\s*=\s*[\"'])([^\"']+)([\"'][^>]*>)""", caseSensitive: false);
    result = result.replaceAllMapped(linkRe, (m) {
      final ref = m.group(2)!;
      final resolved = _resolveProjectPath(entryFile, ref);
      final css = _projectCodeFiles[resolved];
      if (css == null || _extensionOf(resolved) != 'css') return m.group(0)!;
      final rewrittenCss = css.replaceAllMapped(RegExp(r'''url\(\s*[\"']?([^\)\"']+)[\"']?\s*\)'''), (u) {
        final assetPath = _resolveProjectPath(resolved, u.group(1)!);
        final data = _dataUrlForProjectPath(assetPath);
        return data.isNotEmpty ? 'url("$data")' : u.group(0)!;
      });
      return '<style data-project-file="$resolved">\n$rewrittenCss\n</style>';
    });
    final scriptRe = RegExp(r"""(<script\b[^>]*?src\s*=\s*[\"'])([^\"']+)([\"'][^>]*>)(?:\s*</script>)?""", caseSensitive: false);
    result = result.replaceAllMapped(scriptRe, (m) {
      final ref = m.group(2)!;
      final resolved = _resolveProjectPath(entryFile, ref);
      final js = _projectCodeFiles[resolved];
      if (js == null || _extensionOf(resolved) != 'js') return m.group(0)!;
      final safeJs = _prepareJavaScriptForPreview(js);
      return '<script data-project-file="$resolved">\n$safeJs\n</script>';
    });

    // Inline remaining CSS/JS files that were created but are not explicitly linked,
    // preserving project creation order. This makes multi-file projects usable while
    // still respecting explicit <link>/<script src> relationships.
    final cssUnlinked = _projectCodeFiles.entries.where((e) => _extensionOf(e.key) == 'css' &&
        !result.contains('data-project-file="${e.key}"')).toList();
    if (cssUnlinked.isNotEmpty) {
      final block = cssUnlinked.map((e) => '/* --- ${e.key} --- */\n${e.value}').join('\n');
      final style = '<style data-project-bundle="css">\n$block\n</style>';
      result = result.contains('</head>') ? result.replaceFirst('</head>', '$style\n</head>') : '$style\n$result';
    }
    final jsUnlinked = _projectCodeFiles.entries.where((e) => _extensionOf(e.key) == 'js' &&
        !result.contains('data-project-file="${e.key}"')).toList();
    if (jsUnlinked.isNotEmpty) {
      final block = jsUnlinked.map((e) => '// --- ${e.key} ---\n${_prepareJavaScriptForPreview(e.value)}').join('\n');
      final script = '<script data-project-bundle="js">\n$block\n</script>';
      result = result.contains('</body>') ? result.replaceFirst('</body>', '$script\n</body>') : '$result\n$script';
    }

    // Replace local asset URLs using the same resolver used by export.
    final attrRe = RegExp(r"""(\b(?:src|href|poster|data|srcset|content)\s*=\s*[\"'])([^\"']+)([\"'])""", caseSensitive: false);
    result = result.replaceAllMapped(attrRe, (m) {
      final ref = m.group(2)!;
      final resolved = _resolveProjectPath(entryFile, ref);
      final data = _dataUrlForProjectPath(resolved);
      return data.isNotEmpty ? '${m.group(1)}$data${m.group(3)}' : m.group(0)!;
    });
    // CSS url(...) references inside inline/external CSS.
    result = result.replaceAllMapped(RegExp(r"""url\(\s*[\"']?([^\)\"']+)[\"']?\s*\)""", caseSensitive: false), (m) {
      final ref = m.group(1)!;
      final resolved = _resolveProjectPath(entryFile, ref);
      final data = _dataUrlForProjectPath(resolved);
      return data.isNotEmpty ? 'url("$data")' : m.group(0)!;
    });

    // Fonts are assets too; no special folder assumption is required anymore.
    return result;
  }

  void _updateSplitPreview() {
    if (!_isSplitScreen) return;
    Future.microtask(() {
      if (!mounted) return;
      _splitPreviewController.loadHtmlString(_buildPreviewHtml());
    });
  }

  // Safely prepares user JavaScript for the live preview.
  // Loop guards are inserted without adding new lines, so existing error
  // locations remain aligned with the user's original JavaScript.
  String _prepareJavaScriptForPreview(String source) {
    final obviousInfiniteLoopMatch = RegExp(
      r'\bwhile\s*\(\s*(?:true|1)\s*\)(?!\s*\{)|'
      r'\bfor\s*\(\s*;\s*;\s*\)(?!\s*\{)',
      multiLine: true,
    ).firstMatch(source);

    if (obviousInfiniteLoopMatch != null) {
      final line = source
          .substring(0, obviousInfiniteLoopMatch.start)
          .split('\n')
          .length;
      return '__swmLoopGuard($line);';
    }

    int? findLoopBodyBrace(int openParen) {
      int depth = 0;
      String? quote;
      bool escaped = false;
      bool lineComment = false;
      bool blockComment = false;

      for (int j = openParen; j < source.length; j++) {
        final c = source[j];
        final next = j + 1 < source.length ? source[j + 1] : '';

        if (lineComment) {
          if (c == '\n') lineComment = false;
          continue;
        }
        if (blockComment) {
          if (c == '*' && next == '/') {
            blockComment = false;
            j++;
          }
          continue;
        }
        if (quote != null) {
          if (escaped) {
            escaped = false;
          } else if (c == '\\') {
            escaped = true;
          } else if (c == quote) {
            quote = null;
          }
          continue;
        }
        if (c == '/' && next == '/') {
          lineComment = true;
          j++;
          continue;
        }
        if (c == '/' && next == '*') {
          blockComment = true;
          j++;
          continue;
        }
        if (c == '"' || c == "'" || c == '`') {
          quote = c;
          continue;
        }

        if (c == '(') {
          depth++;
        } else if (c == ')') {
          depth--;
          if (depth == 0) {
            int k = j + 1;
            while (k < source.length &&
                (source[k] == ' ' ||
                    source[k] == '\t' ||
                    source[k] == '\r' ||
                    source[k] == '\n')) {
              k++;
            }
            return k < source.length && source[k] == '{' ? k : null;
          }
        }
      }
      return null;
    }

    bool isIdentifierChar(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

    final out = StringBuffer();
    int i = 0;

    while (i < source.length) {
      final c = source[i];
      final next = i + 1 < source.length ? source[i + 1] : '';

      // Preserve strings and comments verbatim so words such as "while"
      // inside text are never modified.
      if (c == '/' && next == '/') {
        final end = source.indexOf('\n', i);
        if (end == -1) {
          out.write(source.substring(i));
          break;
        }
        out.write(source.substring(i, end));
        i = end;
        continue;
      }
      if (c == '/' && next == '*') {
        final end = source.indexOf('*/', i + 2);
        if (end == -1) {
          out.write(source.substring(i));
          break;
        }
        out.write(source.substring(i, end + 2));
        i = end + 2;
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        final quote = c;
        int j = i + 1;
        bool escaped = false;
        while (j < source.length) {
          final ch = source[j];
          if (escaped) {
            escaped = false;
          } else if (ch == '\\') {
            escaped = true;
          } else if (ch == quote) {
            j++;
            break;
          }
          j++;
        }
        out.write(source.substring(i, j));
        i = j;
        continue;
      }

      String? keyword;
      if (source.startsWith('while', i) ||
          source.startsWith('for', i) ||
          source.startsWith('do', i)) {
        final candidate = source.startsWith('while', i)
            ? 'while'
            : source.startsWith('for', i)
                ? 'for'
                : 'do';
        final before = i == 0 ? '' : source[i - 1];
        final afterIndex = i + candidate.length;
        final after = afterIndex < source.length ? source[afterIndex] : '';
        if (!isIdentifierChar(before) && !isIdentifierChar(after)) {
          keyword = candidate;
        }
      }

      if (keyword != null) {
        int cursor = i + keyword.length;
        while (cursor < source.length &&
            (source[cursor] == ' ' ||
                source[cursor] == '\t' ||
                source[cursor] == '\r' ||
                source[cursor] == '\n')) {
          cursor++;
        }

        if (keyword == 'do') {
          if (cursor < source.length && source[cursor] == '{') {
            final loopLine = source.substring(0, cursor).split('\n').length;
            out.write(source.substring(i, cursor + 1));
            out.write('__swmLoopGuard($loopLine);');
            i = cursor + 1;
            continue;
          }
        } else if (cursor < source.length && source[cursor] == '(') {
          final brace = findLoopBodyBrace(cursor);
          if (brace != null) {
            final loopLine = source.substring(0, brace).split('\n').length;
            out.write(source.substring(i, brace + 1));
            out.write('__swmLoopGuard($loopLine);');
            i = brace + 1;
            continue;
          }
        }
      }

      out.write(c);
      i++;
    }

    return out.toString();
  }

  // Keeps the editor wide enough for long URLs, titles and other unbroken
  // text. The width is based on the longest source line and grows as needed.
  double _editorContentWidth(String source) {
    int longestLine = 1;
    for (final line in source.split('\n')) {
      if (line.length > longestLine) longestLine = line.length;
    }

    final estimatedWidth = longestLine * 8.5 + 24.0;
    return estimatedWidth.clamp(1200.0, 100000.0).toDouble();
  }

  // Keeps the caret visible when typing at the end of a very long line.
  void _ensureCaretVisibleHorizontally() {
    if (!_horizontalScrollController.hasClients) return;

    final selection = _codeController.selection;
    if (!selection.isValid || selection.baseOffset < 0) return;

    final beforeCaret = _codeController.text.substring(0, selection.baseOffset);
    final lastNewLine = beforeCaret.lastIndexOf('\n');
    final column = selection.baseOffset - lastNewLine - 1;
    final caretX = column * 8.5;
    final position = _horizontalScrollController.position;
    const margin = 40.0;

    double target = position.pixels;
    if (caretX < position.pixels + margin) {
      target = caretX - margin;
    } else if (caretX > position.pixels + position.viewportDimension - margin) {
      target = caretX - position.viewportDimension + margin;
    }

    target = target.clamp(0.0, position.maxScrollExtent).toDouble();
    if ((target - position.pixels).abs() > 1.0) {
      _horizontalScrollController.jumpTo(target);
    }
  }

  void _toggleSplitScreen() {
    setState(() {
      _isSplitScreen = !_isSplitScreen;
    });

    if (_isSplitScreen) {
      _splitPreviewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);
      _updateSplitPreview();
    }
  }

  String _fileExtension(String tab) {
    switch (tab) {
      case 'CSS':
        return '.css';
      case 'JS':
        return '.js';
      default:
        return '.html';
    }
  }

  String get _baseProjectName {
    final trimmed = projectName.trim();
    if (trimmed.isEmpty) return 'my_project';
    final dot = trimmed.lastIndexOf('.');
    return dot > 0 ? trimmed.substring(0, dot) : trimmed;
  }

  // Keep the existing TextField for input, selection, undo and IME support.
  // The colored code is painted underneath it, so no editor package is needed.
  Color _syntaxColorForActiveTab() {
    switch (_activeTab) {
      case 'CSS':
        return _isLightMode ? const Color(0xFF237A36) : const Color(0xFF63D471);
      case 'JS':
        return _isLightMode ? const Color(0xFF9A5B00) : const Color(0xFFFFC857);
      default:
        return _isLightMode ? const Color(0xFF1261A0) : const Color(0xFF5EA7FF);
    }
  }

  TextSpan _highlightCode(String source) {
    final categoryColor = _syntaxColorForActiveTab();
    final spans = <TextSpan>[];
    final tokenPattern = RegExp(
      r'<!--[\s\S]*?-->|/\*[\s\S]*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|'
      r"'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|#[A-Za-z_][\w-]*|"
      r'[A-Za-z_][\w-]*(?=\s*:)|\b[A-Za-z_$][\w$]*\b',
    );
    final htmlTags = <String>{
      "!DOCTYPE html",
      'html',
      'head',
      'body',
      'title',
      'meta',
      'link',
      'style',
      'script',
      'div',
      'span',
      'p',
      'a',
      'img',
      'button',
      'form',
      'input',
      'label',
      'section',
      'header',
      'footer',
      'main',
      'nav',
      'ul',
      'ol',
      'li',
      'table',
      'thead',
      'tbody',
      'tr',
      'th',
      'td',
      'h1',
      'h2',
      'h3',
      'br',
    };
    final cssKeywords = <String>{
      'box-sizing',
      'board-bg',
      'accent',
      'border-box',
      'font-family',
      'min-height',
      'max-width',
      'text-align',
      'margin-bottom',
      'cursor',
      'border-color',
      'flex-wrap',
      'margin-top',
      'grid-template-columns',
      'grid-template-rows',
      'max-height',
      'overflow',
      'user-select',
      'outline',
      'outline-offset',
      'inset',
      'min-width',
      'padding-top',
      'padding-bottom',
      'padding-left',
      'padding-right',
      'text-decoration',
      'tile-gap',
      'tile-rows',
      'tile-columns',
      'tile-auto-flow',
      'tile-template-areas',
      'tile-template-rows',
      'tile-template-columns',
      'tile-template',
      'tile-auto-rows',
      'tile-auto-columns',
      'tile-radius',
      'tile-shadow',
      'tile-border',
      'tile-background',
      'tile-color',
      'text-transform',
      'tile-transform',
      'tile-bg',
      'tile-text',
      'accent-color',
      'empty-bg',
      'webkit-tap-highlight-color',
      'border-style',
      'border-width',
      'border-top',
      'border-right',
      'border-bottom',
      'border-left',
      'border-top-left-radius',
      'border-top-right-radius',
      'border-bottom-left-radius',
      'border-bottom-right-radius',
      'border-image',
      'border-image-source',
      'border-image-slice',
      'border-image-width',
      'border-image-outset',
      'border-image-repeat',
      'border-collapse',
      'border-spacing',
      'font-style',
      'text-shadow',
      'background-image',
      'background-repeat',
      'background-position',
      'background-size',
      'flex-grow',
      'flex-shrink',
      'flex-basis',
      'align-self',
      'order',
      'margin-left',
      'margin-right',
      'aspect-ratio',
      'grid-template',
      'grid-template-areas',
      'background-clip',
      'background-origin',
      'background-attachment',
      'background-blend-mode',
      'background-repeat-x',
      'background-repeat-y',
      'background-position-x',
      'background-position-y',
      'background-size-x',
      'background-size-y',
      'background-image-source',
      'background-image-repeat',
      'background-image-position',
      'background-image-size',
      'background-image-clip',
      'background-image-origin',
      'background-image-attachment',
      'background-image-blend-mode',
      'background-image-repeat-x',
      'background-image-repeat-y',
      'background-image-position-x',
      'background-image-position-y',
      'background-image-size-x',
      'background-image-size-y',
      'background-image-clip-x',
      'background-image-clip-y',
      'background-image-origin-x',
      'background-image-origin-y',
      'background-image-attachment-x',
      'background-image-attachment-y',
      'background-image-blend-mode-x',
      'background-image-blend-mode-y',
      'list-style',
      'list-style-type',
      'list-style-position',
      'list-style-image',
      'text-overflow',
      'white-space',
      'word-wrap',
      'word-break',
      'overflow-wrap',
      'hyphens',
      'text-indent',
      'letter-spacing',
      'word-spacing',
      'text-decoration-line',
      'text-decoration-style',
      'text-decoration-color',
      'perspective',
      'perspective-origin',
      'backface-visibility',
      'transform-style',
      'transform-origin',
      'animation-name',
      'animation-duration',
      'animation-timing-function',
      'animation-delay',
      'animation-iteration-count',
      'animation-direction',
      'animation-fill-mode',
      'animation-play-state',
      'transition-property',
      'transition-duration',
      'transition-timing-function',
      'transition-delay',
      'will-change',
      'pointer-events',
      'background-secondary',
      'canvas-color',
      'text-secondary',
      'text-tertiary',
      'text-quaternary',
      'text-quinary',
      'text-senary',
      'text-septenary',
      'text-octonary',
      'text-nonary',
      'text-denary',
      'text-undenary',
      'text-duodenary',
      'text-tridenary',
      'text-tetradenary',
      'text-pentadenary',
      'text-hexadenary',
      'text-heptadenary',
      'text-octodenary',
      'text-nonadenary',
      'text-icosenary',
      'text-icosidenary',
      'text-icositriadenary',
      'text-icositetraedenary',
      'text-icosipentadenary',
      'text-icosihexadenary',
      'text-icosiheptadenary',
      'text-icosioctodenary',
      'text-icosinonadenary',
      'text-tricenary',
      'text-tetracenary',
      'text-pentacenary',
      'text-hexacenary',
      'text-heptacenary',
      'text-octacenary',
      'text-nonacenary',
      'text-quadragenary',
      'text-quadragintenary',
      'text-quadragintidenary',
      'text-quadragintitriadenary',
      'text-quadragintitetradenary',
      'text-quadragintipentadenary',
      'text-quadragintihexadenary',
      'size',
      'sidebar-color',
      'button-color',
      'hover-color',
      'active-color',
      'focus-color',
      'to'
          'var',
      'from',
      'content',
      'display',
      'position',
      'top',
      'right',
      'bottom',
      'left',
      'width',
      'height',
      'margin',
      'padding',
      'color',
      'background',
      'background-color',
      'font',
      'font-size',
      'font-weight',
      'line-height',
      'border',
      'border-radius',
      'box-shadow',
      'flex',
      'flex-direction',
      'justify-content',
      'align-items',
      'grid',
      'gap',
      'opacity',
      'transform',
      'transition',
      'animation',
      'z-index',
    };
    final jsKeywords = <String>{
      'break',
      'case',
      'catch',
      'class',
      'const',
      'continue',
      'debugger',
      'default',
      'delete',
      'do',
      'else',
      'export',
      'extends',
      'finally',
      'for',
      'from',
      'function',
      'if',
      'import',
      'in',
      'instanceof',
      'let',
      'new',
      'of',
      'return',
      'static',
      'super',
      'switch',
      'this',
      'throw',
      'try',
      'typeof',
      'var',
      'void',
      'while',
      'with',
      'yield',
      'async',
      'await',
      'true',
      'false',
      'null',
      'undefined',
      'document',
      'window',
      'console',
      'Array',
      'Object',
      'String',
      'Number',
      'pop',
      'push',
      'forEach',
    };
    void addPlain(String text) {
      if (text.isNotEmpty) spans.add(TextSpan(text: text));
    }

    int cursor = 0;
    for (final match in tokenPattern.allMatches(source)) {
      addPlain(source.substring(cursor, match.start));
      final token = match.group(0)!;
      Color? color;
      if (token.startsWith('<!--') ||
          token.startsWith('/*') ||
          token.startsWith('//')) {
        color = _isLightMode ? const Color(0xFF687078) : Colors.grey;
        // Do not change font style here: the input layer must use the same
        // glyph metrics as the highlighted layer.
      } else if (token.startsWith('"') ||
          token.startsWith("'") ||
          token.startsWith('`')) {
        color =
            _isLightMode ? const Color(0xFF9A286F) : const Color(0xFFE6A8D7);
      } else if (_activeTab == 'HTML') {
        final tagName = token.replaceFirst(RegExp(r'^</?'), '').toLowerCase();
        color = htmlTags.contains(tagName) || token.startsWith('</')
            ? categoryColor
            : (_isLightMode
                ? const Color(0xFF40566F)
                : const Color(0xFFB8C7E0));
      } else if (_activeTab == 'CSS') {
        color = cssKeywords.contains(token.toLowerCase())
            ? categoryColor
            : (token.startsWith('#')
                ? (_isLightMode
                    ? const Color(0xFF9A286F)
                    : const Color(0xFFE6A8D7))
                : null);
      } else if (jsKeywords.contains(token)) {
        color = categoryColor;
      }
      spans.add(TextSpan(
        text: token,
        // IMPORTANT: keep font metrics identical to the transparent TextField.
        // Only the color is allowed to change. Different font weights/styles
        // change glyph widths and make the visible text drift from the cursor.
        style: color == null ? null : TextStyle(color: color),
      ));
      cursor = match.end;
    }
    addPlain(source.substring(cursor));
    return TextSpan(
      style: TextStyle(
        color: _isLightMode ? const Color(0xFF222222) : const Color(0xFFF8F8F2),
        fontFamily: 'monospace',
        fontSize: 14,
        height: 1.4,
      ),
      children: spans,
    );
  }

  Future<void> _renameCurrentFile() async {
    final extension = _fileExtension(_activeTab);
    final currentName = _fileNames[_activeTab] ?? '$_baseProjectName$extension';

    final controller = TextEditingController(
      text: currentName.endsWith(extension)
          ? currentName.substring(0, currentName.length - extension.length)
          : currentName,
    );

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Rename $_activeTab',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'File name',
            hintStyle: const TextStyle(color: Colors.grey),
            suffixText: extension,
            suffixStyle: const TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final base = controller.text.trim().replaceAll(
                    RegExp(r'[\\/:*?"<>|]'),
                    '_',
                  );
              if (base.isNotEmpty) {
                _fileNames[_activeTab] = '$base$extension';
                setState(() {});
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentProjectToStorage() async {
    if (_activeFileNameByType[_activeTab]?.isNotEmpty == true) {
      _projectCodeFiles[_activeFileNameByType[_activeTab]!] = _codeController.text;
    }
    _ensureHierarchicalFileSystem();
    _syncLegacyFileMaps();
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'projectName': projectName,
      'files': _fileContents,
      'fileNames': _fileNames,
      'images': _projectImages,
      'fonts': _projectFonts,
      'autoSave': _isAutoSaveEnabled,
      'filesMulti': _fileContentsMulti,
      'filesByType': _filesByType,
      'activeFileNameByType': _activeFileNameByType,
      'otherAssets': _projectOtherAssets,
      'projectFolders': _projectFolders.toList(),
      'projectCodeFiles': _projectCodeFiles,
      'projectAssetFiles': _projectAssetFiles,
      'expandedFolders': _expandedFolders.toList(),
    });
    List<String> savedProjects = prefs.getStringList('projects_list') ?? [];
    savedProjects.removeWhere((p) => p.startsWith("$projectName|||"));
    savedProjects.add("$projectName|||$data");
    await prefs.setStringList('projects_list', savedProjects);
  }

  Future<void> _exportProjectZip() async {
    try {
      await _saveCurrentProjectToStorage();
      _ensureHierarchicalFileSystem();
      final archive = Archive();
      for (final e in _projectCodeFiles.entries) {
        final bytes = utf8.encode(e.value);
        archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
      }
      for (final e in _projectAssetFiles.entries) {
        final comma = e.value.indexOf(',');
        if (comma < 0) continue;
        final bytes = base64Decode(e.value.substring(comma + 1));
        archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
      }
      if (archive.files.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to export.')));
        return;
      }
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) throw Exception('Could not create ZIP archive.');
      final fileName = '${projectName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.zip';
      Directory directory;
      if (Platform.isAndroid) {
        final sharedDirectory = Directory('/storage/emulated/0/Download/SumerWebMaker');
        try {
          if (!await sharedDirectory.exists()) await sharedDirectory.create(recursive: true);
          final probe = File('${sharedDirectory.path}/.write_probe');
          await probe.writeAsString('ok');
          await probe.delete();
          directory = sharedDirectory;
        } catch (_) {
          directory = await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      final out = File('${directory.path}/$fileName');
      await out.writeAsBytes(zipBytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Project exported with ${archive.files.length} files: ${out.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting project: $e')));
    }
  }

  void _scrollToLine(int line) {
    // Must match the exact line height used by TextField/RichText/line numbers.
    const lineH = 14.0 * 1.4;
    final targetOffset = (line - 1) * lineH;
    if (_verticalScrollController.hasClients) {
      _verticalScrollController.animateTo(
        targetOffset.clamp(
            0.0, _verticalScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _verticalScrollController.dispose();
    _lineNumbersScrollController.dispose();
    _horizontalScrollController.dispose();
    _highlightScrollController.dispose();
    _smartBarScrollController.dispose();
    _autoSaveTimer?.cancel();
    _editorFocusNode.dispose();
    _codeController.dispose();
    _findController.dispose();
    super.dispose();
  }

  // قالب احترافي ومتطور باللغة الإنجليزية كبداية تلقائية للمستخدمين
  String _defaultTemplate() {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>My Professional Project</title>
    <style>
      :root {
        primary-color: #4f46e5;
        bg-color: #0f172a;
        card-bg: #1e293b;
        text-color: #f8fafc;
      }
      body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        background-color: var(--bg-color);
        color: var(--text-color);
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100vh;
        margin: 0;
      }
      .card {
        background-color: var(--card-bg);
        padding: 2.5rem;
        border-radius: 1rem;
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.3);
        text-align: center;
        max-width: 400px;
        width: 90%;
      }
      h1 {
        margin-bottom: 0.5rem;
        color: #818cf8;
        font-size: 1.8rem;
      }
      p {
        color: #94a3b8;
        font-size: 0.95rem;
      }
      .btn {
        display: inline-block;
        margin-top: 1.5rem;
        padding: 0.75rem 1.5rem;
        background-color: var(--primary-color);
        color: #ffffff;
        border-radius: 0.5rem;
        text-decoration: none;
        font-weight: bold;
        transition: background 0.3s;
      }
      .btn:hover {
        background-color: #4338ca;
      }
    </style>
</head>
<body>
    <div class="card">
        <h1>Welcome Back!</h1>
        <p>Start building your amazing web project right here with clean HTML, CSS, and JS.</p>
        <a href="#" class="btn" onclick="sayHello()">Click Me</a>
    </div>

    <script>
      function sayHello() {
        console.log("Button clicked successfully!");
        alert("Welcome to your live preview!");
      }
    </script>
</body>
</html>''';
  }

  void _insertTextAtCursor(String text) {
    final cursorPosition = _codeController.selection.baseOffset;
    if (cursorPosition < 0) {
      _codeController.text += text;
      return;
    }
    final String currentText = _codeController.text;
    final String newText = currentText.substring(0, cursorPosition) +
        text +
        currentText.substring(cursorPosition);
    _codeController.text = newText;
    _codeController.selection =
        TextSelection.collapsed(offset: cursorPosition + text.length);
  }

  void _formatCode() {
    String code = _codeController.text;
    code = code.replaceAll('><', '>\n<');
    code = code.replaceAll(';}', ';\n}');
    code = code.replaceAll('{', '{\n');
    _codeController.text = code;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Code formatting applied!'),
          duration: Duration(seconds: 1)),
    );
  }

  // --- دمج خيارات القائمة الجديدة (زر الإعدادات المنسدل) ---
  void _showEditorOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return SafeArea(
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Editor Settings & Options',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const Divider(color: Colors.grey),

                    // 1. زر نسخ الكود
                    ListTile(
                      leading: const Icon(Icons.copy_rounded,
                          color: Colors.blueAccent),
                      title: const Text('Copy Code',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Copy all code to clipboard',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        Clipboard.setData(
                            ClipboardData(text: _codeController.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Code copied to clipboard!')),
                        );
                      },
                    ),

                    // 2. زر حذف الكود (مع نافذة تأكيد)
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent),
                      title: const Text('Clear Code',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Delete all code in editor',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _showClearConfirmationDialog();
                      },
                    ),

                    // 3. خيار الحفظ التلقائي (خاص بهذا المشروع)
                    SwitchListTile(
                      secondary: const Icon(Icons.save_alt_rounded,
                          color: Colors.greenAccent),
                      title: const Text('Auto-Save',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'Save changes automatically for this project',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      value: _isAutoSaveEnabled,
                      activeThumbColor: Colors.greenAccent,
                      onChanged: (bool value) async {
                        setStateModal(() {
                          _isAutoSaveEnabled = value;
                        });
                        setState(() {
                          _isAutoSaveEnabled = value;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('auto_save_$projectName', value);
                        // نحفظ الإعداد داخل بيانات المشروع في الحالتين:
                        // التفعيل والإيقاف، حتى يتذكر المشروع اختياره لاحقًا.
                        _fileContents[_activeTab] = _codeController.text;
                        await _saveCurrentProjectToStorage();
                      },
                    ),

                    // 4. خيار الوضع النهاري / الليلي (عام للمحرر)
                    SwitchListTile(
                      secondary: Icon(
                        _isLightMode
                            ? Icons.wb_sunny_rounded
                            : Icons.nightlight_round,
                        color: Colors.amber,
                      ),
                      title: const Text('Day Mode (Light Theme)',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                          'Switch editor background and text colors',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      value: _isLightMode,
                      activeThumbColor: Colors.amber,
                      onChanged: (bool value) async {
                        setStateModal(() {
                          _isLightMode = value;
                        });
                        setState(() {
                          _isLightMode = value;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('editor_light_mode', value);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // نافذة تأكيد الحذف
  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            const Text('Are you sure?', style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will delete all current code in the editor. Do you want to proceed?',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () {
              setState(() {
                _codeController.text = '';
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Editor cleared!')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select Image Insertion Type',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.grey),
                  ListTile(
                    leading: const Icon(Icons.code_rounded,
                        color: Colors.purpleAccent),
                    title: const Text('Embedded Base64 Image',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Embed image directly inside HTML',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndInsertImage(true);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_copy_rounded,
                        color: Colors.tealAccent),
                    title: const Text('Upload Project Images',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text(
                        'Add SVG or other image files to this project',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _uploadProjectImages();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // إدراج الصور بدون إبطاء المحرر:
  // البيانات Base64 الطويلة لا تُكتب داخل نص الكود أبدًا. بل تُحفظ في
  // _projectImages (التي يدعمها الحفظ والتصدير والمعاينة) ويُدرج في الكود
  // مجرد مرجع قصير images/<name>. هكذا يبقى النص صغيرًا حتى مع 10-20 صورة.
  Future<void> _pickAndInsertImage(bool asBase64) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected image.')),
        );
        return;
      }

      final originalName = image.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ext = originalName.split('.').last.toLowerCase();
      final mime = ext == 'svg'
          ? 'image/svg+xml'
          : (ext == 'jpg' || ext == 'jpeg')
              ? 'image/jpeg'
              : 'image/$ext';

      // اسم فريد داخل المشروع حتى لا تتعارض الصور المتكررة مع بعضها.
      var fileName = originalName;
      var counter = 1;
      final used = _projectImages.keys.toSet();
      while (used.contains(fileName)) {
        final dotIndex = originalName.lastIndexOf('.');
        final base =
            dotIndex > 0 ? originalName.substring(0, dotIndex) : originalName;
        final suffix = dotIndex > 0 ? originalName.substring(dotIndex) : '';
        fileName = '$base($counter)$suffix';
        counter++;
      }

      _projectImages[fileName] = 'data:$mime;base64,${base64Encode(bytes)}';

      if (_activeTab != 'HTML') _switchFile('HTML');
      _insertTextAtCursor(
          '\n<img src="images/$fileName" alt="${fileName.split('.').first}" width="100%" />\n');

      await _saveCurrentProjectToStorage();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Image added to project and inserted into HTML.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<Directory> _getProjectFontsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}/SumerWebMakerProjects/$_baseProjectName/fonts',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _fontFamilyName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'CustomFont' : cleaned;
  }

  Future<void> _showAddFontDialog() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final fontNames = _projectFonts.keys.toList()..sort();
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.font_download_rounded,
                            color: Colors.lightBlueAccent),
                        SizedBox(width: 10),
                        Text(
                          'Add Font',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add .ttf fonts to this project. Previously added fonts are kept here.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const Divider(color: Colors.grey),
                    if (fontNames.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'No fonts added yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: fontNames.length,
                          itemBuilder: (context, index) {
                            final name = fontNames[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.font_download,
                                  color: Colors.lightBlueAccent),
                              title: Text(name,
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                'fonts/$name  •  family: ${_fontFamilyName(name)}',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 11),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Choose .ttf Font'),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            allowMultiple: true,
                            type: FileType.custom,
                            allowedExtensions: ['ttf'],
                            withData: true,
                          );
                          if (result == null) return;

                          final fontsDirectory =
                              await _getProjectFontsDirectory();
                          var added = 0;

                          for (final selected in result.files) {
                            final originalName = selected.name.trim();
                            if (!originalName.toLowerCase().endsWith('.ttf')) {
                              continue;
                            }

                            final bytes = selected.bytes ??
                                (selected.path == null
                                    ? null
                                    : await File(selected.path!).readAsBytes());
                            if (bytes == null || bytes.isEmpty) continue;

                            final safeOriginalName = originalName.replaceAll(
                              RegExp(r'[\\/:*?"<>|]'),
                              '_',
                            );

                            var fileName = safeOriginalName;
                            var counter = 1;
                            while (_projectFonts.containsKey(fileName)) {
                              final dot = safeOriginalName.lastIndexOf('.');
                              final base = dot > 0
                                  ? safeOriginalName.substring(0, dot)
                                  : safeOriginalName;
                              final ext = dot > 0
                                  ? safeOriginalName.substring(dot)
                                  : '.ttf';
                              fileName = '$base($counter)$ext';
                              counter++;
                            }

                            final dataUrl =
                                'data:font/ttf;base64,${base64Encode(bytes)}';
                            _projectFonts[fileName] = dataUrl;

                            final output =
                                File('${fontsDirectory.path}/$fileName');
                            await output.writeAsBytes(bytes, flush: true);
                            added++;
                          }

                          if (added > 0) {
                            await _saveCurrentProjectToStorage();
                            if (mounted) setState(() {});
                            setModalState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$added font(s) added to the project.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _uploadProjectImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['svg', 'png', 'jpg', 'jpeg', 'gif', 'webp'],
        withData: true,
      );
      if (result == null) return;

      final uploadedNames = <String>[];
      for (final selected in result.files) {
        final bytes = selected.bytes ??
            (selected.path == null
                ? null
                : await File(selected.path!).readAsBytes());
        if (bytes == null || bytes.isEmpty) continue;

        final name = selected.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final ext = name.split('.').last.toLowerCase();
        final mime = ext == 'svg'
            ? 'image/svg+xml'
            : ext == 'jpg' || ext == 'jpeg'
                ? 'image/jpeg'
                : 'image/$ext';
        _projectImages[name] = 'data:$mime;base64,${base64Encode(bytes)}';
        uploadedNames.add(name);
      }

      // Attach the image to the project and add a usable HTML reference.
      // The reference is inserted into HTML even when the user was viewing
      // the CSS or JS tab when they selected the image.
      if (uploadedNames.isNotEmpty) {
        if (_activeTab != 'HTML') _switchFile('HTML');
        for (final name in uploadedNames) {
          _insertTextAtCursor(
              '\n<img src="images/$name" alt="${name.split('.').first}" />\n');
        }
      }
      await _saveCurrentProjectToStorage();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${result.files.length} project image(s) uploaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading project images: $e')),
      );
    }
  }

  // ------------------------------------------------------------------
  //  SIDE DRAWER: hierarchical file tree
  // ------------------------------------------------------------------

  String _uniqueSiblingPath(String desired, {String? exclude}) {
    final path = _normalizeProjectPath(desired);
    final parent = _parentPath(path);
    final name = _baseName(path);
    if (!_projectCodeFiles.containsKey(path) && !_projectAssetFiles.containsKey(path) &&
        !_projectFolders.contains(path)) return path;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; i < 10000; i++) {
      final candidate = _normalizeProjectPath('${parent.isEmpty ? '' : '$parent/'}$stem$i$ext');
      if (candidate == exclude) continue;
      if (!_projectCodeFiles.containsKey(candidate) && !_projectAssetFiles.containsKey(candidate) && !_projectFolders.contains(candidate)) return candidate;
    }
    return path;
  }

  void _createFolderFromDrawer() {
    final ctrl = TextEditingController();
    final parent = _selectedFolderPath;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('New Folder', style: TextStyle(color: Colors.white)),
        content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Folder name', hintStyle: TextStyle(color: Colors.grey))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            final name = ctrl.text.trim();
            if (name.isEmpty || name.contains(RegExp(r'[\\/:*?"<>|]'))) return;
            final path = _normalizeProjectPath(parent.isEmpty ? name : '$parent/$name');
            if (_projectFolders.contains(path) || _projectCodeFiles.containsKey(path) || _projectAssetFiles.containsKey(path)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A file or folder with this name already exists.'))); return;
            }
            setState(() { _projectFolders.add(path); _expandedFolders.add(parent); _selectedFolderPath = path; });
            _saveCurrentProjectToStorage();
            Navigator.pop(dialogContext);
          }, child: const Text('Create')),
        ],
      ),
    );
  }

  void _createNewFileFromDrawer([String? rawName]) {
    final ctrl = TextEditingController(text: rawName ?? '');
    final parent = _selectedFolderPath;
    void create() {
      final entered = ctrl.text.trim();
      final name = _baseName(entered);
      if (name.isEmpty) return;
      final ext = _extensionOf(name);
      if (!const {'html', 'css', 'js'}.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only .html, .css, and .js files are supported.'))); return;
      }
      final path = _normalizeProjectPath(parent.isEmpty ? name : '$parent/$name');
      if (_projectCodeFiles.containsKey(path) || _projectAssetFiles.containsKey(path) || _projectFolders.contains(path)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$path" already exists.'))); return;
      }
      setState(() {
        _projectCodeFiles[path] = '';
        _ensureFolderParents(path);
        _activeFileNameByType[ext == 'css' ? 'CSS' : ext == 'js' ? 'JS' : 'HTML'] = path;
        _selectedTreePath = path;
      });
      _syncLegacyFileMaps();
      _saveCurrentProjectToStorage();
      Navigator.pop(context);
      _openMultiFile(path);
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('New File', style: TextStyle(color: Colors.white)),
        content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'e.g. about.html, styles/theme.css, scripts/app.js', hintStyle: TextStyle(color: Colors.grey)), onSubmitted: (_) => create()),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), ElevatedButton(onPressed: create, child: const Text('Create'))],
      ),
    );
  }

  void _renameTreeNode(String oldPath) {
    final ctrl = TextEditingController(text: _baseName(oldPath));
    final isFolder = _projectFolders.contains(oldPath);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(isFolder ? 'Rename Folder' : 'Rename File', style: const TextStyle(color: Colors.white)),
        content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), ElevatedButton(onPressed: () {
          final name = ctrl.text.trim();
          if (name.isEmpty || name.contains(RegExp(r'[\\/:*?"<>|]'))) return;
          if (!isFolder && !_isCodePath(name)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only .html, .css, and .js files are supported.'))); return;
          }
          final newPath = _uniqueSiblingPath('${_parentPath(oldPath).isEmpty ? '' : '${_parentPath(oldPath)}/'}$name', exclude: oldPath);
          final descendants = <String>[];
          if (isFolder) {
            descendants.addAll(_projectFolders.where((p) => p == oldPath || p.startsWith('$oldPath/')));
            descendants.addAll(_projectCodeFiles.keys.where((p) => p.startsWith('$oldPath/')));
            descendants.addAll(_projectAssetFiles.keys.where((p) => p.startsWith('$oldPath/')));
          } else { descendants.add(oldPath); }
          setState(() {
            for (final old in descendants) {
              final replacement = isFolder ? '$newPath${old.substring(oldPath.length)}' : newPath;
              if (_projectFolders.remove(old)) _projectFolders.add(replacement);
              if (_projectCodeFiles.containsKey(old)) { final v = _projectCodeFiles.remove(old)!; _projectCodeFiles[replacement] = v; }
              if (_projectAssetFiles.containsKey(old)) { final v = _projectAssetFiles.remove(old)!; _projectAssetFiles[replacement] = v; }
              if (_selectedTreePath == old) _selectedTreePath = replacement;
              for (final type in ['HTML','CSS','JS']) if (_activeFileNameByType[type] == old) _activeFileNameByType[type] = replacement;
            }
            _selectedFolderPath = isFolder && _selectedFolderPath.startsWith('$oldPath') ? _selectedFolderPath.replaceFirst(oldPath, newPath) : _selectedFolderPath;
          });
          _syncLegacyFileMaps(); _syncLegacyAssets(); _saveCurrentProjectToStorage(); Navigator.pop(dialogContext);
          if (!isFolder && _selectedTreePath == newPath) _openMultiFile(newPath);
        }, child: const Text('Rename'))],
      ),
    );
  }

  void _deleteTreeNode(String path) {
    final isFolder = _projectFolders.contains(path);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Are you sure?', style: TextStyle(color: Colors.white)),
        content: Text('Delete "$path"${isFolder ? ' and everything inside it' : ''}? This can\'t be undone.', style: const TextStyle(color: Colors.grey)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () {
          setState(() {
            final prefix = isFolder ? '$path/' : path;
            _projectFolders.removeWhere((p) => p == path || p.startsWith(prefix));
            _projectCodeFiles.removeWhere((p, _) => p == path || p.startsWith(prefix));
            _projectAssetFiles.removeWhere((p, _) => p == path || p.startsWith(prefix));
            if (_selectedTreePath == path || _selectedTreePath.startsWith(prefix)) _selectedTreePath = '';
            if (_selectedFolderPath == path || _selectedFolderPath.startsWith(prefix)) _selectedFolderPath = _parentPath(path);
          });
          _syncLegacyFileMaps(); _syncLegacyAssets(); _saveCurrentProjectToStorage(); Navigator.pop(dialogContext);
        }, child: const Text('Delete', style: TextStyle(color: Colors.white)))],
      ),
    );
  }

  Future<void> _uploadGeneralAsset() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any, withData: true);
      if (result == null) return;
      final parent = _selectedFolderPath;
      var added = 0;
      for (final selected in result.files) {
        final bytes = selected.bytes ?? (selected.path == null ? null : await File(selected.path!).readAsBytes());
        if (bytes == null || bytes.isEmpty) continue;
        final safeName = selected.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final path = _uniqueSiblingPath(parent.isEmpty ? safeName : '$parent/$safeName');
        final dataUrl = 'data:${_mimeForPath(path)};base64,${base64Encode(bytes)}';
        _projectAssetFiles[path] = dataUrl;
        _ensureFolderParents(path);
        added++;
      }
      _syncLegacyAssets();
      await _saveCurrentProjectToStorage();
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$added file(s) uploaded.')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading file: $e'))); }
  }

  IconData _iconForTreePath(String path, bool isFolder) {
    if (isFolder) return _expandedFolders.contains(path) ? Icons.folder_open : Icons.folder;
    switch (_extensionOf(path)) {
      case 'html': return Icons.html;
      case 'css': return Icons.css;
      case 'js': return Icons.javascript;
      case 'png': case 'jpg': case 'jpeg': case 'gif': case 'webp': case 'svg': return Icons.image;
      case 'ttf': case 'otf': case 'woff': case 'woff2': return Icons.font_download;
      default: return Icons.insert_drive_file;
    }
  }

  Color _colorForTreePath(String path, bool isFolder) {
    if (isFolder) return Colors.amber;
    switch (_extensionOf(path)) {
      case 'html': return Colors.orangeAccent;
      case 'css': return Colors.blueAccent;
      case 'js': return Colors.amber;
      case 'png': case 'jpg': case 'jpeg': case 'gif': case 'webp': case 'svg': return Colors.pinkAccent;
      default: return Colors.grey.shade400;
    }
  }

  List<String> _childrenOf(String parent) {
    final paths = <String>{};
    final prefix = parent.isEmpty ? '' : '$parent/';
    for (final p in _projectFolders) {
      if (p.startsWith(prefix)) { final rest = p.substring(prefix.length); if (!rest.contains('/')) paths.add(p); }
    }
    for (final p in _projectCodeFiles.keys) {
      if (p.startsWith(prefix)) { final rest = p.substring(prefix.length); if (!rest.contains('/')) paths.add(p); }
    }
    for (final p in _projectAssetFiles.keys) {
      if (p.startsWith(prefix)) { final rest = p.substring(prefix.length); if (!rest.contains('/')) paths.add(p); }
    }
    final list = paths.toList();
    list.sort((a,b) { final af=_projectFolders.contains(a), bf=_projectFolders.contains(b); if (af != bf) return af ? -1 : 1; return _baseName(a).toLowerCase().compareTo(_baseName(b).toLowerCase()); });
    return list;
  }

  Widget _buildTreeNode(String path, {int depth = 0}) {
    final isFolder = _projectFolders.contains(path);
    final expanded = isFolder && _expandedFolders.contains(path);
    final selected = path == _selectedTreePath;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: selected ? Colors.white.withOpacity(0.08) : Colors.transparent,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 12.0 + depth * 16, right: 2),
          leading: Icon(_iconForTreePath(path, isFolder), color: _colorForTreePath(path, isFolder), size: 19),
          title: Text(_baseName(path), overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white : Colors.grey.shade300, fontSize: 13, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          onTap: () {
            setState(() { _selectedTreePath = path; if (isFolder) { _expandedFolders.contains(path) ? _expandedFolders.remove(path) : _expandedFolders.add(path); _selectedFolderPath = path; } else { _selectedFolderPath = _parentPath(path); } });
            if (!isFolder && _isCodePath(path)) { _openMultiFile(path); Navigator.pop(context); }
          },
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit, size: 15, color: Colors.orangeAccent), tooltip: 'Rename', onPressed: () => _renameTreeNode(path)),
            IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), tooltip: 'Delete', onPressed: () => _deleteTreeNode(path)),
          ]),
        ),
      ),
      if (expanded) ..._childrenOf(path).map((child) => _buildTreeNode(child, depth: depth + 1)),
    ]);
  }

  Widget _buildFileDrawer() {
    _ensureHierarchicalFileSystem();
    final roots = _childrenOf('');
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      child: SafeArea(child: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(16,20,16,16), color: const Color(0xFF232323), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(projectName, style: const TextStyle(color: Colors.white,fontSize:16,fontWeight:FontWeight.bold)), const SizedBox(height:4), const Text('Project files', style: TextStyle(color:Colors.grey,fontSize:12))])),
        Padding(padding: const EdgeInsets.fromLTRB(10,10,10,4), child: Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _createFolderFromDrawer, icon: const Icon(Icons.create_new_folder,size:17), label: const Text('Folder'))),
          const SizedBox(width:6),
          Expanded(child: OutlinedButton.icon(onPressed: () => _createNewFileFromDrawer(), icon: const Icon(Icons.note_add,size:17), label: const Text('File'))),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal:10), child: SizedBox(width:double.infinity, child: ElevatedButton.icon(onPressed:_uploadGeneralAsset, icon:const Icon(Icons.upload_file,size:17), label:const Text('Upload File')))),
        Expanded(child: ListView(padding: const EdgeInsets.only(top:4,bottom:16), children: roots.isEmpty ? [const Padding(padding:EdgeInsets.all(20),child:Text('No files yet.',style:TextStyle(color:Colors.grey)))] : roots.map((p) => _buildTreeNode(p)).toList())),
      ])),
    );
  }

  void _showSaveDialog() {
    TextEditingController nameController =
        TextEditingController(text: projectName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            const Text('Save Project', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('File Name:',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Save in App',
                style: TextStyle(color: Colors.white)),
            onPressed: () async {
              projectName = nameController.text.trim().isEmpty
                  ? projectName
                  : nameController.text.trim();
              _fileContents[_activeTab] = _codeController.text;
              await _saveCurrentProjectToStorage();
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Project saved successfully!')),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Save to SumerWebMaker',
                style: TextStyle(color: Colors.white)),
            onPressed: () async {
              projectName = nameController.text.trim().isEmpty
                  ? projectName
                  : nameController.text.trim();
              _fileContents[_activeTab] = _codeController.text;

              // الحفظ الخارجي دائمًا ZIP داخل مجلد SumerWebMaker.
              // سواء كان المشروع يحتوي ملفًا واحدًا أو ملفين أو ثلاثة.
              await _exportProjectZip();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveProjectToStorage(String name, String code) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedProjects = prefs.getStringList('projects_list') ?? [];
    String projectData = "$name|||$code";
    savedProjects.removeWhere((p) => p.startsWith("$name|||"));
    savedProjects.add(projectData);
    await prefs.setStringList('projects_list', savedProjects);
  }

  Future<void> _exportToDownloads(String fileName, String content) async {
    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download/SumerWebMaker');
        try {
          await directory.create(recursive: true);
        } on FileSystemException {
          final appStorage = await getExternalStorageDirectory();
          directory = appStorage == null
              ? null
              : Directory('${appStorage.path}/SumerWebMaker');
          await directory?.create(recursive: true);
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final filePath = '${directory?.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(content);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded to: $filePath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading file: $e')),
      );
    }
  }

  void _insertColor(String hex) {
    _insertTextAtCursor(hex);
  }

  Widget _buildColorItem(String hex) {
    final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _insertColor(hex),
        child: Container(
          width: 34,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: hex == '#FFFFFF' ? Colors.grey : Colors.white24,
            ),
          ),
          alignment: Alignment.center,
          child: hex == '#000000' || hex == '#FFFFFF'
              ? Text(
                  hex == '#000000' ? 'K' : 'W',
                  style: TextStyle(
                    color: hex == '#000000' ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // أزرار الكيبورد الذكي: وظيفتها الوحيدة إدخال الكود في الملف الحالي.
  // لا تستعمل _switchFile هنا حتى لا تغيّر واجهة HTML/CSS/JS.
  Widget _buildSmartBarItem(String label, String codeToInsert,
      {Color color = Colors.orangeAccent}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 3.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2C2C2C),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(40, 36),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: () => _insertTextAtCursor(codeToInsert),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
      ),
    );
  }

  // أزرار HTML/CSS/JS العلوية: وظيفتها الوحيدة تبديل واجهة المحرر.
  Widget _buildTabButton(String title, Color activeColor) {
    bool isActive = _activeTab == title;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor:
              isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
          foregroundColor: isActive ? activeColor : Colors.grey,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: const Size(32, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _switchFile(title),
        child: Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // أزرار تصنيف الكيبورد الذكي: تبدّل الاختصارات فقط.
  Widget _buildSmartCategoryButton(String title, Color activeColor) {
    final isActive = _smartCategory == title;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor:
              isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
          foregroundColor: isActive ? activeColor : Colors.grey,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: const Size(32, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => setState(() => _smartCategory = title),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutCategoryBar() {
    return Container(
      height: 40,
      color: _isLightMode ? const Color(0xFFEAEAEA) : const Color(0xFF181818),
      child: Row(
        children: [
          const SizedBox(width: 4),
          _buildSmartCategoryButton('HTML', Colors.blueAccent),
          _buildSmartCategoryButton('CSS', Colors.greenAccent),
          _buildSmartCategoryButton('JS', Colors.amber),
          const SizedBox(width: 4),
          Expanded(
            child: ListView(
              controller: _smartBarScrollController,
              scrollDirection: Axis.horizontal,
              children: _getSmartBarItems(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _getSmartBarItems() {
    if (_smartCategory == 'HTML') {
      return [
        _buildSmartBarItem('<!DOCTYPE>', '<!DOCTYPE html>\n',
            color: Colors.blueAccent),
        _buildSmartBarItem('<html>', '<html>\n\t\n</html>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<head>', '<head>\n\t\n</head>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<title>', '<title>Page Title</title>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<body>', '<body>\n\t\n</body>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<div>', '<div class="">\n\t\n</div>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<p>', '<p></p>', color: Colors.blueAccent),
        _buildSmartBarItem('<h1>', '<h1></h1>', color: Colors.blueAccent),
        _buildSmartBarItem('<h2>', '<h2></h2>', color: Colors.blueAccent),
        _buildSmartBarItem('<button>', '<button></button>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<li>', '<li></li>', color: Colors.blueAccent),
        _buildSmartBarItem('width', 'width="100"', color: Colors.blueAccent),
        _buildSmartBarItem('height', 'height="100"', color: Colors.blueAccent),
        _buildSmartBarItem('class', 'class=""', color: Colors.blueAccent),
        _buildSmartBarItem('id', 'id=""', color: Colors.blueAccent),
        _buildSmartBarItem('<a>', '<a href="#">Link</a>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<img>', '<img src="" alt="" width="100%" />',
            color: Colors.blueAccent),
        _buildSmartBarItem('<span>', '<span></span>', color: Colors.blueAccent),
        _buildSmartBarItem('<input text>', '<input type="text">',
            color: Colors.blueAccent),
        _buildSmartBarItem('<input number>', '<input type="number">',
            color: Colors.blueAccent),
        _buildSmartBarItem(
            '<table>', '<table>\n\t<tr><td>Data</td></tr>\n</table>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<br>', '<br>', color: Colors.blueAccent),
        _buildSmartBarItem('<form>', '<form>\n\t\n</form>',
            color: Colors.blueAccent),
        _buildSmartBarItem(
            '<link>', '<link rel="stylesheet" href="/style.css">',
            color: Colors.blueAccent),
        _buildSmartBarItem('<script>', '<script>\n\t\n</script>',
            color: Colors.blueAccent),
        _buildSmartBarItem('<style>', '<style>\n\t\n</style>',
            color: Colors.blueAccent),
      ];
    } else if (_smartCategory == 'CSS') {
      return [
        _buildSmartBarItem('.', '.', color: Colors.greenAccent),
        _buildSmartBarItem('#', '#', color: Colors.greenAccent),
        _buildSmartBarItem('{ }', '{\n\t\n}', color: Colors.greenAccent),
        _buildSmartBarItem('color', 'color: #000000;',
            color: Colors.greenAccent),
        _buildSmartBarItem(
            'font-family', 'font-family: "courier new", courier, monospace;',
            color: Colors.greenAccent),
        _buildSmartBarItem('text-align', 'text-align: center;',
            color: Colors.greenAccent),
        _buildSmartBarItem('background', 'background: #FFFF00;',
            color: Colors.greenAccent),
        _buildSmartBarItem('padding', 'padding: 10px;',
            color: Colors.greenAccent),
        _buildSmartBarItem('margin', 'margin: 10px;',
            color: Colors.greenAccent),
        _buildSmartBarItem('width', 'width: 50%;', color: Colors.greenAccent),
        _buildSmartBarItem('height', 'height: 50px;',
            color: Colors.greenAccent),
        _buildSmartBarItem('font-size', 'font-size: 1rem;',
            color: Colors.greenAccent),
        _buildSmartBarItem('border-radius', 'border-radius: 8px;',
            color: Colors.greenAccent),
        _buildSmartBarItem('border-color', 'border: #FFFF00;',
            color: Colors.greenAccent),
        _buildSmartBarItem('display', 'display: block;',
            color: Colors.greenAccent),
        _buildSmartBarItem('@media', '@media (max-width: 992px) {\n\t\n}',
            color: Colors.greenAccent),
        _buildSmartBarItem('flex-direction', 'flex-direction: column;',
            color: Colors.greenAccent),
        _buildSmartBarItem('justify-content', 'justify-content: center;',
            color: Colors.greenAccent),
        _buildSmartBarItem('align-items', 'align-items: center;',
            color: Colors.greenAccent),
        _buildSmartBarItem('background-color', 'background-color: #ffffff;',
            color: Colors.greenAccent),
        _buildSmartBarItem('border', 'border: 1px solid #ccc;',
            color: Colors.greenAccent),
        _buildSmartBarItem('width/height', 'width: 100%;\nheight: auto;',
            color: Colors.greenAccent),
      ];
    } else {
      return [
        _buildSmartBarItem('console.log', 'console.log("")',
            color: Colors.amber),
        _buildSmartBarItem('let', 'let variableName = value',
            color: Colors.amber),
        _buildSmartBarItem('else if', 'else if (condition) {\n\t\n}',
            color: Colors.amber),
        _buildSmartBarItem('else', 'else {\n\t\n}', color: Colors.amber),
        _buildSmartBarItem('if statement', 'if (condition) {\n\t\n}',
            color: Colors.amber),
        _buildSmartBarItem('function', 'function myFunction() {\n\t\n}',
            color: Colors.amber),
        _buildSmartBarItem('and &&', '&&', color: Colors.amber),
        _buildSmartBarItem('or ||', '||', color: Colors.amber),
        _buildSmartBarItem('not !', '!', color: Colors.amber),
        _buildSmartBarItem('while', 'while (condition) {\n\t\n}',
            color: Colors.amber),
        _buildSmartBarItem('for loop', 'for (let i = 0; i <= 10; i++) {\n\t\n}',
            color: Colors.amber),
        _buildSmartBarItem('return', 'return', color: Colors.amber),
        _buildSmartBarItem('getElementById', 'document.getElementById("");',
            color: Colors.amber),
        _buildSmartBarItem('addEventListener',
            'window.addEventListener("load", function() {\n\t\n});',
            color: Colors.amber),
      ];
    }
  }

  Widget _buildFindBar() {
    if (!_isFindOpen) return const SizedBox.shrink();
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      color: _isLightMode ? const Color(0xFFEAEAEA) : const Color(0xFF181818),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findController,
              autofocus: true,
              style: TextStyle(
                color: _isLightMode ? Colors.black87 : Colors.white,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Find in ${_fileNames[_activeTab] ?? _activeTab}',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                isDense: true,
                prefixIcon: const Icon(Icons.search,
                    color: Colors.cyanAccent, size: 19),
                suffixText: _findQuery.isEmpty
                    ? ''
                    : '${_findMatches.isEmpty ? 0 : _findIndex + 1}/${_findMatches.length}',
                suffixStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    _isLightMode ? Colors.white : const Color(0xFF252525),
              ),
              onSubmitted: (_) => _runFindSearch(),
            ),
          ),
          IconButton(
            tooltip: 'Search',
            onPressed: _runFindSearch,
            icon: const Icon(Icons.search, color: Colors.cyanAccent),
          ),
          IconButton(
              tooltip: 'Previous',
              onPressed: _previousFind,
              icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white)),
          IconButton(
              tooltip: 'Next',
              onPressed: _nextFind,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white)),
          IconButton(
              tooltip: 'Close Find',
              onPressed: _closeFind,
              icon: const Icon(Icons.close, color: Colors.redAccent)),
        ],
      ),
    );
  }

  Widget _buildColorBar() {
    if (!_showColorBar) return const SizedBox.shrink();
    return Container(
      height: 42,
      color: _isLightMode ? const Color(0xFFEAEAEA) : const Color(0xFF181818),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          const Center(
              child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 7),
            child: Text('COLORS',
                style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          )),
          ..._colorPalette.map(_buildColorItem),
        ],
      ),
    );
  }

  Widget _buildEditorArea(
    Color editorBgColor,
    Color lineNumBgColor,
    TextStyle editorTextStyle,
  ) {
    // One source of truth for every text layer. The real TextField, syntax
    // layer, and line numbers must use the same font metrics and line height.
    const double lineHeight = 14.0 * 1.4;

    final TextStyle exactEditorStyle = editorTextStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
    );

    return Container(
      color: editorBgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 45,
            color: lineNumBgColor,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _codeController,
              builder: (context, TextEditingValue value, __) {
                final int lineCount = value.text.split('\n').length;

                return SingleChildScrollView(
                  controller: _lineNumbersScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      lineCount > 0 ? lineCount : 1,
                      (index) => SizedBox(
                        height: lineHeight,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              '${index + 1}',
                              style: exactEditorStyle.copyWith(
                                color: Colors.grey,
                              ),
                              textHeightBehavior: const TextHeightBehavior(
                                applyHeightToFirstAscent: true,
                                applyHeightToLastDescent: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _codeController,
                builder: (context, value, __) {
                  return SizedBox(
                    width: _editorContentWidth(value.text),
                    child: Stack(
                      children: [
                        // Syntax layer. It is deliberately metric-identical to
                        // the transparent TextField underneath it.
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _codeController,
                          builder: (context, value, __) => IgnorePointer(
                            child: SingleChildScrollView(
                              controller: _highlightScrollController,
                              physics: const NeverScrollableScrollPhysics(),
                              child: RichText(
                                text: _highlightCode(value.text),
                                textDirection: TextDirection.ltr,
                                softWrap: false,
                                strutStyle: const StrutStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  height: 1.4,
                                  fontWeight: FontWeight.normal,
                                  forceStrutHeight: true,
                                ),
                                textHeightBehavior: const TextHeightBehavior(
                                  applyHeightToFirstAscent: true,
                                  applyHeightToLastDescent: true,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Real input layer: keep it responsible for selection,
                        // cursor, keyboard/IME, undo and editing.
                        TextField(
                          controller: _codeController,
                          focusNode: _editorFocusNode,
                          scrollController: _verticalScrollController,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          cursorColor: _syntaxColorForActiveTab(),
                          strutStyle: const StrutStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            height: 1.4,
                            fontWeight: FontWeight.normal,
                            forceStrutHeight: true,
                          ),
                          style: exactEditorStyle.copyWith(
                            color: Colors.transparent,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    // تحديد الألوان بناءً على الوضع (النهاري أو الليلي)
    final Color scaffoldBgColor =
        _isLightMode ? const Color(0xFFF5F5F5) : const Color(0xFF121212);
    final Color appBarBgColor =
        _isLightMode ? const Color(0xFFE0E0E0) : const Color(0xFF1F1F1F);
    final Color appBarTextColor = _isLightMode ? Colors.black87 : Colors.white;
    final Color editorBgColor =
        _isLightMode ? Colors.white : const Color(0xFF1E1E1E);
    final Color lineNumBgColor =
        _isLightMode ? const Color(0xFFEEEEEE) : const Color(0xFF161616);
    final TextStyle editorTextStyle = TextStyle(
      color: _isLightMode ? const Color(0xFF222222) : const Color(0xFFF8F8F2),
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      letterSpacing: 0,
    );

    return Scaffold(
      backgroundColor: scaffoldBgColor,
      resizeToAvoidBottomInset: true,
      // New Hamburger Button: Scaffold auto-adds a 3-line menu icon at
      // the start of the AppBar whenever a drawer is present, which
      // opens this side navigation drawer from the left.
      drawer: _buildFileDrawer(),
      appBar: AppBar(
        backgroundColor: appBarBgColor,
        title: Text('Editor',
            style: TextStyle(color: appBarTextColor, fontSize: 16)),
        iconTheme: IconThemeData(color: appBarTextColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_rounded, color: Colors.purpleAccent),
            tooltip: 'Insert Image',
            onPressed: _showImageOptions,
          ),
          IconButton(
            icon: const Icon(Icons.format_align_left_rounded,
                color: Colors.orangeAccent),
            tooltip: 'Format Code',
            onPressed: _formatCode,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, color: Colors.amber),
            tooltip: 'Fullscreen Preview',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      FullscreenPreviewScreen(code: _buildPreviewHtml()),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save_rounded, color: Colors.greenAccent),
            tooltip: 'Save',
            onPressed: _showSaveDialog,
          ),
          // زر القائمة المنسدلة الجديدة للإعدادات
          IconButton(
            icon: Icon(Icons.tune_rounded, color: appBarTextColor),
            tooltip: 'Editor Options',
            onPressed: _showEditorOptionsMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 42,
            color: _isLightMode
                ? const Color(0xFFEAEAEA)
                : const Color(0xFF181818),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Undo',
                    icon: const Icon(Icons.undo_rounded, color: Colors.white),
                    onPressed:
                        _undoStacks[_activeTab]!.length > 1 ? _undo : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    icon: const Icon(Icons.redo_rounded, color: Colors.white),
                    onPressed:
                        _redoStacks[_activeTab]!.isNotEmpty ? _redo : null,
                  ),
                  IconButton(
                    tooltip: 'Find',
                    icon: const Icon(Icons.search_rounded,
                        color: Colors.cyanAccent),
                    onPressed: _showFindDialog,
                  ),
                  IconButton(
                    tooltip: 'Add Font',
                    icon: const Icon(Icons.font_download_rounded,
                        color: Colors.lightBlueAccent),
                    onPressed: _showAddFontDialog,
                  ),
                  IconButton(
                    tooltip: 'Colors',
                    icon: Icon(Icons.palette_rounded,
                        color:
                            _showColorBar ? Colors.pinkAccent : Colors.white),
                    onPressed: () =>
                        setState(() => _showColorBar = !_showColorBar),
                  ),
                  IconButton(
                    tooltip: 'Split Screen',
                    icon: Icon(
                      Icons.vertical_split_rounded,
                      color: _isSplitScreen ? Colors.amber : Colors.white,
                    ),
                    onPressed: _toggleSplitScreen,
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: _isLightMode
                ? const Color(0xFFEAEAEA)
                : const Color(0xFF181818),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_activeFileNameByType[_activeTab] ?? _activeTab,
                    style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                Text(projectName,
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: _isSplitScreen
                ? Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Container(
                          color: Colors.black,
                          child: WebViewWidget(
                              controller: _splitPreviewController),
                        ),
                      ),
                      Container(height: 1, color: Colors.grey),
                      Expanded(
                        flex: 5,
                        child: _buildEditorArea(
                          editorBgColor,
                          lineNumBgColor,
                          editorTextStyle,
                        ),
                      ),
                    ],
                  )
                : _buildEditorArea(
                    editorBgColor,
                    lineNumBgColor,
                    editorTextStyle,
                  ),
          ),
          _buildFindBar(),
          _buildColorBar(),
          _buildShortcutCategoryBar(),
        ],
      ),
    );
  }
}

class FullscreenPreviewScreen extends StatefulWidget {
  final String code;
  const FullscreenPreviewScreen({super.key, required this.code});

  @override
  State<FullscreenPreviewScreen> createState() =>
      _FullscreenPreviewScreenState();
}

class _FullscreenPreviewScreenState extends State<FullscreenPreviewScreen> {
  late final WebViewController _controller;
  final List<String> _consoleLogs = [];

  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ConsoleChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          setState(() {
            if (_consoleLogs.length < 500) {
              _consoleLogs.add(message.message);
            }
          });
        },
      )
      ..loadHtmlString(_injectConsoleInterceptor(widget.code));
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    });
  }

  String _injectConsoleInterceptor(String originalCode) {
    const interceptorScript = '''
    <script>
      var __swmLogCount=0,__swmLogLimit=200,__swmLogLimitSent=false;
      var oldLog=console.log;
      console.log=function(){
        if(__swmLogCount++>=__swmLogLimit){if(!__swmLogLimitSent){__swmLogLimitSent=true;ConsoleChannel.postMessage(JSON.stringify({type:'log',message:'Console output limit reached; further output was suppressed.'}));}return;}
        ConsoleChannel.postMessage(JSON.stringify({type:'log',message:Array.prototype.slice.call(arguments).map(function(v){return String(v);}).join(' ')}));
        oldLog.apply(console,arguments);
      };
      var oldError=console.error;
      console.error=function(){ConsoleChannel.postMessage(JSON.stringify({type:'error',message:Array.prototype.slice.call(arguments).map(function(v){return String(v);}).join(' '),line:null}));oldError.apply(console,arguments);};
      window.onerror=function(msg,url,line,col,error){
        var realLine=error&&error.__swmLine?error.__swmLine:(line?Math.max(1,line-7):null);
        ConsoleChannel.postMessage(JSON.stringify({type:'error',message:String(msg),line:realLine}));
        return false;
      };
    </script>
    ''';

    if (originalCode.contains('<head>')) {
      return originalCode.replaceFirst('<head>', '<head>\n$interceptorScript');
    } else {
      return interceptorScript + originalCode;
    }
  }

  void _showConsole() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            height: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.terminal_rounded, color: Colors.greenAccent),
                    SizedBox(width: 10),
                    Text('Developer Console',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(color: Colors.grey),
                Expanded(
                  child: _consoleLogs.isEmpty
                      ? const Center(
                          child: Text('No logs or errors.',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _consoleLogs.length,
                          itemBuilder: (context, index) {
                            final rawLog = _consoleLogs[index];
                            Map<String, dynamic>? parsed;
                            try {
                              final decoded = jsonDecode(rawLog);
                              if (decoded is Map) {
                                parsed = Map<String, dynamic>.from(decoded);
                              }
                            } catch (_) {}

                            final displayLog =
                                parsed?['message']?.toString() ?? rawLog;
                            final isError = parsed?['type'] == 'error' ||
                                rawLog.contains('ERROR');
                            final int? targetLine = parsed?['line'] is num
                                ? (parsed!['line'] as num).toInt()
                                : null;
                            final Color logColor =
                                isError ? Colors.redAccent : Colors.white;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: InkWell(
                                onTap: isError
                                    ? () {
                                        Navigator.pop(context);
                                        Navigator.pop(context, targetLine);
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: isError
                                      ? BoxDecoration(
                                          color: Colors.red.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.redAccent
                                                  .withOpacity(0.3)),
                                        )
                                      : null,
                                  child: Text(
                                    '> $displayLog ${isError ? "\n[Tap to jump to error location]" : ""}',
                                    style: TextStyle(
                                        color: logColor,
                                        fontFamily: 'monospace',
                                        fontSize: 13),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (await _controller.canGoBack()) {
          _controller.goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F1F1F),
          title: const Text('Live Preview',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: Icon(
                _isLandscape
                    ? Icons.screen_rotation_rounded
                    : Icons.screen_lock_rotation_rounded,
                color: _isLandscape ? Colors.amber : Colors.grey,
              ),
              tooltip: 'Rotate Screen',
              onPressed: _toggleOrientation,
            ),
          ],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              if (await _controller.canGoBack()) {
                _controller.goBack();
              } else {
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: WebViewWidget(controller: _controller),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF2C2C2C),
          mini: true,
          onPressed: _showConsole,
          child:
              const Icon(Icons.bug_report_rounded, color: Colors.greenAccent),
        ),
      ),
    );
  }
}
