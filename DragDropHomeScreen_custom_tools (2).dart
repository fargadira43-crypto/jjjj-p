import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'editor_screen.dart';

// NOTE: this file now depends on `package:http` for the YouTube Video
// widget's automatic title lookup (see _fetchYoutubeMetadata). If `http`
// is not already in pubspec.yaml, add:
//   http: ^1.2.0
// `file_picker` is already a project dependency (used by editor_screen.dart
// for its "upload images" action) and is reused here for the .ttf uploader.

// ============================================================
//  DRAG AND DROP WEB BUILDER  (Skratch-style, for the web)
// ============================================================

class DragDropHomeScreen extends StatefulWidget {
  const DragDropHomeScreen({super.key});

  @override
  _DragDropHomeScreenState createState() => _DragDropHomeScreenState();
}

class _DragDropHomeScreenState extends State<DragDropHomeScreen> {
  List<Map<String, dynamic>> projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedData = prefs.getString('drag_drop_projects');
    if (storedData != null) {
      setState(() {
        projects = List<Map<String, dynamic>>.from(json.decode(storedData));
        projects.sort((a, b) => b['date'].compareTo(a['date']));
      });
    }
  }

  Future<void> _saveProjectsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drag_drop_projects', json.encode(projects));
  }

  bool _nameExists(String name) {
    return projects.any((p) => p['name'] == name);
  }

  void _showNewProjectDialog() {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Create New Project',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Project name',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                String projectName = nameController.text.trim();
                if (projectName.isEmpty) return;
                if (_nameExists(projectName)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('That name is already used. Pick another.')),
                  );
                  return;
                }
                Navigator.pop(context);
                Map<String, dynamic> newProject = {
                  'name': projectName,
                  'date': DateTime.now().toIso8601String(),
                  'elements': []
                };
                setState(() {
                  projects.insert(0, newProject);
                  _saveProjectsToStorage();
                });
                _navigateToEditor(newProject);
              },
              child:
                  const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _navigateToEditor(Map<String, dynamic> project) async {
    final updatedProject = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DragDropEditorScreen(projectData: project),
      ),
    );

    if (updatedProject != null) {
      setState(() {
        int index = projects.indexWhere((p) => p['name'] == project['name']);
        if (index != -1) {
          projects[index] = updatedProject;
          projects.sort((a, b) => b['date'].compareTo(a['date']));
          _saveProjectsToStorage();
        }
      });
    }
  }

  void _deleteProject(int index) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title:
            const Text('Delete Project', style: TextStyle(color: Colors.white)),
        content: Text(
            'Delete "${projects[index]['name']}"? This cannot be undone.',
            style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        projects.removeAt(index);
        _saveProjectsToStorage();
      });
    }
  }

  void _renameProject(int index) {
    TextEditingController renameController =
        TextEditingController(text: projects[index]['name']);
    final String oldName = projects[index]['name'];
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Rename Project',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: renameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'New project name',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                String newName = renameController.text.trim();
                if (newName.isEmpty) return;
                if (newName != oldName && _nameExists(newName)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('That name is already used.')),
                  );
                  return;
                }
                setState(() {
                  projects[index]['name'] = newName;
                  projects[index]['date'] = DateTime.now().toIso8601String();
                  _saveProjectsToStorage();
                });
                Navigator.pop(context);
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161616),
      appBar: AppBar(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Drag & Drop Web Builder',
            style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                onPressed: _showNewProjectDialog,
                label: const Text('Create New Project',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: projects.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dashboard_customize,
                              color: Colors.grey, size: 56),
                          SizedBox(height: 12),
                          Text('No projects yet. Create your first one!',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        final project = projects[index];
                        return Card(
                          color: const Color(0xFF222222),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: const Icon(Icons.web,
                                color: Colors.lightBlueAccent),
                            title: Text(project['name'],
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              'Last edited: ${project['date'].substring(0, 10)}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.orange),
                                  onPressed: () => _renameProject(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _deleteProject(index),
                                ),
                              ],
                            ),
                            onTap: () => _navigateToEditor(project),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom HTML is deliberately never executed in the Flutter canvas. This
// lightweight placeholder gives the editor a visual preview while keeping
// custom JavaScript inert until the generated site is opened by its owner.
String _customHtmlPreviewText(String html) {
  return html
      .replaceAll(
          RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
              caseSensitive: false),
          ' ')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Widget _customComponentPlaceholder(Map<String, dynamic> element) {
  final String name =
      (element['custom_name']?.toString().trim().isNotEmpty ?? false)
          ? element['custom_name'].toString().trim()
          : 'Custom component';
  final String preview =
      _customHtmlPreviewText((element['custom_html'] ?? '').toString());
  final String id = (element['id'] ?? 'custom-component').toString();

  return Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 86),
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFF5F3FF), Color(0xFFEFF6FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: const Color(0xFF8B7CF6), width: 1.2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.code, color: Color(0xFF6554C0), size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF282044),
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            const Text('CUSTOM',
                style: TextStyle(
                    color: Color(0xFF6554C0),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.7)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          preview.isEmpty
              ? 'HTML / CSS / JS preview · scripts stay inactive on the canvas'
              : preview,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Color(0xFF55516A), fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 7),
        Text('id="$id"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFF77718E),
                fontSize: 9,
                fontFamily: 'monospace')),
      ],
    ),
  );
}

// ============================================================
//  SCREEN 2 : DRAG AND DROP EDITOR SCREEN
//  Modular, LEGO-like section builder:
//   - Pre-built BLOCKS (Header, Title & Description, Skills / Profile,
//     Footer) are single self-contained elements dragged from the sidebar.
//   - Individual WIDGETS (Text, Edit Number, Edit Text, Link, Button,
//     Image) still exist for fine-grained content.
//   - No free-form "div" containers anymore — every element sits directly
//     on the canvas and can be freely reordered by drag-and-drop.
//   - Deletion: tap an element to select it; a delete button appears
//     right on that element (and also in the properties panel) so there
//     is no more bottom trash zone or permanent "X" buttons.
// ============================================================
class DragDropEditorScreen extends StatefulWidget {
  final Map<String, dynamic> projectData;

  const DragDropEditorScreen({super.key, required this.projectData});

  @override
  _DragDropEditorScreenState createState() => _DragDropEditorScreenState();
}

class _DragDropEditorScreenState extends State<DragDropEditorScreen> {
  static const String _customComponentsStorageKey =
      'drag_drop_custom_components';
  static const List<String> _builtInFontFamilies = [
    'Arial',
    'Georgia',
    'Tahoma',
    'Times New Roman',
    'Courier New',
    'Verdana',
    'Trebuchet MS',
  ];

  late String projectName;
  List<Map<String, dynamic>> elements = [];
  List<Map<String, dynamic>> customComponents = [];
  Map<String, dynamic>? selectedElement;
  bool showCodePanel = false;
  int codeTabIndex = 0; // 0: HTML, 1: CSS, 2: JS
  String defaultFontFamily = 'Arial';
  Set<String> disabledFontFamilies = {};
  int _customElementCounter = 0;
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  late FlutterExceptionHandler _customComponentErrorHandler;
  bool _showingCustomComponentError = false;

  // ---- Custom Background Support (project-wide card/notebook background) ----
  // 'color' or 'image'. When 'image', canvasBgImage holds either a
  // "data:image/..." payload (device upload) or a plain http(s) URL.
  String canvasBgType = 'color';
  String canvasBgColor = '#ffffff';
  String canvasBgImage = '';

  // ---- Custom TTF Font Upload ----
  // fontFamilyName -> "data:font/ttf;base64,...." payload. Uploaded via the
  // sidebar's "Upload Font" action button and made available in every
  // font-family picker (_openFontPopup) alongside the built-in fonts.
  Map<String, String> customFonts = {};

  // Dropdown Menu Functionality: one GlobalKey per block ID, so the
  // header's "Menu" dropdown can scroll the canvas straight to whichever
  // section the user taps (Scrollable.ensureVisible needs a live key/
  // context for the target, not just its id string).
  final Map<String, GlobalKey> _sectionKeys = {};
  GlobalKey _keyForSection(String id) =>
      _sectionKeys.putIfAbsent(id, () => GlobalKey());

  static const List<String> blockTypes = [
    'header_block',
    'title_desc_block',
    'skills_block',
    'footer_block',
    'services_block',
    'portfolio_block',
    'testimonials_block',
    'contact_block',
    'store_block',
  ];

  @override
  void initState() {
    super.initState();
    _previousFlutterErrorHandler = FlutterError.onError;
    _customComponentErrorHandler = (details) {
      _previousFlutterErrorHandler?.call(details);
      if (!details.exceptionAsString().contains('_dependents.isEmpty')) {
        return;
      }
      final trace = StringBuffer()
        ..writeln(details.exceptionAsString())
        ..writeln()
        ..writeln('Flutter stack trace:')
        ..writeln(details.stack ?? '(No stack trace was provided.)');
      _showCustomComponentErrorDetails(trace.toString());
    };
    FlutterError.onError = _customComponentErrorHandler;

    projectName = widget.projectData['name'];
    elements =
        List<Map<String, dynamic>>.from(widget.projectData['elements'] ?? []);
    canvasBgType = widget.projectData['canvas_bg_type']?.toString() ?? 'color';
    canvasBgColor =
        widget.projectData['canvas_bg_color']?.toString() ?? '#ffffff';
    canvasBgImage = widget.projectData['canvas_bg_image']?.toString() ?? '';
    defaultFontFamily =
        widget.projectData['default_font_family']?.toString() ?? 'Arial';
    final savedDisabledFonts = widget.projectData['disabled_font_families'];
    if (savedDisabledFonts is Iterable) {
      disabledFontFamilies =
          savedDisabledFonts.map((font) => font.toString()).toSet();
    }
    if (widget.projectData['custom_fonts'] is Map) {
      customFonts = Map<String, String>.from(
          (widget.projectData['custom_fonts'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString())));
      _reloadCustomFontsIntoEngine();
    }
    if (_availableFontFamilies().isEmpty) {
      disabledFontFamilies.clear();
    }
    _loadCustomComponents();
  }

  void _showCustomComponentErrorDetails(String trace) {
    if (_showingCustomComponentError) return;
    _showingCustomComponentError = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _showingCustomComponentError = false;
        return;
      }
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Flutter error details'),
          content: SizedBox(
            width: 620,
            height: 440,
            child: SingleChildScrollView(
              child: SelectableText(
                trace,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: trace));
                Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy trace'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ).whenComplete(() => _showingCustomComponentError = false);
    });
  }

  @override
  void dispose() {
    if (identical(FlutterError.onError, _customComponentErrorHandler)) {
      FlutterError.onError = _previousFlutterErrorHandler;
    }
    super.dispose();
  }

  Future<void> _loadCustomComponents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_customComponentsStorageKey);
      if (stored == null || stored.trim().isEmpty) return;
      final decoded = json.decode(stored);
      if (decoded is! List) return;
      final loaded = decoded
          .whereType<Map>()
          .map((component) => Map<String, dynamic>.from(component.map(
              (key, value) => MapEntry(key.toString(), value))))
          .where((component) =>
              (component['id']?.toString().isNotEmpty ?? false) &&
              (component['name']?.toString().trim().isNotEmpty ?? false))
          .toList();
      if (!mounted) return;
      setState(() => customComponents = loaded);
    } catch (_) {
      // Keep the editor usable if a preferences value was interrupted or
      // written by an older version with an unexpected shape.
    }
  }

  Future<bool> _persistCustomComponents(
      List<Map<String, dynamic>> updated) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
          _customComponentsStorageKey, json.encode(updated));
      if (!saved) throw StateError('Preferences did not save the component.');
      if (!mounted) return false;
      setState(() => customComponents = updated);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save custom component: $e')));
      }
      return false;
    }
  }

  // FontLoader registrations don't persist across app restarts, so any
  // fonts saved with this project need to be re-registered with the
  // Flutter engine each time it's reopened, or the live canvas would fall
  // back to a system font even though the export still works correctly.
  Future<void> _reloadCustomFontsIntoEngine() async {
    for (final entry in customFonts.entries) {
      try {
        final comma = entry.value.indexOf(',');
        if (comma < 0) continue;
        final bytes = base64Decode(entry.value.substring(comma + 1));
        final fontLoader = FontLoader(entry.key);
        fontLoader.addFont(
            Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
        await fontLoader.load();
      } catch (_) {
        // Skip a corrupt/unreadable saved font rather than blocking the
        // rest of the project from loading.
      }
    }
  }

  void _saveAndReturn() {
    widget.projectData['elements'] = elements;
    widget.projectData['canvas_bg_type'] = canvasBgType;
    widget.projectData['canvas_bg_color'] = canvasBgColor;
    widget.projectData['canvas_bg_image'] = canvasBgImage;
    widget.projectData['custom_fonts'] = customFonts;
    widget.projectData['default_font_family'] = defaultFontFamily;
    widget.projectData['disabled_font_families'] =
        disabledFontFamilies.toList();
    widget.projectData['date'] = DateTime.now().toIso8601String();
    Navigator.pop(context, widget.projectData);
  }

  Future<void> _handleBackNavigation() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Save project?',
              style: TextStyle(color: Colors.white)),
          content: const Text('Do you want to save the current project?',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // discard, go back
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                Navigator.pop(context); // close dialog
                _saveAndReturn(); // same action as top-bar Save button
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  //  CODE GENERATION
  // ------------------------------------------------------------
  Map<String, String> _generateDesign() {
    final css = StringBuffer();
    final body = StringBuffer();
    final js = StringBuffer();
    final images = <String, String>{};
    final fonts = <String, String>{};

    css.writeln('        /* ===== Generated Design Styles ===== */');
    css.writeln('        * { box-sizing: border-box; }');
    css.writeln('        html { scroll-behavior: smooth; }');

    // Custom Background Support: the page/notebook background is either a
    // solid color or an image (uploaded from device, embedded as a data
    // URL into /images, or linked directly from a URL).
    String bodyBg;
    if (canvasBgType == 'image' && canvasBgImage.trim().isNotEmpty) {
      String bgUrl;
      if (canvasBgImage.startsWith('data:')) {
        final ext = _imageExt(canvasBgImage);
        final name = 'bg_${images.length + 1}.$ext';
        images[name] = canvasBgImage;
        bgUrl = 'images/$name';
      } else {
        bgUrl = _esc(canvasBgImage.trim());
      }
      bodyBg = 'background-image: url("$bgUrl"); background-size: cover; '
          'background-position: center; background-repeat: no-repeat; '
          'background-attachment: fixed;';
    } else {
      bodyBg =
          'background: ${canvasBgColor.trim().isEmpty ? "#f5f5f5" : canvasBgColor};';
    }
    final bodyFontFamily = defaultFontFamily
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"');
    css.writeln('        body { '
        'font-family: "$bodyFontFamily", Arial, sans-serif; margin: 0; padding: 0; '
        '$bodyBg }');
    css.writeln('        .sketch-canvas { '
        'max-width: 1100px; width: 100%; margin: 0 auto; overflow-x: hidden; }');
    css.writeln('        .sketch-canvas img { max-width: 100%; }');

    // Global Font Availability: every uploaded custom font gets a
    // @font-face rule pointing at /fonts/<file>, so it works as a normal
    // font-family value anywhere in the exported site.
    for (final entry in customFonts.entries) {
      final familyName = entry.key;
      final fileExt = _fontExt(entry.value);
      final fileName = '${_cleanId(familyName).replaceAll('-', '_')}.$fileExt';
      fonts[fileName] = entry.value;
      css.writeln('        @font-face { '
          'font-family: "$familyName"; src: url("fonts/$fileName"); '
          'font-display: swap; }');
    }

    for (var el in elements) {
      _compileElement(el, css, body, js, images);
    }

    final htmlCode = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$projectName</title>
    <style>
$css    </style>
</head>
<body>
    <div class="sketch-canvas">
$body    </div>
    <script>
$js    </script>
</body>
</html>''';

    return {
      'HTML': htmlCode,
      'CSS': css.toString(),
      'JS': js.toString(),
      'IMAGES': jsonEncode(images),
      'FONTS': jsonEncode(fonts),
    };
  }

  void _generateCodeAndNavigate() {
    final design = _generateDesign();
    final images =
        Map<String, String>.from(jsonDecode(design['IMAGES']!) as Map);
    final fonts = Map<String, String>.from(jsonDecode(design['FONTS']!) as Map);

    final projectJson = jsonEncode({
      'projectName': projectName,
      'files': {
        'HTML': design['HTML'],
        'CSS': design['CSS'],
        'JS': design['JS']
      },
      'fileNames': {
        'HTML': '$projectName.html',
        'CSS': 'style.css',
        'JS': 'script.js',
      },
      'images': images,
      'fonts': fonts,
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditorScreen(
          initialCode: projectJson,
          initialFileName: '$projectName.html',
        ),
      ),
    );
  }

  String _imageExt(String dataUrl) {
    final m = RegExp(r'data:image/([a-z0-9.+-]+)').firstMatch(dataUrl);
    final t = m?.group(1) ?? 'png';
    if (t == 'jpeg') return 'jpg';
    if (t.isEmpty) return 'png';
    return t;
  }

  // Fonts Folder Structure: picks a sensible file extension for an
  // uploaded font's data URL (almost always .ttf, since the sidebar
  // uploader only accepts .ttf files — see _uploadCustomFont).
  String _fontExt(String dataUrl) {
    final m = RegExp(r'data:font/([a-z0-9.+-]+)').firstMatch(dataUrl);
    final t = m?.group(1) ?? 'ttf';
    if (t.isEmpty) return 'ttf';
    return t;
  }

  void _compileElement(Map<String, dynamic> el, StringBuffer css,
      StringBuffer body, StringBuffer js, Map<String, String> images) {
    final String type = el['type'];
    final String id = _cleanId(el['id']);

    switch (type) {
      case 'header_block':
        _compileHeaderBlock(el, id, css, body, js, images);
        return;
      case 'title_desc_block':
        _compileTitleDescBlock(el, id, css, body);
        return;
      case 'skills_block':
        _compileSkillsBlock(el, id, css, body, images);
        return;
      case 'footer_block':
        _compileFooterBlock(el, id, css, body);
        return;
      case 'services_block':
        _compileServicesBlock(el, id, css, body, js);
        return;
      case 'portfolio_block':
        _compilePortfolioBlock(el, id, css, body);
        return;
      case 'testimonials_block':
        _compileTestimonialsBlock(el, id, css, body, js, images);
        return;
      case 'contact_block':
        _compileContactBlock(el, id, css, body, js);
        return;
      case 'store_block':
        _compileStoreBlock(el, id, css, body, js, images);
        return;
      case 'youtube_widget':
        _compileYoutubeWidget(el, id, css, body);
        return;
      case 'buttons_block':
        _compileButtonsBlock(el, id, css, body);
        return;
      case 'social_block':
        _compileSocialBlock(el, id, css, body);
        return;
      case 'custom':
        _compileCustomElement(el, id, css, body, js);
        return;
    }

    // ---- Individual widgets (text/link/button/edit_text/edit_number/image) ----
    // Every widget is wrapped in its own independent container div. The
    // container owns height, background color, and alignment; width is
    // always 100% (no width control is exposed to the user any more).
    final String text = el['text'] ?? '';
    final String hint = el['hint'] ?? '';
    final String url = el['url'] ?? '#';
    final String height = el['height'] ?? 'auto';
    final String containerBg = el['container_bg_color'] ?? 'transparent';
    final String padding = el['padding'] ?? '4px';
    final String margin = el['margin'] ?? '2px';
    final String color = el['color'] ?? '#000000';
    final String hintColor = el['hint_color'] ?? '#999999';
    final String bg = el['bg_color'] ?? '#ffffff';
    final String fontSize = el['font_size'] ?? '14px';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String textAlign = el['text_align'] ?? 'center';
    final String radius = el['border_radius'] ?? '4px';
    final String borderColor = el['border_color'] ?? '#cccccc';
    final String hoverCss = el['hover_css'] ?? '';
    final String activeCss = el['active_css'] ?? '';
    final String elemJs = el['js_code'] ?? '';
    // Text Widget Formatting: bold / underline / opacity, currently
    // exposed in the toolbar for the Text widget.
    final bool isBold = (el['bold']?.toString() ?? 'false') == 'true';
    final bool isUnderline = (el['underline']?.toString() ?? 'false') == 'true';
    final String opacityStr = (el['opacity']?.toString() ?? '100');
    final double opacityPct =
        double.tryParse(opacityStr.replaceAll('%', '')) ?? 100;

    final String flexAlign = textAlign == 'left'
        ? 'flex-start'
        : textAlign == 'right'
            ? 'flex-end'
            : 'center';

    // Container wrapper: height + background + alignment live here.
    css.writeln('        #${id}_wrap { '
        'width: 100%; height: $height; background-color: $containerBg; '
        'display: flex; align-items: center; justify-content: $flexAlign; '
        'box-sizing: border-box; padding: $padding; margin: $margin auto; }');

    // The widget itself fills its container's width/height.
    css.writeln('        #$id {');
    css.writeln('            width: 100%;');
    if (type != 'text') {
      css.writeln('            height: 100%;');
    }
    css.writeln('            color: $color;');
    css.writeln('            background-color: $bg;');
    css.writeln('            border: 1px solid $borderColor;');
    css.writeln('            border-radius: $radius;');
    css.writeln('            font-size: $fontSize;');
    css.writeln('            font-family: $fontFamily;');
    css.writeln('            text-align: $textAlign;');
    css.writeln('            box-sizing: border-box;');
    if (type == 'text') {
      if (isBold) css.writeln('            font-weight: bold;');
      if (isUnderline) css.writeln('            text-decoration: underline;');
      css.writeln('            opacity: ${(opacityPct / 100).clamp(0, 1)};');
    }
    if (type == 'image') {
      css.writeln('            display: block; object-fit: cover;');
    } else if (type == 'button') {
      css.writeln('            cursor: pointer;');
    }
    css.writeln('        }');
    if (type == 'edit_text' || type == 'edit_number') {
      css.writeln('        #$id::placeholder { color: $hintColor; }');
    }
    if (hoverCss.trim().isNotEmpty) {
      css.writeln('        #$id:hover {');
      css.writeln('            $hoverCss');
      css.writeln('        }');
    }
    if (activeCss.trim().isNotEmpty) {
      css.writeln('        #$id:active {');
      css.writeln('            $activeCss');
      css.writeln('        }');
    }

    body.writeln(
        '        <div id="${id}_wrap" class="widget-container"${_bgImageAttr(el, 'container_bg_image')}>');
    switch (type) {
      case 'text':
        body.writeln('            <p id="$id">${_esc(text)}</p>');
        break;
      case 'button':
        final clickJs = el['click_js']?.toString() ?? '';
        body.writeln(
            '            <button id="$id" ${clickJs.trim().isNotEmpty ? "onclick=\"${_escJs(clickJs)}\"" : ''}>${_esc(text)}</button>');
        break;
      case 'link':
        final clickJs = el['click_js']?.toString() ?? '';
        final target =
            '${_escJs(clickJs)}${_escJs(clickJs).isNotEmpty ? ';' : ''}window.open("${_esc(url)}", "_blank");return false;';
        body.writeln(
            '            <a id="$id" href="${_esc(url)}" onclick="return !(function(){ $target })();">${_esc(text)}</a>');
        break;
      case 'edit_text':
      case 'edit_number':
        final inputType = type == 'edit_number' ? 'number' : 'text';
        body.writeln('            <input id="$id" type="$inputType" '
            'placeholder="${_esc(hint)}" />');
        break;
      case 'image':
        final src = el['src']?.toString() ?? '';
        if (src.isNotEmpty && src.startsWith('data:')) {
          final ext = _imageExt(src);
          final name = 'image_${images.length + 1}.$ext';
          images[name] = src;
          body.writeln('            <img id="$id" src="images/$name" '
              'alt="image" />');
        } else {
          body.writeln(
              '            <img id="$id" src="${_esc(src)}" alt="image" />');
        }
        break;
      default:
        body.writeln('            <div id="$id"></div>');
        break;
    }
    body.writeln('        </div>');

    if (elemJs.trim().isNotEmpty) {
      js.writeln('        // JS for #$id');
      js.writeln(elemJs);
      js.writeln('');
    }
  }

  void _compileCustomElement(Map<String, dynamic> el, String id,
      StringBuffer css, StringBuffer body, StringBuffer js) {
    final String name = (el['custom_name'] ?? 'Custom component').toString();
    final String fontFamily =
        (el['font_family'] ?? defaultFontFamily)
            .toString()
            .replaceAll('\\', r'\\')
            .replaceAll('"', r'\"');
    final String safeCommentName =
        name.replaceAll(RegExp(r'[\r\n*/]'), ' ').trim();
    final String html = (el['custom_html'] ?? '').toString();
    final String customCss = (el['custom_css'] ?? '').toString();
    final String customJs = (el['custom_js'] ?? '').toString();

    css.writeln('        /* Custom component: $safeCommentName (#$id) */');
    css.writeln('        #$id { font-family: "$fontFamily"; }');
    if (customCss.trim().isNotEmpty) {
      css.writeln(customCss.replaceAll('{{ROOT}}', '#$id'));
      css.writeln();
    }

    body.writeln('        <div id="$id" class="custom-component">');
    body.writeln(html);
    body.writeln('        </div>');

    if (customJs.trim().isNotEmpty) {
      js.writeln('        // Custom component: $safeCommentName (#$id)');
      js.writeln('        (function () {');
      js.writeln('          var customRoot = document.getElementById("$id");');
      js.writeln('          if (!customRoot) return;');
      js.writeln(customJs.replaceAll('{{ROOT}}', 'customRoot'));
      js.writeln('        })();');
      js.writeln();
    }
  }

  // YouTube Widget Integration: renders as a clickable thumbnail card
  // (thumbnail + centered play button + title) that opens the real video
  // in a new tab — no embedded iframe/API key needed.
  void _compileYoutubeWidget(
      Map<String, dynamic> el, String id, StringBuffer css, StringBuffer body) {
    final String videoUrl = (el['video_url'] ?? '').toString().trim();
    final String videoId = (el['video_id'] ?? '').toString().trim();
    final String title = (el['title'] ?? '').toString().trim();
    final String thumb = (el['thumb_src'] ?? '').toString().trim();
    final String radius = el['border_radius'] ?? '10px';
    final String resolvedThumb = thumb.isNotEmpty
        ? thumb
        : (videoId.isNotEmpty
            ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
            : '');

    css.writeln('        #$id { display: block; position: relative; '
        'width: 100%; max-width: 480px; margin: 8px auto; text-decoration: none; }');
    css.writeln('        #$id .yt-thumb { position: relative; width: 100%; '
        'padding-top: 56.25%; background-color: #000; background-size: cover; '
        'background-position: center; border-radius: $radius; overflow: hidden; }');
    css.writeln(
        '        #$id .yt-play { position: absolute; top: 50%; left: 50%; '
        'transform: translate(-50%, -50%); width: 64px; height: 46px; '
        'background: rgba(0,0,0,0.75); border-radius: 12px; display: flex; '
        'align-items: center; justify-content: center; }');
    css.writeln(
        '        #$id .yt-play::after { content: ""; border-style: solid; '
        'border-width: 11px 0 11px 18px; border-color: transparent transparent '
        'transparent #ffffff; margin-left: 4px; }');
    css.writeln('        #$id .yt-title { margin-top: 8px; font-size: 14px; '
        'font-weight: 600; color: #222; font-family: Arial; text-align: center; }');

    if (videoUrl.isEmpty) {
      // No link set yet: show the same "paste a link" affordance as the
      // editor placeholder, so an accidentally-exported empty widget is
      // still self-explanatory rather than a blank box.
      body.writeln(
          '        <div id="$id" class="yt-thumb" style="display:flex;align-items:center;'
          'justify-content:center;color:#aaa;font-family:Arial;font-size:13px;">'
          'YouTube video (no link set)</div>');
      return;
    }

    body.writeln(
        '        <a id="$id" href="${_esc(videoUrl)}" target="_blank" rel="noopener">');
    body.writeln('            <div class="yt-thumb"'
        '${resolvedThumb.isNotEmpty ? ' style="background-image: url(\'${_esc(resolvedThumb)}\');"' : ''}>');
    body.writeln('                <div class="yt-play"></div>');
    body.writeln('            </div>');
    if (title.isNotEmpty) {
      body.writeln('            <div class="yt-title">${_esc(title)}</div>');
    }
    body.writeln('        </a>');
  }

  // ---- Custom Buttons block: user-defined button collection, each ----
  // routable to either an internal section anchor or an external URL.
  void _compileButtonsBlock(
      Map<String, dynamic> el, String id, StringBuffer css, StringBuffer body) {
    final String bg = el['bg_color'] ?? '#ffffff';
    final List<Map<String, dynamic>> buttons =
        List<Map<String, dynamic>>.from((el['buttons'] as List?) ?? []);

    css.writeln('        #$id { background-color: $bg; padding: 24px 20px; }');
    css.writeln(
        '        #$id .buttons-row { display: flex; flex-wrap: wrap; gap: 12px; '
        'justify-content: center; align-items: center; }');
    css.writeln(
        '        #$id .custom-btn { border: none; cursor: pointer; text-decoration: none; '
        'display: inline-flex; align-items: center; justify-content: center; }');

    body.writeln(
        '        <section id="$id" class="buttons-section"${_bgImageAttr(el)}>');
    body.writeln('            <div class="buttons-row">');
    for (int i = 0; i < buttons.length; i++) {
      final b = buttons[i];
      final String btnId = '${id}_btn_$i';
      final String text = (b['text'] ?? 'Button').toString();
      final String bgColor = (b['bg_color'] ?? '#1565c0').toString();
      final String textColor = (b['text_color'] ?? '#ffffff').toString();
      final String fontSize = (b['font_size'] ?? '14px').toString();
      final String radius = (b['border_radius'] ?? '8px').toString();
      final String fontFamily = (b['font_family'] ?? 'Arial').toString();
      final String linkType = (b['link_type'] ?? 'section').toString();

      css.writeln(
          '        #$btnId { background-color: $bgColor; color: $textColor; '
          'font-size: $fontSize; font-family: $fontFamily; border-radius: $radius; '
          'padding: 12px 22px; font-weight: 600; }');
      css.writeln('        #$btnId:hover { opacity: 0.9; }');

      if (linkType == 'url') {
        final String url = (b['url'] ?? '#').toString().trim();
        body.writeln(
            '                <a id="$btnId" class="custom-btn" href="${_esc(url.isEmpty ? '#' : url)}" target="_blank" rel="noopener">${_esc(text)}</a>');
      } else {
        final String target = _cleanId((b['target'] ?? '').toString());
        body.writeln(
            '                <a id="$btnId" class="custom-btn" href="#$target">${_esc(text)}</a>');
      }
    }
    body.writeln('            </div>');
    body.writeln('        </section>');
  }

  // ---- Social Media Bar: platform icon links, full-color or mono ----
  void _compileSocialBlock(
      Map<String, dynamic> el, String id, StringBuffer css, StringBuffer body) {
    final String bg = el['bg_color'] ?? '#ffffff';
    final String iconStyle = (el['icon_style'] ?? 'color').toString();
    final String iconSize = (el['icon_size'] ?? '32px').toString();
    final List<Map<String, dynamic>> items =
        List<Map<String, dynamic>>.from((el['items'] as List?) ?? []);

    const Map<String, String> brandColors = {
      'facebook': '#1877F2',
      'whatsapp': '#25D366',
      'telegram': '#26A5E4',
      'x': '#000000',
      'instagram': '#E1306C',
      'github': '#333333',
    };
    const Map<String, String> initials = {
      'facebook': 'f',
      'whatsapp': 'W',
      'telegram': 'T',
      'x': 'X',
      'instagram': 'IG',
      'github': 'GH',
    };

    css.writeln('        #$id { background-color: $bg; padding: 20px; }');
    css.writeln(
        '        #$id .social-row { display: flex; flex-wrap: wrap; gap: 14px; '
        'justify-content: center; align-items: center; }');
    css.writeln(
        '        #$id .social-icon { width: $iconSize; height: $iconSize; '
        'border-radius: 50%; display: flex; align-items: center; justify-content: center; '
        'text-decoration: none; color: #ffffff; font-family: Arial; font-weight: 700; '
        'font-size: calc($iconSize / 2.2); }');

    body.writeln(
        '        <section id="$id" class="social-section"${_bgImageAttr(el)}>');
    body.writeln('            <div class="social-row">');
    for (final item in items) {
      final String platform = (item['platform'] ?? '').toString();
      final String url = (item['url'] ?? '').toString().trim();
      final String color = iconStyle == 'mono'
          ? '#333333'
          : (brandColors[platform] ?? '#555555');
      final String label = initials[platform] ?? '?';
      body.writeln(
          '                <a class="social-icon" style="background-color: $color;" '
          'href="${_esc(url.isEmpty ? '#' : url)}" target="_blank" rel="noopener" '
          'aria-label="${_esc(platform)}">${_esc(label)}</a>');
    }
    body.writeln('            </div>');
    body.writeln('        </section>');
  }

  // ---- Block-specific compilers ----

  void _compileHeaderBlock(Map<String, dynamic> el, String id, StringBuffer css,
      StringBuffer body, StringBuffer js, Map<String, String> images) {
    final String bg = el['bg_color'] ?? '#0277BD';
    final String height = el['height'] ?? '70px';
    final String navColor = el['nav_color'] ?? '#ffffff';
    final String navFontSize = el['nav_font_size'] ?? '14px';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String logoSrc = (el['logo_src']?.toString() ?? '').trim();
    final String headerText = (el['header_text'] ?? '').toString();
    final List<Map<String, dynamic>> navItems =
        List<Map<String, dynamic>>.from((el['nav_items'] as List?) ?? []);

    // Header ("Navigation Bar") Section: image + descriptive text sit on
    // the far left; a "Menu" label with a 3-line hamburger icon sits on
    // the far right. Clicking it toggles a dropdown panel — built,
    // styled, and wired up entirely in the exported site's own HTML/
    // CSS/JS below (this is what actually ships to visitors; it has
    // nothing to do with how the editor renders its own mock preview).
    css.writeln('        #$id { position: relative; display: flex; '
        'align-items: center; justify-content: space-between; flex-wrap: wrap; '
        'gap: 12px; min-height: $height; background-color: $bg; padding: 10px 24px; }');
    css.writeln(
        '        #$id .header-left { display: flex; align-items: center; gap: 10px; '
        'min-width: 0; }');
    css.writeln(
        '        #$id .logo-img { height: 42px; width: auto; border-radius: 6px; object-fit: cover; flex-shrink: 0; }');
    css.writeln(
        '        #$id .header-text { color: $navColor; font-size: $navFontSize; '
        'font-family: $fontFamily; font-weight: 600; overflow: hidden; '
        'text-overflow: ellipsis; white-space: nowrap; }');
    css.writeln(
        '        #$id .menu-toggle { display: flex; align-items: center; gap: 8px; '
        'background: none; border: none; cursor: pointer; padding: 6px 4px; '
        'flex-shrink: 0; }');
    css.writeln(
        '        #$id .menu-toggle .menu-label { color: $navColor; font-size: $navFontSize; '
        'font-family: $fontFamily; font-weight: 600; }');
    css.writeln(
        '        #$id .hamburger-icon { display: flex; flex-direction: column; gap: 4px; }');
    css.writeln(
        '        #$id .hamburger-icon span { display: block; width: 24px; height: 3px; '
        'background-color: $navColor; border-radius: 2px; transition: transform 0.2s ease, '
        'opacity 0.2s ease; }');
    // The dropdown animates via opacity/transform (not display:none/flex,
    // which can't transition) so "Menu" opens and closes with a smooth
    // fade + slide instead of an instant snap.
    css.writeln(
        '        #$id .nav-menu { display: flex; flex-direction: column; '
        'position: absolute; top: 100%; right: 24px; margin-top: 8px; '
        'background-color: $bg; border-radius: 8px; overflow: hidden; z-index: 50; '
        'box-shadow: 0 6px 18px rgba(0,0,0,0.2); min-width: 180px; max-width: min(90vw, 320px); '
        'opacity: 0; visibility: hidden; transform: translateY(-8px); '
        'transition: opacity 0.18s ease, transform 0.18s ease, visibility 0.18s ease; '
        'pointer-events: none; }');
    css.writeln(
        '        #$id .nav-menu.open { opacity: 1; visibility: visible; '
        'transform: translateY(0); pointer-events: auto; }');
    css.writeln(
        '        #$id .nav-menu a { color: $navColor; font-size: $navFontSize; '
        'font-family: $fontFamily; text-decoration: none; font-weight: 600; '
        'cursor: pointer; padding: 12px 18px; white-space: nowrap; overflow: hidden; '
        'text-overflow: ellipsis; }');
    css.writeln(
        '        #$id .nav-menu a:hover { background-color: rgba(255,255,255,0.15); }');
    // Responsiveness: on narrow screens the dropdown spans edge-to-edge
    // under the header instead of risking clipping off the right side.
    css.writeln('        @media (max-width: 480px) {');
    css.writeln(
        '            #$id .nav-menu { left: 16px; right: 16px; min-width: 0; '
        'max-width: none; }');
    css.writeln('        }');

    body.writeln('        <header id="$id"${_bgImageAttr(el)}>');
    body.writeln('            <div class="header-left">');
    if (logoSrc.isNotEmpty) {
      if (logoSrc.startsWith('data:')) {
        final ext = _imageExt(logoSrc);
        final name = 'image_${images.length + 1}.$ext';
        images[name] = logoSrc;
        body.writeln(
            '                <img class="logo-img" src="images/$name" alt="logo" />');
      } else {
        body.writeln(
            '                <img class="logo-img" src="${_esc(logoSrc)}" alt="logo" />');
      }
    }
    if (headerText.isNotEmpty) {
      body.writeln(
          '                <span class="header-text">${_esc(headerText)}</span>');
    }
    body.writeln('            </div>');
    final String menuBtnId = '${id}_menu_btn';
    final String menuId = '${id}_menu';
    body.writeln(
        '            <button type="button" class="menu-toggle" id="$menuBtnId" '
        'aria-label="Menu" aria-haspopup="true" aria-expanded="false" '
        'aria-controls="$menuId">');
    body.writeln('                <span class="menu-label">Menu</span>');
    body.writeln(
        '                <span class="hamburger-icon"><span></span><span></span><span></span></span>');
    body.writeln('            </button>');
    // Hidden/toggleable dropdown container, populated dynamically from
    // this header's own nav_items list (Home, About, etc.) — each link
    // targets a real section id on the page via data-scroll-target,
    // resolved by the smooth-scroll JS below rather than a bare "#" jump.
    body.writeln('            <nav class="nav-menu" id="$menuId">');
    for (final item in navItems) {
      final label = (item['label'] ?? '').toString();
      final target = _cleanId((item['target'] ?? '').toString());
      body.writeln(
          '                <a href="#$target" data-scroll-target="$target">${_esc(label)}</a>');
    }
    body.writeln('            </nav>');
    body.writeln('        </header>');

    // Lightweight vanilla JS: toggles the dropdown on button click, and
    // smooth-scrolls to the clicked link's target section via
    // scrollIntoView (rather than relying on the browser's native "#"
    // anchor jump), then closes the menu again.
    js.writeln("        (function(){");
    js.writeln("            function initMenu() {");
    js.writeln(
        "                var btn = document.getElementById('$menuBtnId');");
    js.writeln(
        "                var menu = document.getElementById('$menuId');");
    js.writeln("                if (!btn || !menu) return false;");
    js.writeln("                if (btn.dataset.initialized) return true;");
    js.writeln("                btn.dataset.initialized = 'true';");
    js.writeln("                function closeMenu() {");
    js.writeln("                    menu.classList.remove('open');");
    js.writeln(
        "                    btn.setAttribute('aria-expanded', 'false');");
    js.writeln("                }");
    js.writeln("                function toggleMenu(e) {");
    js.writeln("                    e.stopPropagation();");
    js.writeln(
        "                    var isOpen = menu.classList.toggle('open');");
    js.writeln(
        "                    btn.setAttribute('aria-expanded', isOpen ? 'true' : 'false');");
    js.writeln("                }");
    js.writeln("                btn.addEventListener('click', toggleMenu);");
    js.writeln(
        "                menu.querySelectorAll('a').forEach(function(a){");
    js.writeln("                    a.addEventListener('click', function(e){");
    js.writeln("                        e.preventDefault();");
    js.writeln("                        closeMenu();");
    js.writeln(
        "                        var targetId = a.getAttribute('data-scroll-target');");
    js.writeln(
        "                        var targetEl = targetId ? document.getElementById(targetId) : null;");
    js.writeln("                        if (targetEl) {");
    js.writeln(
        "                            targetEl.scrollIntoView({ behavior: 'smooth', block: 'start' });");
    js.writeln("                        }");
    js.writeln("                    });");
    js.writeln("                });");
    js.writeln(
        "                document.addEventListener('click', function(e){");
    js.writeln(
        "                    if (!menu.contains(e.target) && e.target !== btn) closeMenu();");
    js.writeln("                });");
    js.writeln(
        "                document.addEventListener('keydown', function(e){");
    js.writeln("                    if (e.key === 'Escape') closeMenu();");
    js.writeln("                });");
    js.writeln("                return true;");
    js.writeln("            }");
    js.writeln("            if (!initMenu()) {");
    js.writeln("                var attempts = 0;");
    js.writeln("                var timer = setInterval(function() {");
    js.writeln("                    attempts++;");
    js.writeln("                    if (initMenu() || attempts > 20) {");
    js.writeln("                        clearInterval(timer);");
    js.writeln("                    }");
    js.writeln("                }, 100);");
    js.writeln("            }");
    js.writeln("        })();");
  }

  void _compileTitleDescBlock(
      Map<String, dynamic> el, String id, StringBuffer css, StringBuffer body) {
    final String bg = el['bg_color'] ?? '#ffffff';
    final String titleColor = el['title_color'] ?? '#000000';
    final String descColor = el['desc_color'] ?? '#444444';
    final String titleSize = el['title_font_size'] ?? '26px';
    final String descSize = el['desc_font_size'] ?? '15px';
    final String title = el['title'] ?? '';
    final String desc = el['description'] ?? '';
    final String fontFamily = el['font_family'] ?? 'Arial';
    // Title & Description Text Alignment: 'left' | 'center' | 'right'.
    final String textAlign = el['text_align'] ?? 'center';
    final String pMargin = textAlign == 'center' ? '0 auto' : '0';

    css.writeln(
        '        #$id { background-color: $bg; padding: 48px 20px; text-align: $textAlign; }');
    css.writeln(
        '        #$id h2 { color: $titleColor; font-size: $titleSize; font-family: $fontFamily; margin: 0 0 12px 0; }');
    css.writeln(
        '        #$id p { color: $descColor; font-size: $descSize; font-family: $fontFamily; max-width: 700px; '
        'margin: $pMargin; line-height: 1.6; }');

    body.writeln('        <section id="$id"${_bgImageAttr(el)}>');
    body.writeln('            <h2>${_esc(title)}</h2>');
    body.writeln('            <p>${_esc(desc)}</p>');
    body.writeln('        </section>');
  }

  void _compileSkillsBlock(Map<String, dynamic> el, String id, StringBuffer css,
      StringBuffer body, Map<String, String> images) {
    final String bg = el['bg_color'] ?? '#f7f7f7';
    final String radius = el['image_radius'] ?? '16px';
    final String descColor = el['desc_color'] ?? '#333333';
    final String descSize = el['desc_font_size'] ?? '15px';
    final String desc = el['description'] ?? '';
    final String src = (el['image_src']?.toString() ?? '').trim();
    final String fontFamily = el['font_family'] ?? 'Arial';

    css.writeln(
        '        #$id { background-color: $bg; padding: 48px 20px; text-align: center; }');
    css.writeln(
        '        #$id img { max-width: 280px; width: 100%; height: auto; '
        'border-radius: $radius; object-fit: cover; }');
    css.writeln(
        '        #$id p { color: $descColor; font-size: $descSize; font-family: $fontFamily; max-width: 600px; '
        'margin: 18px auto 0; line-height: 1.6; }');

    body.writeln('        <section id="$id"${_bgImageAttr(el)}>');
    if (src.isNotEmpty) {
      if (src.startsWith('data:')) {
        final ext = _imageExt(src);
        final name = 'image_${images.length + 1}.$ext';
        images[name] = src;
        body.writeln('            <img src="images/$name" alt="profile" />');
      } else {
        body.writeln('            <img src="${_esc(src)}" alt="profile" />');
      }
    }
    body.writeln('            <p>${_esc(desc)}</p>');
    body.writeln('        </section>');
  }

  void _compileFooterBlock(
      Map<String, dynamic> el, String id, StringBuffer css, StringBuffer body) {
    final String bg = el['bg_color'] ?? '#161616';
    final String color = el['color'] ?? '#ffffff';
    final String size = el['font_size'] ?? '12px';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String text = el['text'] ?? '';

    css.writeln(
        '        #$id { background-color: $bg; color: $color; font-size: $size; '
        'font-family: $fontFamily; text-align: center; padding: 20px 12px; }');

    body.writeln(
        '        <footer id="$id"${_bgImageAttr(el)}>${_esc(text)}</footer>');
  }

  // ---- Services block: card carousel with autoplay + manual swipe ----
  void _compileServicesBlock(Map<String, dynamic> el, String id,
      StringBuffer css, StringBuffer body, StringBuffer js) {
    final String bg = el['bg_color'] ?? '#ffffff';
    final String cardBg = el['card_bg_color'] ?? '#f7f7f7';
    final String titleColor = el['title_color'] ?? '#000000';
    final String descColor = el['desc_color'] ?? '#555555';
    final String titleSize = el['title_font_size'] ?? '18px';
    final String descSize = el['desc_font_size'] ?? '13px';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String autoplaySeconds = el['autoplay_seconds'] ?? '3';
    final List<Map<String, dynamic>> services =
        List<Map<String, dynamic>>.from((el['services'] as List?) ?? []);

    css.writeln('        #$id { background-color: $bg; padding: 44px 20px; }');
    css.writeln('        #$id .services-track { display: flex; gap: 16px; '
        'overflow-x: auto; scroll-snap-type: x mandatory; scroll-behavior: smooth; '
        '-webkit-overflow-scrolling: touch; padding-bottom: 8px; }');
    css.writeln(
        '        #$id .services-track::-webkit-scrollbar { height: 0; }');
    css.writeln(
        '        #$id .service-card { flex: 0 0 220px; scroll-snap-align: start; '
        'background-color: $cardBg; border-radius: 10px; padding: 20px; box-sizing: border-box; }');
    css.writeln(
        '        #$id .service-card h3 { color: $titleColor; font-size: $titleSize; '
        'font-family: $fontFamily; margin: 0 0 8px 0; }');
    css.writeln(
        '        #$id .service-card p { color: $descColor; font-size: $descSize; '
        'font-family: $fontFamily; margin: 0; line-height: 1.5; }');

    body.writeln(
        '        <section id="$id" class="services-section"${_bgImageAttr(el)}>');
    body.writeln('            <div class="services-track">');
    for (final s in services) {
      body.writeln('                <div class="service-card">');
      body.writeln(
          '                    <h3>${_esc((s['title'] ?? '').toString())}</h3>');
      body.writeln(
          '                    <p>${_esc((s['description'] ?? '').toString())}</p>');
      body.writeln('                </div>');
    }
    body.writeln('            </div>');
    body.writeln('        </section>');

    js.writeln("        (function(){");
    js.writeln(
        "            var track = document.querySelector('#$id .services-track');");
    js.writeln("            if (!track) return;");
    js.writeln(
        "            var autoplayMs = ${_jsNum(autoplaySeconds, 3)} * 1000;");
    js.writeln("            var paused = false, resumeTimer = null;");
    js.writeln("            function next(){");
    js.writeln("                if (paused) return;");
    js.writeln(
        "                var card = track.querySelector('.service-card');");
    js.writeln(
        "                var step = card ? card.offsetWidth + 16 : 220;");
    js.writeln(
        "                if (track.scrollLeft + track.clientWidth >= track.scrollWidth - 5) {");
    js.writeln(
        "                    track.scrollTo({left: 0, behavior: 'smooth'});");
    js.writeln("                } else {");
    js.writeln(
        "                    track.scrollBy({left: step, behavior: 'smooth'});");
    js.writeln("                }");
    js.writeln("            }");
    js.writeln("            setInterval(next, autoplayMs);");
    js.writeln("            function onManual(){");
    js.writeln("                paused = true;");
    js.writeln("                clearTimeout(resumeTimer);");
    js.writeln(
        "                resumeTimer = setTimeout(function(){ paused = false; }, autoplayMs);");
    js.writeln("            }");
    js.writeln(
        "            track.addEventListener('touchstart', onManual, {passive: true});");
    js.writeln("            track.addEventListener('mousedown', onManual);");
    js.writeln(
        "            track.addEventListener('wheel', onManual, {passive: true});");
    js.writeln("        })();");
  }

  // ---- Portfolio block: project cards in a clean horizontal row ----
  void _compilePortfolioBlock(
      Map<String, dynamic> el, String id, StringBuffer css, StringBuffer body) {
    final String bg = el['bg_color'] ?? '#ffffff';
    final String cardBg = el['card_bg_color'] ?? '#f7f7f7';
    final String titleColor = el['title_color'] ?? '#000000';
    final String descColor = el['desc_color'] ?? '#555555';
    final String titleSize = el['title_font_size'] ?? '18px';
    final String descSize = el['desc_font_size'] ?? '13px';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final List<Map<String, dynamic>> projects =
        List<Map<String, dynamic>>.from((el['projects'] as List?) ?? []);

    css.writeln('        #$id { background-color: $bg; padding: 44px 20px; }');
    css.writeln('        #$id .portfolio-row { display: flex; flex-wrap: wrap; '
        'gap: 18px; justify-content: center; }');
    css.writeln(
        '        #$id .project-card { flex: 0 1 240px; background-color: $cardBg; '
        'border-radius: 10px; padding: 18px; text-decoration: none; display: block; '
        'box-sizing: border-box; transition: transform .2s ease; }');
    css.writeln(
        '        #$id .project-card:hover { transform: translateY(-4px); }');
    css.writeln(
        '        #$id .project-card h3 { color: $titleColor; font-size: $titleSize; '
        'font-family: $fontFamily; margin: 0 0 8px 0; }');
    css.writeln(
        '        #$id .project-card p { color: $descColor; font-size: $descSize; '
        'font-family: $fontFamily; margin: 0 0 8px 0; line-height: 1.5; }');
    css.writeln(
        '        #$id .project-card .project-link { display: inline-block; '
        'color: $titleColor; font-size: $descSize; font-family: $fontFamily; '
        'text-decoration: underline; margin: 0; }');

    body.writeln(
        '        <section id="$id" class="portfolio-section"${_bgImageAttr(el)}>');
    body.writeln('            <div class="portfolio-row">');
    for (final p in projects) {
      final String url = (p['url'] ?? '').toString().trim();
      final String linkText = (p['link_text'] ?? '').toString().trim().isEmpty
          ? 'Click here to view the project'
          : (p['link_text'] ?? '').toString();
      body.writeln(
          '                <a class="project-card" href="${_esc(url.isEmpty ? '#' : url)}" target="_blank" rel="noopener">');
      body.writeln(
          '                    <h3>${_esc((p['title'] ?? '').toString())}</h3>');
      body.writeln(
          '                    <p>${_esc((p['description'] ?? '').toString())}</p>');
      body.writeln(
          '                    <span class="project-link">${_esc(linkText)}</span>');
      body.writeln('                </a>');
    }
    body.writeln('            </div>');
    body.writeln('        </section>');
  }

  // ---- Testimonials block: vertical auto-rotating feedback cards ----
  void _compileTestimonialsBlock(
      Map<String, dynamic> el,
      String id,
      StringBuffer css,
      StringBuffer body,
      StringBuffer js,
      Map<String, String> images) {
    final String bg = el['bg_color'] ?? '#f7f7f7';
    final String nameColor = el['name_color'] ?? '#000000';
    final String textColor = el['text_color'] ?? '#555555';
    final String nameSize = el['name_font_size'] ?? '15px';
    final String textSize = el['text_font_size'] ?? '13px';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String sectionHeight = el['section_height'] ?? '160px';
    final List<Map<String, dynamic>> testimonials =
        List<Map<String, dynamic>>.from((el['testimonials'] as List?) ?? []);

    css.writeln('        #$id { background-color: $bg; padding: 30px 20px; }');
    css.writeln(
        '        #$id .testimonials-viewport { max-width: 420px; margin: 0 auto; '
        'height: $sectionHeight; overflow: hidden; position: relative; }');
    css.writeln(
        '        #$id .testimonials-track { display: flex; flex-direction: column; '
        'transition: transform .6s ease; }');
    css.writeln(
        '        #$id .testimonial-card { height: $sectionHeight; display: flex; '
        'flex-direction: column; align-items: center; justify-content: center; '
        'text-align: center; padding: 12px; box-sizing: border-box; }');
    css.writeln('        #$id .testimonial-photo { width: 64px; height: 64px; '
        'border-radius: 50%; object-fit: cover; margin-bottom: 10px; background: #ddd; }');
    css.writeln(
        '        #$id .testimonial-name { color: $nameColor; font-size: $nameSize; '
        'font-family: $fontFamily; font-weight: 600; margin-bottom: 6px; }');
    css.writeln(
        '        #$id .testimonial-feedback { color: $textColor; font-size: $textSize; '
        'font-family: $fontFamily; line-height: 1.5; }');

    body.writeln(
        '        <section id="$id" class="testimonials-section"${_bgImageAttr(el)}>');
    body.writeln('            <div class="testimonials-viewport">');
    body.writeln('                <div class="testimonials-track">');
    for (final t in testimonials) {
      final String photo = (t['photo'] ?? '').toString().trim();
      String photoSrc = '';
      if (photo.isNotEmpty) {
        if (photo.startsWith('data:')) {
          final ext = _imageExt(photo);
          final name = 'image_${images.length + 1}.$ext';
          images[name] = photo;
          photoSrc = 'images/$name';
        } else {
          photoSrc = photo;
        }
      }
      body.writeln('                    <div class="testimonial-card">');
      if (photoSrc.isNotEmpty) {
        body.writeln(
            '                        <img class="testimonial-photo" src="${_esc(photoSrc)}" alt="" />');
      } else {
        body.writeln(
            '                        <div class="testimonial-photo"></div>');
      }
      body.writeln(
          '                        <div class="testimonial-name">${_esc((t['name'] ?? '').toString())}</div>');
      body.writeln(
          '                        <div class="testimonial-feedback">${_esc((t['feedback'] ?? '').toString())}</div>');
      body.writeln('                    </div>');
    }
    body.writeln('                </div>');
    body.writeln('            </div>');
    body.writeln('        </section>');

    js.writeln("        (function(){");
    js.writeln(
        "            var track = document.querySelector('#$id .testimonials-track');");
    js.writeln(
        "            var viewport = document.querySelector('#$id .testimonials-viewport');");
    js.writeln("            if (!track || !viewport) return;");
    js.writeln("            var count = track.children.length;");
    js.writeln("            if (count <= 1) return;");
    js.writeln("            var index = 0;");
    js.writeln("            setInterval(function(){");
    js.writeln("                index = (index + 1) % count;");
    js.writeln(
        "                track.style.transform = 'translateY(' + (-index * viewport.offsetHeight) + 'px)';");
    js.writeln("            }, 2000);");
    js.writeln("        })();");
  }

  // ---- Contact block: heading + description + email CTA (mailto) ----
  void _compileContactBlock(Map<String, dynamic> el, String id,
      StringBuffer css, StringBuffer body, StringBuffer js) {
    final String bg = el['bg_color'] ?? '#ffffff';
    final String headingColor = el['heading_color'] ?? '#000000';
    final String descColor = el['desc_color'] ?? '#555555';
    final String headingSize = el['heading_font_size'] ?? '24px';
    final String descSize = el['desc_font_size'] ?? '14px';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String heading = el['heading'] ?? '';
    final String description = el['description'] ?? '';
    final String buttonText = el['button_text'] ?? 'Send Email';
    final String buttonColor = el['button_color'] ?? '#1565c0';
    final String buttonTextColor = el['button_text_color'] ?? '#ffffff';
    final String ownerEmail = (el['owner_email'] ?? '').toString().trim();
    final String emailId = '${id}_email';
    final String btnId = '${id}_btn';

    css.writeln(
        '        #$id { background-color: $bg; padding: 44px 20px; text-align: center; }');
    css.writeln(
        '        #$id h2 { color: $headingColor; font-size: $headingSize; '
        'font-family: $fontFamily; margin: 0 0 10px 0; }');
    css.writeln('        #$id p { color: $descColor; font-size: $descSize; '
        'font-family: $fontFamily; max-width: 560px; margin: 0 auto 22px; line-height: 1.6; }');
    css.writeln(
        '        #$id .contact-form { display: flex; flex-wrap: wrap; gap: 10px; '
        'justify-content: center; align-items: center; max-width: 460px; margin: 0 auto; }');
    css.writeln(
        '        #$id .contact-form input[type=email] { flex: 1 1 220px; '
        'padding: 12px 14px; border-radius: 6px; border: 1px solid #ccc; font-size: 14px; '
        'font-family: $fontFamily; }');
    css.writeln(
        '        #$id .contact-form button { padding: 12px 22px; border: none; '
        'border-radius: 6px; background-color: $buttonColor; color: $buttonTextColor; font-weight: 600; '
        'font-family: $fontFamily; cursor: pointer; }');
    css.writeln('        #$id .contact-form button:hover { opacity: 0.9; }');

    body.writeln(
        '        <section id="$id" class="contact-section"${_bgImageAttr(el)}>');
    body.writeln('            <h2>${_esc(heading)}</h2>');
    body.writeln('            <p>${_esc(description)}</p>');
    body.writeln('            <div class="contact-form">');
    body.writeln(
        '                <input type="email" id="$emailId" placeholder="Your email address" />');
    body.writeln(
        '                <button type="button" id="$btnId">${_esc(buttonText)}</button>');
    body.writeln('            </div>');
    body.writeln('        </section>');

    js.writeln("        (function(){");
    js.writeln("            var btn = document.getElementById('$btnId');");
    js.writeln("            var input = document.getElementById('$emailId');");
    js.writeln("            if (!btn) return;");
    js.writeln("            btn.addEventListener('click', function(){");
    js.writeln(
        "                var visitor = input ? input.value.trim() : '';");
    js.writeln(
        "                var subject = encodeURIComponent('New message from your website');");
    js.writeln(
        "                var body = encodeURIComponent('From: ' + (visitor || '(no email provided)') + '\\n\\n');");
    js.writeln(
        "                window.location.href = 'mailto:${_escJsString(ownerEmail)}?subject=' + subject + '&body=' + body;");
    js.writeln("            });");
    js.writeln("        })();");
  }

  // ---- Store block: search bar + product grid + detail modal ----
  void _compileStoreBlock(Map<String, dynamic> el, String id, StringBuffer css,
      StringBuffer body, StringBuffer js, Map<String, String> images) {
    final String bg = el['bg_color'] ?? '#ffffff';
    final String cardBg = el['card_bg_color'] ?? '#f7f7f7';
    final String titleColor = el['title_color'] ?? '#000000';
    final String priceColor = el['price_color'] ?? '#e53935';
    final String descColor = el['desc_color'] ?? '#555555';
    final String buttonColor = el['button_color'] ?? '#1565c0';
    final String fontFamily = el['font_family'] ?? 'Arial';
    final List<Map<String, dynamic>> products =
        List<Map<String, dynamic>>.from((el['products'] as List?) ?? []);
    final String modalId = '${id}_modal';

    css.writeln('        #$id { background-color: $bg; padding: 44px 20px; }');
    css.writeln(
        '        #$id .store-search { display: block; width: 100%; max-width: 420px; '
        'margin: 0 auto 24px; padding: 12px 14px; border-radius: 6px; border: 1px solid #ccc; '
        'font-size: 14px; font-family: $fontFamily; box-sizing: border-box; }');
    css.writeln(
        '        #$id .store-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); '
        'gap: 16px; }');
    css.writeln(
        '        #$id .store-card { background-color: $cardBg; border-radius: 10px; '
        'padding: 14px; cursor: pointer; box-sizing: border-box; transition: transform .2s ease; }');
    css.writeln(
        '        #$id .store-card:hover { transform: translateY(-3px); }');
    css.writeln(
        '        #$id .store-card img { width: 100%; height: 120px; object-fit: cover; '
        'border-radius: 6px; margin-bottom: 10px; background: #e0e0e0; }');
    css.writeln(
        '        #$id .store-title { color: $titleColor; font-size: 15px; '
        'font-family: $fontFamily; font-weight: 600; margin-bottom: 4px; }');
    css.writeln(
        '        #$id .store-price { color: $priceColor; font-size: 14px; '
        'font-family: $fontFamily; font-weight: 600; margin-bottom: 6px; }');
    css.writeln(
        '        #$id .store-desc-short { color: $descColor; font-size: 12px; '
        'font-family: $fontFamily; margin: 0; line-height: 1.4; }');
    css.writeln(
        '        #$id .store-modal { display: none; position: fixed; inset: 0; '
        'background: rgba(0,0,0,0.6); z-index: 9999; align-items: center; justify-content: center; '
        'padding: 20px; }');
    css.writeln('        #$id .store-modal.open { display: flex; }');
    css.writeln(
        '        #$id .store-modal-inner { background: #ffffff; border-radius: 10px; '
        'max-width: 360px; width: 100%; padding: 26px; position: relative; text-align: center; '
        'font-family: $fontFamily; }');
    css.writeln(
        '        #$id .store-modal-close { position: absolute; top: 8px; right: 14px; '
        'cursor: pointer; font-size: 22px; color: #888; line-height: 1; }');
    css.writeln(
        '        #$id .store-modal-img { width: 100%; max-height: 180px; object-fit: cover; '
        'border-radius: 8px; margin-bottom: 14px; background: #e0e0e0; }');
    css.writeln(
        '        #$id .store-modal-title { color: $titleColor; font-size: 18px; '
        'font-weight: 700; margin: 0 0 6px 0; }');
    css.writeln(
        '        #$id .store-modal-price { color: $priceColor; font-size: 15px; '
        'font-weight: 600; margin-bottom: 10px; }');
    css.writeln(
        '        #$id .store-modal-desc { color: $descColor; font-size: 13px; '
        'line-height: 1.6; margin: 0 0 16px 0; }');
    css.writeln(
        '        #$id .store-modal-btn { display: inline-block; padding: 11px 24px; '
        'border-radius: 6px; background-color: $buttonColor; color: #ffffff; text-decoration: none; '
        'font-weight: 600; }');

    body.writeln(
        '        <section id="$id" class="store-section"${_bgImageAttr(el)}>');
    body.writeln(
        '            <input type="text" class="store-search" placeholder="Search products..." />');
    body.writeln('            <div class="store-grid">');
    for (final p in products) {
      final String name = (p['name'] ?? '').toString();
      final String price = (p['price'] ?? '').toString();
      final String desc = (p['description'] ?? '').toString();
      final String btnText = (p['button_text'] ?? 'Order Now').toString();
      final String btnUrl = (p['button_url'] ?? '').toString().trim();
      // Store Section Card Backgrounds: an individual product can override
      // the block-wide card background color; falls back to $cardBg.
      final String cardBgForThis =
          (p['bg_color']?.toString().trim().isNotEmpty ?? false)
              ? p['bg_color'].toString().trim()
              : cardBg;
      final String img = (p['image'] ?? '').toString().trim();
      String imgSrc = '';
      if (img.isNotEmpty) {
        if (img.startsWith('data:')) {
          final ext = _imageExt(img);
          final imgName = 'image_${images.length + 1}.$ext';
          images[imgName] = img;
          imgSrc = 'images/$imgName';
        } else {
          imgSrc = img;
        }
      }
      body.writeln('                <div class="store-card" '
          'style="background-color: ${_esc(cardBgForThis)};" '
          'data-name="${_esc(name)}" data-price="${_esc(price)}" data-desc="${_esc(desc)}" '
          'data-img="${_esc(imgSrc)}" data-btntext="${_esc(btnText)}" '
          'data-url="${_esc(btnUrl.isEmpty ? '#' : btnUrl)}">');
      if (imgSrc.isNotEmpty) {
        body.writeln(
            '                    <img src="${_esc(imgSrc)}" alt="${_esc(name)}" />');
      } else {
        body.writeln('                    <img alt="" />');
      }
      body.writeln(
          '                    <div class="store-title">${_esc(name)}</div>');
      body.writeln(
          '                    <div class="store-price">${_esc(price)}</div>');
      body.writeln(
          '                    <p class="store-desc-short">${_esc(desc)}</p>');
      body.writeln('                </div>');
    }
    body.writeln('            </div>');
    body.writeln('            <div class="store-modal" id="$modalId">');
    body.writeln('                <div class="store-modal-inner">');
    body.writeln(
        '                    <span class="store-modal-close">&times;</span>');
    body.writeln('                    <img class="store-modal-img" alt="" />');
    body.writeln('                    <h3 class="store-modal-title"></h3>');
    body.writeln('                    <div class="store-modal-price"></div>');
    body.writeln('                    <p class="store-modal-desc"></p>');
    body.writeln(
        '                    <a class="store-modal-btn" target="_blank" rel="noopener"></a>');
    body.writeln('                </div>');
    body.writeln('            </div>');
    body.writeln('        </section>');

    js.writeln("        (function(){");
    js.writeln("            var root = document.getElementById('$id');");
    js.writeln("            if (!root) return;");
    js.writeln("            var search = root.querySelector('.store-search');");
    js.writeln("            var cards = root.querySelectorAll('.store-card');");
    js.writeln("            var modal = document.getElementById('$modalId');");
    js.writeln("            if (search) {");
    js.writeln("                search.addEventListener('input', function(){");
    js.writeln(
        "                    var q = search.value.trim().toLowerCase();");
    js.writeln("                    cards.forEach(function(card){");
    js.writeln(
        "                        var name = (card.getAttribute('data-name') || '').toLowerCase();");
    js.writeln(
        "                        card.style.display = name.indexOf(q) !== -1 ? '' : 'none';");
    js.writeln("                    });");
    js.writeln("                });");
    js.writeln("            }");
    js.writeln("            cards.forEach(function(card){");
    js.writeln("                card.addEventListener('click', function(){");
    js.writeln("                    if (!modal) return;");
    js.writeln(
        "                    modal.querySelector('.store-modal-img').src = card.getAttribute('data-img') || '';");
    js.writeln(
        "                    modal.querySelector('.store-modal-title').textContent = card.getAttribute('data-name') || '';");
    js.writeln(
        "                    modal.querySelector('.store-modal-price').textContent = card.getAttribute('data-price') || '';");
    js.writeln(
        "                    modal.querySelector('.store-modal-desc').textContent = card.getAttribute('data-desc') || '';");
    js.writeln(
        "                    var btn = modal.querySelector('.store-modal-btn');");
    js.writeln(
        "                    btn.textContent = card.getAttribute('data-btntext') || 'Order Now';");
    js.writeln(
        "                    btn.href = card.getAttribute('data-url') || '#';");
    js.writeln("                    modal.classList.add('open');");
    js.writeln("                });");
    js.writeln("            });");
    js.writeln("            if (modal) {");
    js.writeln(
        "                modal.querySelector('.store-modal-close').addEventListener('click', function(){");
    js.writeln("                    modal.classList.remove('open');");
    js.writeln("                });");
    js.writeln("                modal.addEventListener('click', function(e){");
    js.writeln(
        "                    if (e.target === modal) modal.classList.remove('open');");
    js.writeln("                });");
    js.writeln("            }");
    js.writeln("        })();");
  }

  // Escapes text for safe embedding inside a single-quoted JS string
  // literal in a generated <script> block (distinct from _escJs, which
  // escapes for inline HTML event-handler attributes).
  String _escJsString(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n');
  }

  String _jsNum(String val, num def) {
    final m = RegExp(r'[\d.]+').firstMatch(val);
    return m != null ? m.group(0)! : def.toString();
  }

  void _openPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PreviewScreen(projectName: projectName, elements: elements),
      ),
    );
  }

  // ------------------------------------------------------------
  //  DELETE
  // ------------------------------------------------------------
  void _deleteElement(Map<String, dynamic> el) {
    setState(() {
      elements.remove(el);
      if (selectedElement == el) selectedElement = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF161616),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: const Color(0xFF222222),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(projectName,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleBackNavigation,
            tooltip: 'Back',
          ),
          actions: [
            TextButton.icon(
                onPressed: _generateCodeAndNavigate,
                icon:
                    const Icon(Icons.chevron_right, color: Colors.orangeAccent),
                label: const Text('Generate',
                    style: TextStyle(color: Colors.orangeAccent)),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.orangeAccent)),
            IconButton(
                icon: const Icon(Icons.save, color: Colors.greenAccent),
                onPressed: _saveAndReturn,
                tooltip: 'Save'),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Left palette: Blocks + Widgets ----
                  Container(
                    width: 150,
                    color: const Color(0xFF222222),
                    child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        _paletteSectionHeader('BLOCKS', Icons.view_agenda,
                            Colors.deepPurpleAccent),
                        _buildPaletteItem('Header', 'header_block',
                            Icons.web_asset, Colors.deepPurpleAccent),
                        _buildPaletteItem('Title & Desc.', 'title_desc_block',
                            Icons.text_snippet, Colors.deepPurpleAccent),
                        _buildPaletteItem('Skills / Profile', 'skills_block',
                            Icons.person_pin, Colors.deepPurpleAccent),
                        _buildPaletteItem(
                            'Footer',
                            'footer_block',
                            Icons.vertical_align_bottom,
                            Colors.deepPurpleAccent),
                        const Divider(color: Colors.grey),
                        _paletteSectionHeader('SECTIONS',
                            Icons.dashboard_customize, Colors.orangeAccent),
                        _buildPaletteItem('Services', 'services_block',
                            Icons.design_services, Colors.orangeAccent),
                        _buildPaletteItem('Portfolio', 'portfolio_block',
                            Icons.work_outline, Colors.orangeAccent),
                        _buildPaletteItem('Testimonials', 'testimonials_block',
                            Icons.format_quote, Colors.orangeAccent),
                        _buildPaletteItem('Contact', 'contact_block',
                            Icons.mail_outline, Colors.orangeAccent),
                        _buildPaletteItem('Store', 'store_block',
                            Icons.storefront, Colors.orangeAccent),
                        _buildPaletteItem('Custom Buttons', 'buttons_block',
                            Icons.smart_button, Colors.orangeAccent),
                        _buildPaletteItem('Social Bar', 'social_block',
                            Icons.share, Colors.orangeAccent),
                        const Divider(color: Colors.grey),
                        _paletteSectionHeader(
                            'WIDGETS', Icons.widgets, Colors.lightBlueAccent),
                        _buildPaletteItem('Text', 'text', Icons.text_fields,
                            Colors.lightBlueAccent),
                        _buildPaletteItem('Edit Number', 'edit_number',
                            Icons.pin, Colors.lightBlueAccent),
                        _buildPaletteItem('Edit Text', 'edit_text', Icons.input,
                            Colors.lightBlueAccent),
                        _buildPaletteItem(
                            'Link', 'link', Icons.link, Colors.lightBlueAccent),
                        _buildPaletteItem('Button', 'button',
                            Icons.smart_button, Colors.lightBlueAccent),
                        _buildPaletteItem('Image', 'image', Icons.image,
                            Colors.lightBlueAccent),
                        // YouTube Widget Integration: dedicated draggable
                        // widget. The play-icon/arrow badge on its chip
                        // signals it accepts a pasted video link (set once
                        // dropped, via the properties panel).
                        _buildPaletteItem('YouTube Video', 'youtube_widget',
                            Icons.smart_display, Colors.redAccent),
                        const Divider(color: Colors.grey),
                        _paletteSectionHeader(
                            'TOOLS', Icons.build, Colors.amberAccent),
                        _buildActionPaletteItem(
                            'Custom',
                            Icons.code,
                            Colors.deepPurpleAccent,
                            _openCustomComponentsDialog),
                        ...customComponents
                            .map(_buildCustomComponentPaletteItem),
                        _buildActionPaletteItem(
                            'Fonts & Typography',
                            Icons.text_fields,
                            Colors.amberAccent,
                            _openFontSettings),
                        // Sidebar Font Uploader: a direct action button
                        // (not draggable — tapping it immediately opens the
                        // file picker) rather than a widget dropped onto
                        // the canvas.
                        _buildActionPaletteItem(
                            'Upload Font (.ttf)',
                            Icons.font_download,
                            Colors.amberAccent,
                            _uploadCustomFont),
                        // Custom Background Support: opens the page
                        // background settings (solid color or image).
                        _buildActionPaletteItem(
                            'Page Background',
                            Icons.wallpaper,
                            Colors.amberAccent,
                            _openCanvasBackgroundPopup),
                      ],
                    ),
                  ),

                  // ---- Center: Phone Frame canvas ----
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, canvasConstraints) {
                        // Real phone aspect ratio (~9:19.5), scaled down to
                        // fit the available space so it stays shaped like
                        // an actual phone screen instead of a stretched box.
                        const double phoneAspect = 9 / 19.5;
                        double availW = canvasConstraints.maxWidth - 16;
                        double availH = canvasConstraints.maxHeight - 16;
                        double frameW = availW;
                        double frameH = frameW / phoneAspect;
                        if (frameH > availH) {
                          frameH = availH;
                          frameW = frameH * phoneAspect;
                        }
                        return Center(
                          child: Container(
                            width: frameW,
                            height: frameH,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.grey.shade700, width: 4),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                color: Colors.white,
                                child: Column(
                                  children: [
                                    // Header shows project name directly
                                    Container(
                                      height: 28,
                                      color: const Color(0xFF0277BD),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        projectName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      child: DragTarget<Object>(
                                        onAcceptWithDetails: (details) {
                                          setState(() {
                                            final element =
                                                _elementFromPaletteData(
                                                    details.data);
                                            if (element != null) {
                                              elements.add(element);
                                              selectedElement = element;
                                            }
                                          });
                                        },
                                        builder: (context, candidateData,
                                            rejectedData) {
                                          // Custom Background Support: the
                                          // notebook canvas shows either the
                                          // solid color or the uploaded/
                                          // linked background image, live.
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: _parseColor(canvasBgColor),
                                              image:
                                                  (canvasBgType == 'image' &&
                                                          canvasBgImage
                                                              .trim()
                                                              .isNotEmpty)
                                                      ? DecorationImage(
                                                          image: canvasBgImage
                                                                  .startsWith(
                                                                      'data:')
                                                              ? MemoryImage(base64Decode(
                                                                      canvasBgImage.substring(
                                                                          canvasBgImage.indexOf(',') +
                                                                              1)))
                                                                  as ImageProvider
                                                              : NetworkImage(
                                                                      canvasBgImage)
                                                                  as ImageProvider,
                                                          fit: BoxFit.cover,
                                                        )
                                                      : null,
                                            ),
                                            child: elements.isEmpty
                                                ? const Center(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .drag_indicator,
                                                            color: Colors.grey,
                                                            size: 36),
                                                        SizedBox(height: 6),
                                                        Text(
                                                            'Drag a block or '
                                                            'widget here',
                                                            style: TextStyle(
                                                                color:
                                                                    Colors.grey,
                                                                fontSize: 11)),
                                                      ],
                                                    ),
                                                  )
                                                : ListView(
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    children:
                                                        _buildInsertableChildren(
                                                            elements),
                                                  ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
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
            if (showCodePanel) _codePanel(),
            if (selectedElement != null) _propertiesPanel(),
          ],
        ),
      ),
    );
  }

  Widget _codePanel() {
    final design = _generateDesign();
    final htmlCode = design['HTML'] ?? '';
    final cssCode = design['CSS'] ?? '';
    final jsCode = design['JS'] ?? '';
    final list = [htmlCode, cssCode, jsCode];
    return Container(
      height: 180,
      color: const Color(0xFF0D0D0D),
      child: Column(
        children: [
          Container(
            color: Colors.black,
            child: Row(
              children: [
                _codeTabButton('HTML', 0),
                _codeTabButton('CSS', 1),
                _codeTabButton('JS', 2),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Live code updates automatically',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => setState(() => showCodePanel = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: SelectableText(
                  list[codeTabIndex].trim().isEmpty
                      ? '// Nothing here yet.'
                      : list[codeTabIndex],
                  style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeTabButton(String title, int index) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor:
            codeTabIndex == index ? Colors.tealAccent : Colors.transparent,
      ),
      onPressed: () => setState(() => codeTabIndex = index),
      child: Text(title,
          style: TextStyle(
              color: codeTabIndex == index ? Colors.black : Colors.tealAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold)),
    );
  }

  // ------------------------------------------------------------
  //  PROPERTIES PANEL (shown for the tapped/selected element)
  // ------------------------------------------------------------
  // Bottom Toolbar (Properties Bar) Redesign: taller bar, larger buttons
  // with breathing room between them, and a short 2–4 word label under
  // each icon describing exactly what it does.
  Widget _propertiesPanel() {
    return Container(
      height: 108,
      color: const Color(0xFF222222),
      child: Column(
        children: [
          Container(
            height: 24,
            color: Colors.black,
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.tune, color: Colors.grey, size: 13),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_typeLabel(selectedElement!['type']),
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                // Dedicated delete option for the selected item.
                IconButton(
                  icon: const Icon(Icons.delete,
                      color: Colors.redAccent, size: 16),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete this element',
                  onPressed: () => _deleteElement(selectedElement!),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => selectedElement = null),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: _buildToolbarIcons()),
            ),
          ),
        ],
      ),
    );
  }

  // Trims a full tooltip down to a short 2–4 word label for display under
  // the toolbar icon (e.g. "ID (used as scroll target for nav buttons)"
  // becomes just "ID"; "Background color" is already short and passes
  // through unchanged). The full text always stays available via the
  // long-press Tooltip.
  String _toolbarShortLabel(String tooltip) {
    String base = tooltip.split('(').first.trim();
    final words = base.split(RegExp(r'\s+'));
    if (words.length > 4) {
      base = words.take(4).join(' ');
    }
    return base;
  }

  List<Widget> _buildToolbarIcons() {
    final String type = selectedElement!['type'];
    final List<Widget> icons = [];

    void add(IconData icon, String tooltip, VoidCallback onTap,
        {Color color = Colors.white}) {
      final String shortLabel = _toolbarShortLabel(tooltip);
      icons.add(Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 72,
            height: 76,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2E2E2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 5),
                Text(
                  shortLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color == Colors.white
                          ? Colors.white70
                          : color.withOpacity(0.85),
                      fontSize: 9,
                      height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ));
    }

    if (type == 'custom') {
      add(Icons.code, 'Edit custom HTML, CSS and JS',
          _editSelectedCustomComponent,
          color: Colors.deepPurpleAccent);
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'Wrapper ID',
          () => _openTextFieldPopup('Wrapper ID', 'id'));
      return icons;
    }

    // Background Image Customization for All Divs: every section-level
    // block can swap its solid background color for a custom image
    // (device upload or URL). Individual widgets get the equivalent
    // control further below, tied to their own container.
    const Set<String> bgImageBlockTypes = {
      'header_block',
      'title_desc_block',
      'skills_block',
      'footer_block',
      'services_block',
      'portfolio_block',
      'testimonials_block',
      'contact_block',
      'store_block',
      'buttons_block',
      'social_block',
    };
    if (bgImageBlockTypes.contains(type)) {
      add(Icons.image, 'Background image URL',
          () => _openTextFieldPopup('Background image URL', 'bg_image'));
      add(Icons.photo_library, 'Choose background image from device',
          () => _pickImageInto('bg_image'));
    }

    if (type == 'header_block') {
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.height, 'Header height',
          () => _openSizePopup('Height', 'height', max: 160));
      add(Icons.link, 'Logo image URL',
          () => _openTextFieldPopup('Logo image URL', 'logo_src'));
      add(Icons.photo_library, 'Choose logo from device',
          () => _pickImageInto('logo_src'));
      add(Icons.text_fields, 'Header text (next to image)',
          () => _openTextFieldPopup('Header text', 'header_text'));
      add(Icons.menu, 'Manage menu sections', _openNavItemsPopup);
      add(Icons.palette, 'Text color',
          () => _openColorPopup('Text color', 'nav_color'));
      add(Icons.format_size, 'Font size',
          () => _openSizePopup('Font size', 'nav_font_size', max: 40));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID', () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'title_desc_block') {
      add(Icons.title, 'Title text',
          () => _openTextFieldPopup('Title text', 'title'));
      add(Icons.notes, 'Description text',
          () => _openTextFieldPopup('Description text', 'description'));
      add(Icons.format_align_center, 'Text alignment', _openAlignPopup);
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.palette, 'Title color',
          () => _openColorPopup('Title color', 'title_color'));
      add(Icons.format_color_text, 'Description color',
          () => _openColorPopup('Description color', 'desc_color'));
      add(Icons.format_size, 'Title font size',
          () => _openSizePopup('Title font size', 'title_font_size', max: 60));
      add(
          Icons.format_size,
          'Description font size',
          () => _openSizePopup('Description font size', 'desc_font_size',
              max: 40));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'skills_block') {
      add(Icons.image_search, 'Image URL',
          () => _openTextFieldPopup('Image URL', 'image_src'));
      add(Icons.photo_library, 'Choose image from device',
          () => _pickImageInto('image_src'));
      add(
          Icons.rounded_corner,
          'Image border radius',
          () =>
              _openSizePopup('Image border radius', 'image_radius', max: 200));
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.notes, 'Description text',
          () => _openTextFieldPopup('Description text', 'description'));
      add(Icons.format_color_text, 'Description color',
          () => _openColorPopup('Description color', 'desc_color'));
      add(
          Icons.format_size,
          'Description font size',
          () => _openSizePopup('Description font size', 'desc_font_size',
              max: 40));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'footer_block') {
      add(Icons.notes, 'Footer text',
          () => _openTextFieldPopup('Footer text', 'text'));
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.palette, 'Text color',
          () => _openColorPopup('Text color', 'color'));
      add(Icons.format_size, 'Font size',
          () => _openSizePopup('Font size', 'font_size', max: 40));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID', () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'services_block') {
      add(Icons.view_carousel, 'Manage service cards', _openServicesPopup);
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.dashboard, 'Card background color',
          () => _openColorPopup('Card background color', 'card_bg_color'));
      add(Icons.palette, 'Title color',
          () => _openColorPopup('Title color', 'title_color'));
      add(Icons.format_color_text, 'Description color',
          () => _openColorPopup('Description color', 'desc_color'));
      add(Icons.format_size, 'Title font size',
          () => _openSizePopup('Title font size', 'title_font_size', max: 40));
      add(
          Icons.format_size,
          'Description font size',
          () => _openSizePopup('Description font size', 'desc_font_size',
              max: 30));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(
          Icons.timer,
          'Autoplay speed (seconds)',
          () => _openSizePopup('Autoplay speed (seconds)', 'autoplay_seconds',
              max: 15,
              descriptionText:
                  'Type how many seconds each card stays visible before auto-sliding to the next one, for example 3 (meaning 3 seconds).',
              hintText: 'e.g. 3 (seconds)'));
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'portfolio_block') {
      add(Icons.view_module, 'Manage projects', _openProjectsPopup);
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.dashboard, 'Card background color',
          () => _openColorPopup('Card background color', 'card_bg_color'));
      add(Icons.palette, 'Title color',
          () => _openColorPopup('Title color', 'title_color'));
      add(Icons.format_color_text, 'Description color',
          () => _openColorPopup('Description color', 'desc_color'));
      add(Icons.format_size, 'Title font size',
          () => _openSizePopup('Title font size', 'title_font_size', max: 40));
      add(
          Icons.format_size,
          'Description font size',
          () => _openSizePopup('Description font size', 'desc_font_size',
              max: 30));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'testimonials_block') {
      add(Icons.reviews, 'Manage testimonials', _openTestimonialsPopup);
      add(Icons.height, 'Section height',
          () => _openSizePopup('Section height', 'section_height', max: 500));
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.palette, 'Name color',
          () => _openColorPopup('Name color', 'name_color'));
      add(Icons.format_color_text, 'Feedback text color',
          () => _openColorPopup('Feedback text color', 'text_color'));
      add(Icons.format_size, 'Name font size',
          () => _openSizePopup('Name font size', 'name_font_size', max: 30));
      add(
          Icons.format_size,
          'Feedback font size',
          () =>
              _openSizePopup('Feedback font size', 'text_font_size', max: 30));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'contact_block') {
      add(Icons.title, 'Heading text',
          () => _openTextFieldPopup('Heading text', 'heading'));
      add(Icons.notes, 'Description text',
          () => _openTextFieldPopup('Description text', 'description'));
      add(Icons.smart_button, 'Button text',
          () => _openTextFieldPopup('Button text', 'button_text'));
      add(Icons.email, 'Owner email (where messages are sent)',
          () => _openTextFieldPopup('Owner email', 'owner_email'));
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.palette, 'Heading color',
          () => _openColorPopup('Heading color', 'heading_color'));
      add(Icons.format_color_text, 'Description color',
          () => _openColorPopup('Description color', 'desc_color'));
      add(Icons.format_paint, 'Button color',
          () => _openColorPopup('Button color', 'button_color'));
      add(Icons.palette, 'Button text color',
          () => _openColorPopup('Button text color', 'button_text_color'));
      add(
          Icons.format_size,
          'Heading font size',
          () => _openSizePopup('Heading font size', 'heading_font_size',
              max: 60));
      add(
          Icons.format_size,
          'Description font size',
          () => _openSizePopup('Description font size', 'desc_font_size',
              max: 30));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'store_block') {
      add(Icons.inventory_2, 'Manage products', _openProductsPopup);
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.dashboard, 'Card background color',
          () => _openColorPopup('Card background color', 'card_bg_color'));
      add(Icons.palette, 'Title color',
          () => _openColorPopup('Title color', 'title_color'));
      add(Icons.sell, 'Price color',
          () => _openColorPopup('Price color', 'price_color'));
      add(Icons.format_color_text, 'Description color',
          () => _openColorPopup('Description color', 'desc_color'));
      add(Icons.format_paint, 'Button color',
          () => _openColorPopup('Button color', 'button_color'));
      add(Icons.abc, 'Font family', _openFontPopup);
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'youtube_widget') {
      // YouTube Widget Integration: pasting the link auto-fetches the
      // thumbnail + title; both can still be overridden manually below.
      add(Icons.smart_display, 'YouTube link', _openYoutubeLinkPopup);
      add(Icons.title, 'Video title (override)',
          () => _openTextFieldPopup('Video title', 'title'));
      add(Icons.image, 'Thumbnail image URL (override)',
          () => _openTextFieldPopup('Thumbnail image URL', 'thumb_src'));
      add(Icons.rounded_corner, 'Corner rounding',
          () => _openSizePopup('Corner rounding', 'border_radius', max: 60));
      add(Icons.mode_standby, 'ID', () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'buttons_block') {
      add(Icons.smart_button, 'Manage buttons', _openCustomButtonsPopup);
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else if (type == 'social_block') {
      add(Icons.share, 'Manage social icons', _openSocialIconsPopup);
      add(Icons.format_color_fill, 'Background color',
          () => _openColorPopup('Background color', 'bg_color'));
      add(Icons.rounded_corner, 'Icon size',
          () => _openSizePopup('Icon size', 'icon_size', max: 80));
      add(Icons.style, 'Icon style (color / mono)', _openSocialStylePopup);
      add(Icons.mode_standby, 'ID (used as scroll target for nav buttons)',
          () => _openTextFieldPopup('ID', 'id'));
    } else {
      // ---- Individual widgets: Text, Button, Edit Number, Edit Text,
      // Link, Image. Each is wrapped in its own container div (width is
      // always 100% and is not user-adjustable any more).
      add(
          Icons.height,
          'Container height',
          () => _openSizePopup('Container height', 'height',
              max: 800, allowAuto: true));
      add(
          Icons.format_color_fill,
          'Container background color',
          () => _openColorPopup(
              'Container background color', 'container_bg_color'));
      add(
          Icons.image,
          'Container background image URL',
          () => _openTextFieldPopup(
              'Container background image URL', 'container_bg_image'));
      add(Icons.photo_library, 'Choose container background image',
          () => _pickImageInto('container_bg_image'));
      add(Icons.format_align_center, 'Text align', _openAlignPopup);
      add(Icons.padding, 'Padding',
          () => _openSizePopup('Padding', 'padding', max: 100));
      add(Icons.margin, 'Margin',
          () => _openSizePopup('Margin', 'margin', max: 100));
      add(Icons.mode_standby, 'ID', () => _openTextFieldPopup('ID', 'id'));
      add(Icons.touch_app, 'On Click', _openOnClickPanel,
          color: const Color(0xFFF7DF1E));

      if (['text', 'link', 'button', 'edit_text', 'edit_number']
          .contains(type)) {
        add(Icons.text_fields, 'Text content',
            () => _openTextFieldPopup('Text content', 'text'));
        add(Icons.abc, 'Font family', _openFontPopup);
        add(Icons.format_size, 'Font size',
            () => _openSizePopup('Font size', 'font_size', max: 60));
        add(Icons.border_color, 'Border color',
            () => _openColorPopup('Border color', 'border_color'));
        add(
            Icons.palette,
            type == 'button' ? 'Button text color' : 'Text color',
            () => _openColorPopup(
                type == 'button' ? 'Button text color' : 'Text color',
                'color'));
      }

      // Text Widget Formatting Enhancements: Bold, Underline and opacity
      // controls for the Text widget.
      if (type == 'text') {
        add(Icons.format_bold, 'Bold / Underline / Opacity',
            _openTextFormatPopup);
      }

      // Background Colors: expose the widget's own background-color
      // control (key 'bg_color') for Buttons, Text, Edit Number and
      // Edit Text, matching the styling controls other elements get.
      // Each defaults to a solid white background (#ffffff) except the
      // button, which defaults to its accent color.
      if (['button', 'text', 'edit_text', 'edit_number'].contains(type)) {
        add(
            Icons.format_paint,
            type == 'button' ? 'Button background color' : 'Background color',
            () => _openColorPopup(
                type == 'button'
                    ? 'Button background color'
                    : 'Background color',
                'bg_color'));
      }

      if (type == 'button') {
        add(Icons.rounded_corner, 'Border radius',
            () => _openSizePopup('Border radius', 'border_radius', max: 60));
      }

      if (type == 'link') {
        add(Icons.link, 'Destination URL',
            () => _openTextFieldPopup('Destination URL', 'url'));
      }

      if (type == 'edit_text' || type == 'edit_number') {
        add(Icons.help_outline, 'Placeholder / hint text',
            () => _openTextFieldPopup('Placeholder / hint text', 'hint'));
        add(Icons.format_color_text, 'Hint color',
            () => _openColorPopup('Hint color', 'hint_color'));
      }

      if (type == 'image') {
        add(Icons.image_search, 'Image URL',
            () => _openTextFieldPopup('Image URL', 'src'));
        add(Icons.photo_library, 'Choose image from device',
            () => _pickImageInto('src'));
      }
    }

    return icons;
  }

  Widget _popupQuickChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.blueAccent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
    );
  }

  void _openTextFieldPopup(String label, String key) {
    final ctrl =
        TextEditingController(text: selectedElement?[key]?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          minLines: 1,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Type here...',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() => selectedElement![key] = ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openSizePopup(String label, String key,
      {bool allowAuto = false,
      bool allowPct = false,
      int max = 600,
      String? descriptionText,
      String? hintText}) {
    final ctrl =
        TextEditingController(text: selectedElement?[key]?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(descriptionText ?? 'Type the value, for example 120px or 50%',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: hintText ?? 'e.g. 120px',
                hintStyle: const TextStyle(color: Colors.grey),
                enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent)),
              ),
            ),
            if (allowAuto || allowPct) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  if (allowAuto)
                    _popupQuickChip('Auto', () {
                      setState(() => selectedElement![key] = 'auto');
                      Navigator.pop(context);
                    }),
                  if (allowPct)
                    _popupQuickChip('100%', () {
                      setState(() => selectedElement![key] = '100%');
                      Navigator.pop(context);
                    }),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() => selectedElement![key] = ctrl.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatches(String key, TextEditingController hexCtrl) {
    const palette = [
      '#000000',
      '#ffffff',
      '#e53935',
      '#f57c00',
      '#fbc02d',
      '#43a047',
      '#1e88e5',
      '#8e24aa',
      '#795548',
      '#607d8b',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ...palette.map((hex) => GestureDetector(
              onTap: () {
                setState(() => selectedElement![key] = hex);
                hexCtrl.text = hex;
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _parseColor(hex),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey, width: 2),
                ),
              ),
            )),
      ],
    );
  }

  void _openColorPopup(String label, String key) {
    final hexCtrl = TextEditingController(
        text: selectedElement?[key]?.toString() ?? '#000000');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _colorSwatches(key, hexCtrl),
              const SizedBox(height: 10),
              TextField(
                controller: hexCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Hex color',
                  labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  final v = val.trim();
                  if (RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(v)) {
                    setState(() =>
                        selectedElement![key] = v.startsWith('#') ? v : '#$v');
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Close', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  List<String> _availableFontFamilies() {
    final customNames = customFonts.keys.toList()..sort();
    return <String>{
      ..._builtInFontFamilies.where(
          (font) => !disabledFontFamilies.contains(font)),
      ...customNames.where((font) => !disabledFontFamilies.contains(font)),
    }.toList();
  }

  void _openFontPopup() {
    final availableFonts = _availableFontFamilies();
    if (availableFonts.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Font family',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        children: [
          ...availableFonts.map((font) {
            final isCustom = customFonts.containsKey(font);
            return SimpleDialogOption(
              onPressed: () {
                setState(() => selectedElement!['font_family'] = font);
                Navigator.pop(dialogContext);
              },
              child: Row(
                children: [
                  if (isCustom)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.font_download,
                          color: Colors.amberAccent, size: 16),
                    ),
                  Expanded(
                    child: Text(font,
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: font,
                            fontSize: 14)),
                  ),
                  if (selectedElement?['font_family'] == font)
                    const Icon(Icons.check,
                        color: Colors.lightGreenAccent, size: 17),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _applyFontToNestedValues(dynamic value, String fontFamily) {
    if (value is Map) {
      if (value.containsKey('font_family')) {
        value['font_family'] = fontFamily;
      }
      for (final nested in value.values) {
        _applyFontToNestedValues(nested, fontFamily);
      }
    } else if (value is List) {
      for (final nested in value) {
        _applyFontToNestedValues(nested, fontFamily);
      }
    }
  }

  void _openFontSettings() {
    final allFonts = <String>{
      ..._builtInFontFamilies,
      ...(customFonts.keys.toList()..sort()),
    }.toList();
    final initialAvailable = _availableFontFamilies();
    if (initialAvailable.isNotEmpty &&
        !initialAvailable.contains(defaultFontFamily)) {
      defaultFontFamily = initialAvailable.first;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Row(
            children: [
              Icon(Icons.text_fields, color: Colors.amberAccent),
              SizedBox(width: 8),
              Text('Fonts & typography',
                  style: TextStyle(color: Colors.white, fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 420,
            height: 410,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Default font for new elements',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _availableFontFamilies().contains(defaultFontFamily)
                      ? defaultFontFamily
                      : _availableFontFamilies().first,
                  dropdownColor: const Color(0xFF303030),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    isDense: true,
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.amberAccent)),
                  ),
                  items: _availableFontFamilies()
                      .map((font) => DropdownMenuItem<String>(
                          value: font,
                          child: Text(font, style: TextStyle(fontFamily: font))))
                      .toList(),
                  onChanged: (font) {
                    if (font == null) return;
                    setState(() => defaultFontFamily = font);
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 12),
                const Text('Available fonts',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView(
                    children: allFonts.map((font) {
                      final enabled = !disabledFontFamilies.contains(font);
                      final isDefault = defaultFontFamily == font;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D2D2D),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                value: font,
                                groupValue: defaultFontFamily,
                                onChanged: enabled
                                    ? (value) {
                                        if (value == null) return;
                                        setState(
                                            () => defaultFontFamily = value);
                                        setDialogState(() {});
                                      }
                                    : null,
                                title: Text(font,
                                    style: TextStyle(
                                        color: enabled
                                            ? Colors.white
                                            : Colors.white38,
                                        fontFamily: font,
                                        fontSize: 13)),
                                subtitle: isDefault
                                    ? const Text('Project default',
                                        style: TextStyle(
                                            color: Colors.amberAccent,
                                            fontSize: 10))
                                    : null,
                                activeColor: Colors.amberAccent,
                              ),
                            ),
                            Switch(
                              value: enabled,
                              activeColor: Colors.amberAccent,
                              onChanged: (turnOn) {
                                setState(() {
                                  if (turnOn) {
                                    disabledFontFamilies.remove(font);
                                  } else {
                                    if (_availableFontFamilies().length <= 1) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Keep at least one font enabled.')));
                                      return;
                                    }
                                    disabledFontFamilies.add(font);
                                    if (defaultFontFamily == font) {
                                      defaultFontFamily =
                                          _availableFontFamilies().first;
                                    }
                                  }
                                });
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  for (final element in elements) {
                    _applyFontToNestedValues(element, defaultFontFamily);
                  }
                });
                setDialogState(() {});
              },
              icon: const Icon(Icons.done_all, size: 17),
              label: const Text('Apply to all elements'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // YouTube Widget Integration: accepts any standard YouTube link shape
  // (watch?v=, youtu.be/, /shorts/, /embed/), extracts the video ID,
  // fills in the standard public thumbnail URL immediately, and — best
  // effort, no API key required — fetches the real title via YouTube's
  // public oEmbed endpoint. Manual title/thumbnail overrides in the
  // properties panel always win over whatever was auto-fetched.
  String? _extractYoutubeId(String url) {
    final patterns = [
      RegExp(r'(?:v=|/embed/|/shorts/|youtu\.be/)([A-Za-z0-9_-]{11})'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  Future<void> _applyYoutubeUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    final id = _extractYoutubeId(url);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("That doesn't look like a YouTube link.")));
      return;
    }
    setState(() {
      selectedElement!['video_url'] = url;
      selectedElement!['video_id'] = id;
      selectedElement!['thumb_src'] =
          'https://img.youtube.com/vi/$id/hqdefault.jpg';
    });
    // Best-effort title fetch; the widget already works with just the
    // thumbnail if this fails or the device is offline.
    try {
      final resp = await http.get(Uri.parse(
          'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map;
        final fetchedTitle = data['title']?.toString();
        if (fetchedTitle != null &&
            fetchedTitle.isNotEmpty &&
            mounted &&
            selectedElement != null &&
            selectedElement!['video_id'] == id) {
          setState(() => selectedElement!['title'] = fetchedTitle);
        }
      }
    } catch (_) {
      // Offline or blocked — the manual "Video title" field still lets
      // the user set one by hand.
    }
  }

  void _openYoutubeLinkPopup() {
    final ctrl = TextEditingController(
        text: selectedElement?['video_url']?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('YouTube link',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste a YouTube video link',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'https://youtube.com/watch?v=...',
                hintStyle: TextStyle(color: Colors.grey),
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
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              Navigator.pop(context);
              await _applyYoutubeUrl(ctrl.text);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openAlignPopup() {
    const options = {
      'left': 'Left',
      'center': 'Center',
      'right': 'Right',
    };
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Text align',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        children: options.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => selectedElement!['text_align'] = e.key);
              Navigator.pop(context);
            },
            child: Text(e.value, style: const TextStyle(color: Colors.white)),
          );
        }).toList(),
      ),
    );
  }

  // Text Widget Formatting Enhancements: Bold + Underline toggles and an
  // opacity slider (0-100%), all in a single popup for the Text widget.
  void _openTextFormatPopup() {
    bool bold = (selectedElement?['bold']?.toString() ?? 'false') == 'true';
    bool underline =
        (selectedElement?['underline']?.toString() ?? 'false') == 'true';
    double opacity = double.tryParse(
            (selectedElement?['opacity']?.toString() ?? '100')
                .replaceAll('%', '')) ??
        100;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Text style',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: Colors.blueAccent,
                    title: const Text('Bold',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: bold,
                    onChanged: (v) => setDialogState(() => bold = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: Colors.blueAccent,
                    title: const Text('Underline',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: underline,
                    onChanged: (v) => setDialogState(() => underline = v),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Opacity: ${opacity.round()}%',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  Slider(
                    value: opacity,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: Colors.blueAccent,
                    label: '${opacity.round()}%',
                    onChanged: (v) => setDialogState(() => opacity = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() {
                    selectedElement!['bold'] = bold.toString();
                    selectedElement!['underline'] = underline.toString();
                    selectedElement!['opacity'] = opacity.round().toString();
                  });
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  void _openHoverPopup() {
    final hoverCtrl =
        TextEditingController(text: selectedElement?['hover_css'] ?? '');
    final activeCtrl =
        TextEditingController(text: selectedElement?['active_css'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Hover & Active CSS',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _jsField('Hover CSS (on hover)', hoverCtrl),
              _jsField('Active CSS (on click / active)', activeCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() {
                selectedElement!['hover_css'] = hoverCtrl.text;
                selectedElement!['active_css'] = activeCtrl.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Manage the header block's navigation buttons: add / rename / remove /
  // point each button at another block's ID so tapping it scrolls there.
  void _openNavItemsPopup() {
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        ((selectedElement?['nav_items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Navigation buttons',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue:
                                        items[i]['label']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Button label',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['label'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['target']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Target section ID',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['target'] = v,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () =>
                                  setDialogState(() => items.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() =>
                            items.add({'label': 'New Button', 'target': ''})),
                        icon: const Icon(Icons.add,
                            color: Colors.lightBlueAccent),
                        label: const Text('Add button',
                            style: TextStyle(color: Colors.lightBlueAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() => selectedElement!['nav_items'] = items);
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // Manage the Services block's cards: title + description, unlimited count.
  void _openServicesPopup() {
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        ((selectedElement?['services'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Service cards',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue:
                                        items[i]['title']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Service title',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['title'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['description']?.toString() ??
                                            '',
                                    maxLines: 2,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Short description',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) =>
                                        items[i]['description'] = v,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () =>
                                  setDialogState(() => items.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() => items
                            .add({'title': 'New Service', 'description': ''})),
                        icon: const Icon(Icons.add,
                            color: Colors.lightBlueAccent),
                        label: const Text('Add service',
                            style: TextStyle(color: Colors.lightBlueAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() => selectedElement!['services'] = items);
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // Manage the Portfolio block's project cards: title + description + link.
  void _openProjectsPopup() {
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        ((selectedElement?['projects'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Projects',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue:
                                        items[i]['title']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Project title',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['title'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['description']?.toString() ??
                                            '',
                                    maxLines: 2,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Short description',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) =>
                                        items[i]['description'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['url']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Link URL',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['url'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['link_text']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Link text (e.g. "Click here to view the project")',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['link_text'] = v,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () =>
                                  setDialogState(() => items.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() => items.add({
                              'title': 'New Project',
                              'description': '',
                              'url': 'https://',
                              'link_text': 'Click here to view the project'
                            })),
                        icon: const Icon(Icons.add,
                            color: Colors.lightBlueAccent),
                        label: const Text('Add project',
                            style: TextStyle(color: Colors.lightBlueAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() => selectedElement!['projects'] = items);
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // Manage the Testimonials block's cards: photo + name + feedback.
  void _openTestimonialsPopup() {
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        ((selectedElement?['testimonials'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          Future<void> pickPhoto(int i) async {
            try {
              final picker = ImagePicker();
              final XFile? image =
                  await picker.pickImage(source: ImageSource.gallery);
              if (image == null) return;
              final bytes = await image.readAsBytes();
              final ext = image.name.split('.').last.toLowerCase();
              final mime = ext == 'jpg' || ext == 'jpeg'
                  ? 'image/jpeg'
                  : ext == 'webp'
                      ? 'image/webp'
                      : 'image/png';
              setDialogState(() {
                items[i]['photo'] = 'data:$mime;base64,${base64Encode(bytes)}';
              });
            } catch (_) {}
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Testimonials',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => pickPhoto(i),
                              child: ClipOval(
                                child: (items[i]['photo']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false)
                                    ? _smallImage(
                                        items[i]['photo'].toString(), 40)
                                    : Container(
                                        width: 40,
                                        height: 40,
                                        color: const Color(0xFF333333),
                                        child: const Icon(Icons.add_a_photo,
                                            color: Colors.grey, size: 16),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue:
                                        items[i]['name']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Customer name',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['name'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['photo']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                    decoration: const InputDecoration(
                                      labelText: 'Photo URL (or tap avatar)',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['photo'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['feedback']?.toString() ?? '',
                                    maxLines: 2,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Feedback text',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['feedback'] = v,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () =>
                                  setDialogState(() => items.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() => items.add({
                              'name': 'New Customer',
                              'photo': '',
                              'feedback': ''
                            })),
                        icon: const Icon(Icons.add,
                            color: Colors.lightBlueAccent),
                        label: const Text('Add testimonial',
                            style: TextStyle(color: Colors.lightBlueAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() => selectedElement!['testimonials'] = items);
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // Manage the Store block's products: image + name + price + description +
  // custom order button (text + URL).
  void _openProductsPopup() {
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        ((selectedElement?['products'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          Future<void> pickImage(int i) async {
            try {
              final picker = ImagePicker();
              final XFile? image =
                  await picker.pickImage(source: ImageSource.gallery);
              if (image == null) return;
              final bytes = await image.readAsBytes();
              final ext = image.name.split('.').last.toLowerCase();
              final mime = ext == 'jpg' || ext == 'jpeg'
                  ? 'image/jpeg'
                  : ext == 'webp'
                      ? 'image/webp'
                      : 'image/png';
              setDialogState(() {
                items[i]['image'] = 'data:$mime;base64,${base64Encode(bytes)}';
              });
            } catch (_) {}
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Products',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => pickImage(i),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: (items[i]['image']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false)
                                    ? _smallImage(
                                        items[i]['image'].toString(), 48)
                                    : Container(
                                        width: 48,
                                        height: 48,
                                        color: const Color(0xFF333333),
                                        child: const Icon(Icons.add_a_photo,
                                            color: Colors.grey, size: 18),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue:
                                        items[i]['name']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Product name',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['name'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['price']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Price',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['price'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['description']?.toString() ??
                                            '',
                                    maxLines: 2,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Short description',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) =>
                                        items[i]['description'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['button_text']?.toString() ??
                                            'Order Now',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Action button text',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) =>
                                        items[i]['button_text'] = v,
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['button_url']?.toString() ??
                                            '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Action button URL',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) =>
                                        items[i]['button_url'] = v,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: items[i]['bg_color']
                                                  ?.toString() ??
                                              '',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13),
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Card background (hex, optional)',
                                            hintText: '#f7f7f7',
                                            hintStyle: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11),
                                            labelStyle: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11),
                                            isDense: true,
                                          ),
                                          onChanged: (v) {
                                            final val = v.trim();
                                            setDialogState(() =>
                                                items[i]['bg_color'] = val);
                                          },
                                        ),
                                      ),
                                      if ((items[i]['bg_color']
                                                  ?.toString()
                                                  .trim()
                                                  .isNotEmpty ??
                                              false) &&
                                          RegExp(r'^#?[0-9a-fA-F]{6}$')
                                              .hasMatch(items[i]['bg_color']
                                                  .toString()
                                                  .trim()))
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 6),
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: _parseColor(items[i]
                                                      ['bg_color']
                                                  .toString()
                                                  .trim()),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.grey, width: 1),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () =>
                                  setDialogState(() => items.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() => items.add({
                              'name': 'New Product',
                              'price': '\$0.00',
                              'description': '',
                              'image': '',
                              'bg_color': '',
                              'button_text': 'Order Now',
                              'button_url': 'https://'
                            })),
                        icon: const Icon(Icons.add,
                            color: Colors.lightBlueAccent),
                        label: const Text('Add product',
                            style: TextStyle(color: Colors.lightBlueAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() => selectedElement!['products'] = items);
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // Manage the Custom Buttons block's buttons: text, colors, size, border
  // radius, font, and a link-type switch (internal section vs external URL).
  void _openCustomButtonsPopup() {
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        ((selectedElement?['buttons'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Custom buttons',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade800),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        items[i]['text']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Button text',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['text'] = v,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle,
                                      color: Colors.redAccent, size: 20),
                                  onPressed: () =>
                                      setDialogState(() => items.removeAt(i)),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        items[i]['bg_color']?.toString() ??
                                            '#1565c0',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Button color (hex)',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['bg_color'] = v,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        items[i]['text_color']?.toString() ??
                                            '#ffffff',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Text color (hex)',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) =>
                                        items[i]['text_color'] = v,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        items[i]['font_size']?.toString() ??
                                            '14px',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Font size',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['font_size'] = v,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        items[i]['border_radius']?.toString() ??
                                            '8px',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Border radius',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) =>
                                        items[i]['border_radius'] = v,
                                  ),
                                ),
                              ],
                            ),
                            TextFormField(
                              initialValue:
                                  items[i]['font_family']?.toString() ??
                                      'Arial',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Font family',
                                labelStyle:
                                    TextStyle(color: Colors.grey, fontSize: 11),
                                isDense: true,
                              ),
                              onChanged: (v) => items[i]['font_family'] = v,
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('On click, go to:',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11)),
                            ),
                            // Fixing Button Options Overflow: Wrap lets
                            // these two chips sit side by side when there's
                            // room and drop to a second line instead of
                            // overflowing when there isn't (narrow dialog /
                            // small screen), with no functional change.
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ChoiceChip(
                                  label: const Text('Section on this page'),
                                  labelStyle: const TextStyle(fontSize: 11),
                                  selected:
                                      (items[i]['link_type'] ?? 'section') ==
                                          'section',
                                  onSelected: (_) => setDialogState(
                                      () => items[i]['link_type'] = 'section'),
                                ),
                                ChoiceChip(
                                  label: const Text('External URL'),
                                  labelStyle: const TextStyle(fontSize: 11),
                                  selected:
                                      (items[i]['link_type'] ?? 'section') ==
                                          'url',
                                  onSelected: (_) => setDialogState(
                                      () => items[i]['link_type'] = 'url'),
                                ),
                              ],
                            ),
                            if ((items[i]['link_type'] ?? 'section') == 'url')
                              TextFormField(
                                initialValue:
                                    items[i]['url']?.toString() ?? 'https://',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  labelText: 'Destination URL',
                                  labelStyle: TextStyle(
                                      color: Colors.grey, fontSize: 11),
                                  isDense: true,
                                ),
                                onChanged: (v) => items[i]['url'] = v,
                              )
                            else
                              TextFormField(
                                initialValue:
                                    items[i]['target']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  labelText: 'Target section ID',
                                  labelStyle: TextStyle(
                                      color: Colors.grey, fontSize: 11),
                                  isDense: true,
                                ),
                                onChanged: (v) => items[i]['target'] = v,
                              ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() => items.add({
                              'text': 'New Button',
                              'bg_color': '#1565c0',
                              'text_color': '#ffffff',
                              'font_size': '14px',
                              'border_radius': '8px',
                              'font_family': defaultFontFamily,
                              'link_type': 'section',
                              'target': '',
                              'url': 'https://',
                            })),
                        icon: const Icon(Icons.add,
                            color: Colors.lightBlueAccent),
                        label: const Text('Add button',
                            style: TextStyle(color: Colors.lightBlueAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() => selectedElement!['buttons'] = items);
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // Manage the Social Media Bar's icons: pick platforms and set each URL.
  void _openSocialIconsPopup() {
    const availablePlatforms = [
      'facebook',
      'whatsapp',
      'telegram',
      'x',
      'instagram',
      'github',
    ];
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
        ((selectedElement?['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Text('Social icons',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: availablePlatforms.contains(
                                            items[i]['platform']?.toString())
                                        ? items[i]['platform'].toString()
                                        : availablePlatforms.first,
                                    dropdownColor: const Color(0xFF222222),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Platform',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    items: availablePlatforms
                                        .map((p) => DropdownMenuItem(
                                            value: p, child: Text(p)))
                                        .toList(),
                                    onChanged: (v) => setDialogState(
                                        () => items[i]['platform'] = v),
                                  ),
                                  TextFormField(
                                    initialValue:
                                        items[i]['url']?.toString() ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: const InputDecoration(
                                      labelText: 'Profile / page URL',
                                      labelStyle: TextStyle(
                                          color: Colors.grey, fontSize: 11),
                                      isDense: true,
                                    ),
                                    onChanged: (v) => items[i]['url'] = v,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () =>
                                  setDialogState(() => items.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() => items.add({
                              'platform': 'facebook',
                              'url': '',
                            })),
                        icon: const Icon(Icons.add,
                            color: Colors.lightBlueAccent),
                        label: const Text('Add icon',
                            style: TextStyle(color: Colors.lightBlueAccent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent),
                onPressed: () {
                  setState(() => selectedElement!['items'] = items);
                  Navigator.pop(context);
                },
                child:
                    const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  // Toggle between full-color brand icons and monochrome icons for the
  // Social Media Bar.
  void _openSocialStylePopup() {
    const options = {
      'color': 'Full-color brand icons',
      'mono': 'Monochrome (black/white)'
    };
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Icon style',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        children: options.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => selectedElement!['icon_style'] = e.key);
              Navigator.pop(context);
            },
            child: Text(e.value, style: const TextStyle(color: Colors.white)),
          );
        }).toList(),
      ),
    );
  }

  Widget _paletteSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(title,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  //  NEW ELEMENT / BLOCK FACTORY
  // ------------------------------------------------------------
  Map<String, dynamic> _createNewElement(String type) {
    final int ts = DateTime.now().millisecondsSinceEpoch;

    switch (type) {
      case 'header_block':
        return {
          'type': type,
          'id': 'header_$ts',
          'bg_color': '#0277BD',
          'height': '70px',
          'logo_src': '',
          'header_text': 'My Website',
          'nav_color': '#ffffff',
          'nav_font_size': '14px',
          'font_family': defaultFontFamily,
          'nav_items': <Map<String, dynamic>>[
            {'label': 'Home', 'target': 'home'},
            {'label': 'About', 'target': 'about'},
          ],
        };
      case 'title_desc_block':
        return {
          'type': type,
          'id': 'section_$ts',
          'title': 'Home',
          'description': 'Write a short description for this section here.',
          'bg_color': '#ffffff',
          'title_color': '#000000',
          'desc_color': '#444444',
          'title_font_size': '26px',
          'desc_font_size': '15px',
          'font_family': defaultFontFamily,
          'text_align': 'center',
        };
      case 'skills_block':
        return {
          'type': type,
          'id': 'skills_$ts',
          'image_src': '',
          'image_radius': '16px',
          'bg_color': '#f7f7f7',
          'description': 'Describe your skills or profile here.',
          'desc_color': '#333333',
          'desc_font_size': '15px',
          'font_family': defaultFontFamily,
        };
      case 'footer_block':
        return {
          'type': type,
          'id': 'footer_$ts',
          'text': '© 2026 My Website. All rights reserved.',
          'bg_color': '#161616',
          'color': '#ffffff',
          'font_size': '12px',
          'font_family': defaultFontFamily,
        };
      case 'services_block':
        return {
          'type': type,
          'id': 'services_$ts',
          'bg_color': '#ffffff',
          'card_bg_color': '#f7f7f7',
          'title_color': '#000000',
          'desc_color': '#555555',
          'title_font_size': '18px',
          'desc_font_size': '13px',
          'font_family': defaultFontFamily,
          'autoplay_seconds': '3',
          'services': <Map<String, dynamic>>[
            {
              'title': 'Service One',
              'description': 'A short description of this service.'
            },
            {
              'title': 'Service Two',
              'description': 'A short description of this service.'
            },
            {
              'title': 'Service Three',
              'description': 'A short description of this service.'
            },
          ],
        };
      case 'portfolio_block':
        return {
          'type': type,
          'id': 'portfolio_$ts',
          'bg_color': '#ffffff',
          'card_bg_color': '#f7f7f7',
          'title_color': '#000000',
          'desc_color': '#555555',
          'title_font_size': '18px',
          'desc_font_size': '13px',
          'font_family': defaultFontFamily,
          'projects': <Map<String, dynamic>>[
            {
              'title': 'Project One',
              'description': 'A short project description.',
              'url': 'https://'
            },
            {
              'title': 'Project Two',
              'description': 'A short project description.',
              'url': 'https://'
            },
          ],
        };
      case 'testimonials_block':
        return {
          'type': type,
          'id': 'testimonials_$ts',
          'bg_color': '#f7f7f7',
          'name_color': '#000000',
          'text_color': '#555555',
          'name_font_size': '15px',
          'text_font_size': '13px',
          'font_family': defaultFontFamily,
          'section_height': '160px',
          'testimonials': <Map<String, dynamic>>[
            {
              'name': 'Jane Doe',
              'photo': '',
              'feedback': 'This service was fantastic!'
            },
            {
              'name': 'John Smith',
              'photo': '',
              'feedback': 'Highly recommend to everyone.'
            },
          ],
        };
      case 'contact_block':
        return {
          'type': type,
          'id': 'contact_$ts',
          'bg_color': '#ffffff',
          'heading_color': '#000000',
          'desc_color': '#555555',
          'heading_font_size': '24px',
          'desc_font_size': '14px',
          'font_family': defaultFontFamily,
          'heading': 'Get In Touch',
          'description': 'Leave your email and we will get back to you.',
          'button_text': 'Send Email',
          'button_color': '#1565c0',
          'button_text_color': '#ffffff',
          'owner_email': 'you@example.com',
        };
      case 'store_block':
        return {
          'type': type,
          'id': 'store_$ts',
          'bg_color': '#ffffff',
          'card_bg_color': '#f7f7f7',
          'title_color': '#000000',
          'price_color': '#e53935',
          'desc_color': '#555555',
          'button_color': '#1565c0',
          'font_family': defaultFontFamily,
          'products': <Map<String, dynamic>>[
            {
              'name': 'Product One',
              'price': '\$19.99',
              'description': 'A short product description.',
              'image': '',
              'bg_color': '',
              'button_text': 'Order Now',
              'button_url': 'https://',
            },
          ],
        };
      case 'youtube_widget':
        return {
          'type': type,
          'id': 'youtube_$ts',
          // The clear visual "accepts a video link" cue lives in the
          // palette chip icon (Icons.smart_display) and, once dropped, in
          // the placeholder play-button/arrow shown until a link is set.
          'video_url': '',
          'video_id': '',
          'title': '',
          'thumb_src': '',
          'border_radius': '10px',
        };
      case 'buttons_block':
        return {
          'type': type,
          'id': 'buttons_$ts',
          'bg_color': '#ffffff',
          'buttons': <Map<String, dynamic>>[
            {
              'text': 'Click Me',
              'bg_color': '#1565c0',
              'text_color': '#ffffff',
              'font_size': '14px',
              'border_radius': '8px',
              'font_family': defaultFontFamily,
              'link_type': 'section',
              'target': '',
              'url': 'https://',
            },
          ],
        };
      case 'social_block':
        return {
          'type': type,
          'id': 'social_$ts',
          'bg_color': '#ffffff',
          'icon_style': 'color',
          'icon_size': '32px',
          'items': <Map<String, dynamic>>[
            {'platform': 'facebook', 'url': ''},
            {'platform': 'instagram', 'url': ''},
          ],
        };
    }

    // Individual widgets
    final Map<String, dynamic> base = {
      'type': type,
      'id': '${type}_$ts',
      'text': type == 'button'
          ? 'Button'
          : type == 'link'
              ? 'Link'
              : type == 'text'
                  ? 'Text here'
                  : '',
      'hint': 'Type here...',
      'hint_color': '#999999',
      'url': 'https://',
      'src': '',
      'height': type == 'image' ? '80px' : '40px',
      'container_bg_color': 'transparent',
      'padding': '4px',
      'margin': '2px',
      'color': type == 'link' ? '#1565c0' : '#000000',
      'bg_color': type == 'button' ? '#e53935' : '#ffffff',
      'font_size': '14px',
      'font_family': defaultFontFamily,
      'text_align': 'center',
      'border_radius': '4px',
      'border_color': type == 'button' ? '#e53935' : '#cccccc',
      'hover_css': '',
      'active_css': '',
      'click_js': '',
      'js_code': '',
    };

    if (type == 'button') base['color'] = '#ffffff';
    return base;
  }

  Widget _buildPaletteItem(
      String label, String type, IconData icon, Color color) {
    return Draggable<Object>(
      data: type,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(4)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _paletteChip(label, icon, color),
      ),
      child: _paletteChip(label, icon, color),
    );
  }

  // Direct-action sidebar entry (font uploader, page background) — looks
  // like a palette chip but is a plain tap target, not a Draggable, since
  // it triggers an action immediately instead of being dropped on canvas.
  Widget _buildActionPaletteItem(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: _paletteChip(label, icon, color),
    );
  }

  Widget _buildCustomComponentPaletteItem(
      Map<String, dynamic> component) {
    final String label = (component['name'] ?? 'Custom').toString();
    final payload = {
      'kind': 'custom_component',
      'component': Map<String, dynamic>.from(component),
    };
    return Draggable<Object>(
      data: payload,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.deepPurpleAccent,
              borderRadius: BorderRadius.circular(4)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.code, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
          opacity: 0.3,
          child: _paletteChip(label, Icons.code, Colors.deepPurpleAccent)),
      child: _paletteChip(label, Icons.code, Colors.deepPurpleAccent),
    );
  }

  String _nextCustomId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${++_customElementCounter}';

  Map<String, dynamic> _createCustomElement(
      Map<String, dynamic> component) {
    return {
      'type': 'custom',
      'id': _nextCustomId('custom'),
      'custom_id': component['id']?.toString() ?? '',
      'custom_name': component['name']?.toString() ?? 'Custom component',
      // Keep a snapshot on each placed instance. Updating or deleting the
      // library entry will not silently change an existing project.
      'custom_html': component['html']?.toString() ?? '',
      'custom_css': component['css']?.toString() ?? '',
      'custom_js': component['js']?.toString() ?? '',
      'font_family': defaultFontFamily,
    };
  }

  Map<String, dynamic>? _elementFromPaletteData(Object data) {
    if (data is String) return _createNewElement(data);
    if (data is Map && data['kind'] == 'custom_component') {
      final rawComponent = data['component'];
      if (rawComponent is Map) {
        final component = Map<String, dynamic>.from(rawComponent.map(
            (key, value) => MapEntry(key.toString(), value)));
        return _createCustomElement(component);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _showCustomComponentEditor(
      {Map<String, dynamic>? component}) async {
    final nameController =
        TextEditingController(text: component?['name']?.toString() ?? '');
    final htmlController =
        TextEditingController(text: component?['html']?.toString() ?? '');
    final cssController =
        TextEditingController(text: component?['css']?.toString() ?? '');
    final jsController =
        TextEditingController(text: component?['js']?.toString() ?? '');
    String? validationMessage;

    Widget codeField(String label, TextEditingController controller,
        {String? helper}) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            if (helper != null) ...[
              const SizedBox(height: 3),
              Text(helper,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
            const SizedBox(height: 5),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35),
              decoration: InputDecoration(
                hintText: '$label code',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF171717),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Colors.white24)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide:
                        const BorderSide(color: Colors.deepPurpleAccent)),
              ),
            ),
          ],
        ),
      );
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: Text(component == null ? 'Create custom component' : 'Edit custom component',
              style: const TextStyle(color: Colors.white, fontSize: 17)),
          content: SizedBox(
            width: 620,
            height: 570,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Saved name',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. Pricing card',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF171717),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7)),
                    ),
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(validationMessage!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
                  ],
                  codeField('HTML', htmlController,
                      helper: 'Markup only. It is placed inside a unique <div> on the canvas and export.'),
                  codeField('CSS', cssController,
                      helper:
                          'Use {{ROOT}} to target this instance, e.g. {{ROOT}} .card { ... }.'),
                  codeField('JS', jsController,
                      helper:
                          'Runs only in the generated site. Use {{ROOT}} for this component’s root element.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(
                      () => validationMessage = 'Enter a name for this component.');
                  return;
                }
                if (htmlController.text.trim().isEmpty) {
                  setDialogState(() => validationMessage =
                      'Add some HTML markup before saving.');
                  return;
                }
                final duplicate = customComponents.any((saved) =>
                    saved['id']?.toString() != component?['id']?.toString() &&
                    saved['name']
                            ?.toString()
                            .trim()
                            .toLowerCase() ==
                        name.toLowerCase());
                if (duplicate) {
                  setDialogState(() => validationMessage =
                      'A component with that name already exists.');
                  return;
                }
                Navigator.pop(dialogContext, {
                  'id': component?['id']?.toString() ??
                      _nextCustomId('component'),
                  'name': name,
                  'html': htmlController.text,
                  'css': cssController.text,
                  'js': jsController.text,
                  'updated_at': DateTime.now().toIso8601String(),
                });
              },
              icon: const Icon(Icons.save_outlined, size: 17),
              label: const Text('Save component'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    htmlController.dispose();
    cssController.dispose();
    jsController.dispose();
    return result;
  }

  Future<void> _showCustomComponentDetails(
      Map<String, dynamic> component) {
    Widget codeBlock(String label, String code) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF171717),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                code.isEmpty ? '(empty)' : code,
                style: const TextStyle(
                    color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text((component['name'] ?? 'Custom component').toString(),
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: SizedBox(
          width: 620,
          height: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                codeBlock('HTML', (component['html'] ?? '').toString()),
                codeBlock('CSS', (component['css'] ?? '').toString()),
                codeBlock('JS', (component['js'] ?? '').toString()),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Future<void> _editSelectedCustomComponent() async {
    final element = selectedElement;
    if (element == null) return;
    final componentId = (element['custom_id']?.toString().isNotEmpty ?? false)
        ? element['custom_id'].toString()
        : _nextCustomId('component');
    final edited = await _showCustomComponentEditor(
      component: {
        'id': componentId,
        'name': element['custom_name'] ?? 'Custom component',
        'html': element['custom_html'] ?? '',
        'css': element['custom_css'] ?? '',
        'js': element['custom_js'] ?? '',
      },
    );
    if (edited == null || !mounted) return;

    setState(() {
      element['custom_id'] = edited['id'];
      element['custom_name'] = edited['name'];
      element['custom_html'] = edited['html'];
      element['custom_css'] = edited['css'];
      element['custom_js'] = edited['js'];
    });

    final updated = List<Map<String, dynamic>>.from(customComponents);
    final index =
        updated.indexWhere((saved) => saved['id'] == edited['id']);
    if (index >= 0) {
      updated[index] = edited;
    } else {
      updated.add(edited);
    }
    // The placed copy updates immediately; saving the library copy makes
    // this edited version available to drag into any other project.
    await _persistCustomComponents(updated);
  }

  Future<void> _openCustomComponentsDialog() async {
    final dialogAction = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ordered = List<Map<String, dynamic>>.from(customComponents)
            ..sort((a, b) => (a['name'] ?? '')
                .toString()
                .toLowerCase()
                .compareTo((b['name'] ?? '').toString().toLowerCase()));
          return AlertDialog(
            backgroundColor: const Color(0xFF222222),
            title: const Row(
              children: [
                Icon(Icons.code, color: Colors.deepPurpleAccent),
                SizedBox(width: 8),
                Text('Custom components',
                    style: TextStyle(color: Colors.white, fontSize: 17)),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(
                          dialogContext, <String, dynamic>{'action': 'create'}),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('Create custom component',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ordered.isEmpty
                        ? const Center(
                            child: Text(
                              'No saved components yet. Create one above; it will be available in every project on this device.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white54, height: 1.4),
                            ),
                          )
                        : ListView.separated(
                            itemCount: ordered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.white12, height: 1),
                            itemBuilder: (context, index) {
                              final component = ordered[index];
                              final name =
                                  (component['name'] ?? 'Custom').toString();
                              final snippet = _customHtmlPreviewText(
                                  (component['html'] ?? '').toString());
                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                leading: const Icon(Icons.code,
                                    color: Colors.deepPurpleAccent),
                                title: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  snippet.isEmpty ? 'HTML / CSS / JS' : snippet,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Component actions',
                                  color: const Color(0xFF303030),
                                  icon: const Icon(Icons.more_vert,
                                      color: Colors.white70),
                                  onSelected: (action) async {
                                    if (action == 'view') {
                                      await _showCustomComponentDetails(
                                          component);
                                    } else if (action == 'edit') {
                                      Navigator.pop<Map<String, dynamic>>(
                                          dialogContext, <String, dynamic>{
                                        'action': 'edit',
                                        'component':
                                            Map<String, dynamic>.from(component),
                                      });
                                    } else if (action == 'add') {
                                      final element =
                                          _createCustomElement(component);
                                      setState(() {
                                        elements.add(element);
                                        selectedElement = element;
                                      });
                                      Navigator.pop(dialogContext);
                                    } else if (action == 'delete') {
                                      final confirm = await showDialog<bool>(
                                        context: dialogContext,
                                        builder: (confirmContext) =>
                                            AlertDialog(
                                          backgroundColor:
                                              const Color(0xFF222222),
                                          title: const Text('Delete component?',
                                              style: TextStyle(
                                                  color: Colors.white)),
                                          content: Text(
                                              'Remove "$name" from the shared library? Components already placed in projects will stay unchanged.',
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(
                                                      confirmContext, false),
                                              child: const Text('Cancel',
                                                  style: TextStyle(
                                                      color: Colors.white70)),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(
                                                      confirmContext, true),
                                              child: const Text('Delete',
                                                  style: TextStyle(
                                                      color: Colors.redAccent)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm != true) return;
                                      final updated = List<
                                              Map<String, dynamic>>.from(
                                          customComponents)
                                        ..removeWhere((saved) =>
                                            saved['id'] == component['id']);
                                      if (await _persistCustomComponents(
                                              updated) &&
                                          dialogContext.mounted) {
                                        setDialogState(() {});
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'view',
                                        child: Text('View code')),
                                    PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit')),
                                    PopupMenuItem(
                                        value: 'add',
                                        child: Text('Add to canvas')),
                                    PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete',
                                            style: TextStyle(
                                                color: Colors.redAccent))),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child:
                    const Text('Close', style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        },
      ),
    );

    if (!mounted || dialogAction == null) return;
    final action = dialogAction['action']?.toString();
    if (action != 'create' && action != 'edit') return;

    // Let the library route finish its closing transition before presenting
    // the code editor; stacked edit/create dialogs caused a framework error
    // while their inherited widget dependents were being deactivated.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;

    final rawComponent = dialogAction['component'];
    final component = rawComponent is Map
        ? Map<String, dynamic>.from(rawComponent.map(
            (key, value) => MapEntry(key.toString(), value)))
        : null;
    final edited = await _showCustomComponentEditor(
        component: action == 'edit' ? component : null);

    // Avoid refreshing the page or opening another dialog during the editor's
    // reverse transition.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    if (edited != null) {
      final updated = List<Map<String, dynamic>>.from(customComponents);
      final savedIndex =
          updated.indexWhere((saved) => saved['id'] == edited['id']);
      if (savedIndex >= 0) {
        updated[savedIndex] = edited;
      } else {
        updated.add(edited);
      }
      await _persistCustomComponents(updated);
    }

    if (mounted) await _openCustomComponentsDialog();
  }

  Widget _paletteChip(String label, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  //  CANVAS: flat, freely-reorderable list of blocks/widgets.
  //  Thin drop-slots sit before, between and after every element so a
  //  dragged item (new from the palette, or an existing one being moved)
  //  can be inserted at an exact position — this is how sections get
  //  reordered on the page.
  // ------------------------------------------------------------
  List<Widget> _buildInsertableChildren(List<Map<String, dynamic>> list) {
    final List<Widget> widgets = [];
    for (int i = 0; i < list.length; i++) {
      widgets.add(_dropSlot(list, i));
      final el = list[i];
      final String id = (el['id']?.toString() ?? '').trim();
      final Widget content = _buildElementWidget(el);
      // Give every identifiable block a stable key so the header's Menu
      // dropdown can scroll straight to it (see _openHeaderMenuDropdown).
      widgets.add(id.isEmpty
          ? content
          : KeyedSubtree(key: _keyForSection(id), child: content));
    }
    widgets.add(_dropSlot(list, list.length));
    return widgets;
  }

  Widget _dropSlot(List<Map<String, dynamic>> list, int insertIndex) {
    return DragTarget<Object>(
      onAcceptWithDetails: (details) {
        setState(() {
          final data = details.data;
          int idx = insertIndex;
          final paletteElement = _elementFromPaletteData(data);
          if (paletteElement != null) {
            idx = idx.clamp(0, list.length).toInt();
            list.insert(idx, paletteElement);
            selectedElement = paletteElement;
          } else if (data is Map<String, dynamic>) {
            final currentIndex = list.indexOf(data);
            if (currentIndex != -1) {
              // Reordering inside the list: remove locally so it isn't
              // duplicated, then re-insert at the (shifted) target slot.
              list.removeAt(currentIndex);
              if (currentIndex < idx) idx -= 1;
            }
            if (idx > list.length) idx = list.length;
            if (idx < 0) idx = 0;
            list.insert(idx, data);
          }
        });
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return Container(
          height: active ? 16 : 6,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: active
                ? Colors.blueAccent.withOpacity(0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      },
    );
  }

  // Tap to select; when selected, a small on-canvas delete button appears
  // on the element itself (in addition to the delete icon in the
  // properties panel). Long-press-drag reorders it among its siblings.
  Widget _buildElementWidget(Map<String, dynamic> el) {
    final bool isSelected = selectedElement == el;
    return LongPressDraggable<Object>(
      data: el,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(2),
          decoration:
              BoxDecoration(border: Border.all(color: Colors.blue, width: 2)),
          child: _buildElementContent(el),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: _buildElementContent(el)),
      child: GestureDetector(
        onTap: () => setState(() => selectedElement = el),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    width: isSelected ? 2 : 1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: _buildElementContent(el),
            ),
            // Delete button only appears once the element is tapped/selected
            // — no more permanent "X" buttons cluttering every element.
            if (isSelected)
              Positioned(
                top: -8,
                right: -8,
                child: GestureDetector(
                  onTap: () => _deleteElement(el),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black45, blurRadius: 3)
                      ],
                    ),
                    child:
                        const Icon(Icons.delete, size: 13, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildElementContent(Map<String, dynamic> el) {
    final String type = el['type'];

    if (type == 'header_block') return _buildHeaderBlockContent(el);
    if (type == 'title_desc_block') return _buildTitleDescBlockContent(el);
    if (type == 'skills_block') return _buildSkillsBlockContent(el);
    if (type == 'footer_block') return _buildFooterBlockContent(el);
    if (type == 'services_block') return _buildServicesBlockContent(el);
    if (type == 'portfolio_block') return _buildPortfolioBlockContent(el);
    if (type == 'testimonials_block') return _buildTestimonialsBlockContent(el);
    if (type == 'contact_block') return _buildContactBlockContent(el);
    if (type == 'store_block') return _buildStoreBlockContent(el);
    if (type == 'youtube_widget') return _buildYoutubeWidgetContent(el);
    if (type == 'buttons_block') return _buildButtonsBlockContent(el);
    if (type == 'social_block') return _buildSocialBlockContent(el);
    if (type == 'custom') return _customComponentPlaceholder(el);

    final TextStyle baseText = TextStyle(
      fontSize: _parseNum(el['font_size'], 14),
      color: _parseColor(el['color'] ?? '#000000'),
      fontFamily: el['font_family'] ?? 'Arial',
      height: 1.1,
    );

    final EdgeInsets padding =
        EdgeInsets.all(_parseNum(el['padding'], 4).toDouble());
    final EdgeInsets margin =
        EdgeInsets.all(_parseNum(el['margin'], 2).toDouble());

    Widget content;
    switch (type) {
      case 'text':
        final bool isBold = (el['bold']?.toString() ?? 'false') == 'true';
        final bool isUnderline =
            (el['underline']?.toString() ?? 'false') == 'true';
        final double opacityPct = double.tryParse(
                (el['opacity']?.toString() ?? '100').replaceAll('%', '')) ??
            100;
        content = Opacity(
          opacity: (opacityPct / 100).clamp(0, 1),
          child: Text(
            el['text'] ?? '',
            textAlign: _parseAlign(el['text_align']),
            style: baseText.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              decoration:
                  isUnderline ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
        );
        break;
      case 'link':
        content = Text(
          el['text'] ?? 'Link',
          textAlign: _parseAlign(el['text_align']),
          style: baseText.copyWith(decoration: TextDecoration.underline),
        );
        break;
      case 'button':
        content = Container(
          alignment: Alignment.center,
          child: Text(el['text'] ?? 'Button',
              style: baseText.copyWith(
                fontWeight: FontWeight.bold,
                color: _parseColor(el['color'] ?? '#ffffff'),
              )),
        );
        break;
      case 'edit_number':
        content = TextField(
          keyboardType: TextInputType.number,
          style: baseText,
          decoration: InputDecoration(
            hintText: el['hint'] ?? '',
            hintStyle: baseText.copyWith(
                color: _parseColor(el['hint_color'] ?? '#999999')),
            contentPadding: padding,
            isDense: true,
            enabledBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(_parseNum(el['border_radius'], 4)),
              borderSide: BorderSide(
                  color: _parseColor(el['border_color'] ?? '#cccccc')),
            ),
          ),
        );
        break;
      case 'edit_text':
        content = TextField(
          style: baseText,
          decoration: InputDecoration(
            hintText: el['hint'] ?? '',
            hintStyle: baseText.copyWith(
                color: _parseColor(el['hint_color'] ?? '#999999')),
            contentPadding: padding,
            isDense: true,
            enabledBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(_parseNum(el['border_radius'], 4)),
              borderSide: BorderSide(
                  color: _parseColor(el['border_color'] ?? '#cccccc')),
            ),
          ),
        );
        break;
      case 'image':
        content = _buildImageView(el);
        break;
      default:
        content = const SizedBox();
    }

    // The widget itself (its own background / border / radius) — matches
    // the button/link/field's own look, independent of the container.
    final decoration = BoxDecoration(
      color: _parseColor(el['bg_color'] ?? '#ffffff'),
      borderRadius: BorderRadius.circular(_parseNum(el['border_radius'], 4)),
      border: Border.all(
          color: _parseColor(el['border_color'] ?? '#cccccc'), width: 1),
    );

    // 'text' now gets its own background box too (matching the generated
    // HTML, which already applies background-color to every widget type),
    // so the editor canvas preview reflects the Background Color control.
    final Widget widgetBox = type == 'link'
        ? Padding(padding: padding, child: content)
        : Container(
            width: double.infinity,
            padding: padding,
            decoration: decoration,
            alignment: Alignment.center,
            child: content,
          );

    // The independent container div every widget now lives inside: it
    // owns height, background color, and alignment. Width is always
    // 100% — there is no width control any more.
    final String heightVal = (el['height'] ?? 'auto').toString().trim();
    final Color containerBg =
        _parseColor(el['container_bg_color'] ?? 'transparent');

    return Container(
      width: double.infinity,
      height: (heightVal.isEmpty || heightVal == 'auto')
          ? null
          : _parseNum(heightVal, 0),
      margin: margin,
      decoration: BoxDecoration(
        color: containerBg,
        image: _canvasBgImage(el, 'container_bg_image'),
      ),
      alignment: _parseAlignment(el['text_align']),
      child: widgetBox,
    );
  }

  // ---- Block content builders (editor canvas preview) ----

  // YouTube Widget Integration: live canvas preview — shows the fetched
  // (or manually overridden) thumbnail with a play-button overlay, or a
  // "paste a link" placeholder with an arrow icon before one is set.
  Widget _buildYoutubeWidgetContent(Map<String, dynamic> el) {
    final String videoUrl = (el['video_url'] ?? '').toString().trim();
    final String title = (el['title'] ?? '').toString().trim();
    final String thumb = (el['thumb_src'] ?? '').toString().trim();
    final double radius = _parseNum(el['border_radius'], 10);

    if (videoUrl.isEmpty) {
      return Container(
        width: double.infinity,
        height: 140,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.redAccent, width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_display, color: Colors.redAccent, size: 30),
            SizedBox(height: 4),
            Icon(Icons.arrow_downward, color: Colors.grey, size: 16),
            SizedBox(height: 2),
            Text('Paste a YouTube link',
                style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (thumb.isNotEmpty)
                    thumb.startsWith('data:')
                        ? Image.memory(
                            base64Decode(
                                thumb.substring(thumb.indexOf(',') + 1)),
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => const SizedBox())
                        : Image.network(thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => const SizedBox()),
                  Center(
                    child: Container(
                      width: 56,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 26),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _buildButtonsBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#ffffff');
    final List<Map<String, dynamic>> buttons =
        List<Map<String, dynamic>>.from((el['buttons'] as List?) ?? []);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: buttons.isEmpty
          ? const Text('Add buttons →',
              style: TextStyle(color: Colors.grey, fontSize: 12))
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: buttons.map((b) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    color: _parseColor(b['bg_color'] ?? '#1565c0'),
                    borderRadius:
                        BorderRadius.circular(_parseNum(b['border_radius'], 8)),
                  ),
                  child: Text((b['text'] ?? 'Button').toString(),
                      style: TextStyle(
                          color: _parseColor(b['text_color'] ?? '#ffffff'),
                          fontSize: _parseNum(b['font_size'], 14),
                          fontFamily: (b['font_family'] ?? 'Arial').toString(),
                          fontWeight: FontWeight.w600)),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildSocialBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#ffffff');
    final String iconStyle = (el['icon_style'] ?? 'color').toString();
    final double iconSize = _parseNum(el['icon_size'], 32);
    final List<Map<String, dynamic>> items =
        List<Map<String, dynamic>>.from((el['items'] as List?) ?? []);
    const Map<String, Color> brandColors = {
      'facebook': Color(0xFF1877F2),
      'whatsapp': Color(0xFF25D366),
      'telegram': Color(0xFF26A5E4),
      'x': Color(0xFF000000),
      'instagram': Color(0xFFE1306C),
      'github': Color(0xFF333333),
    };
    const Map<String, String> initials = {
      'facebook': 'f',
      'whatsapp': 'W',
      'telegram': 'T',
      'x': 'X',
      'instagram': 'IG',
      'github': 'GH',
    };

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: items.isEmpty
          ? const Text('Add social icons →',
              style: TextStyle(color: Colors.grey, fontSize: 12))
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: items.map((item) {
                final String platform = (item['platform'] ?? '').toString();
                final Color color = iconStyle == 'mono'
                    ? const Color(0xFF333333)
                    : (brandColors[platform] ?? Colors.grey);
                return Container(
                  width: iconSize,
                  height: iconSize,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Text(initials[platform] ?? '?',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: iconSize / 2.2,
                          fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
    );
  }

  // Dropdown Menu Functionality: shows the header's configured sections
  // (same list managed via "Manage menu sections") and scrolls the canvas
  // to whichever one is tapped, mirroring how the exported site's own
  // dropdown scrolls the real page.
  void _openHeaderMenuDropdown(Map<String, dynamic> el) {
    final List<Map<String, dynamic>> navItems =
        List<Map<String, dynamic>>.from((el['nav_items'] as List?) ?? []);
    if (navItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No menu sections yet — add some via "Manage menu sections".')));
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Menu',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        children: navItems.map((item) {
          final label = (item['label'] ?? '').toString();
          final target = _cleanId((item['target'] ?? '').toString());
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              _scrollToSection(target);
            },
            child: Text(label.isEmpty ? '(untitled)' : label,
                style: const TextStyle(color: Colors.white)),
          );
        }).toList(),
      ),
    );
  }

  void _scrollToSection(String targetId) {
    final key = _sectionKeys[targetId];
    if (key?.currentContext == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'No block with ID "$targetId" on the canvas yet — set one via that block\'s ID field.')));
      return;
    }
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildHeaderBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#0277BD');
    final double h = _parseNum(el['height'], 70);
    final Color navColor = _parseColor(el['nav_color'] ?? '#ffffff');
    final double navFontSize = _parseNum(el['nav_font_size'], 14);
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String headerText = (el['header_text'] ?? '').toString();
    final String logo = (el['logo_src']?.toString() ?? '').trim();

    // Header ("Navigation Bar") Section: image + descriptive text pinned
    // to the far left; a "Menu" label with a 3-line hamburger icon pinned
    // to the far right (tapping it, in the exported site, reveals the
    // section links — this canvas view is a static preview of that bar).
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: h),
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Wrapping the left side in Expanded (instead of nesting a plain
          // Row inside another Row) is what actually fixes the overflow:
          // a Flexible/ellipsis Text only gets a bounded width to shrink
          // into when its parent Row is itself properly constrained, and
          // Expanded is what supplies that bound here.
          Expanded(
            child: Row(
              children: [
                if (logo.isNotEmpty)
                  _smallImage(logo, 34)
                else
                  const SizedBox(width: 0, height: 34),
                if (headerText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(headerText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: navColor,
                            fontSize: navFontSize,
                            fontFamily: fontFamily,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Dropdown Menu Functionality: tapping "Menu" shows the same
          // section list the exported site's header will show, and
          // selecting one scrolls the canvas to that block.
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openHeaderMenuDropdown(el),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Menu',
                    style: TextStyle(
                        color: navColor,
                        fontSize: navFontSize,
                        fontFamily: fontFamily,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      3,
                      (_) => Container(
                            width: 20,
                            height: 2.5,
                            margin: const EdgeInsets.symmetric(vertical: 1.5),
                            color: navColor,
                          )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleDescBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#ffffff');
    final Color titleColor = _parseColor(el['title_color'] ?? '#000000');
    final Color descColor = _parseColor(el['desc_color'] ?? '#444444');
    final double titleSize = _parseNum(el['title_font_size'], 22);
    final double descSize = _parseNum(el['desc_font_size'], 14);
    final String fontFamily = el['font_family'] ?? 'Arial';
    // Title & Description Text Alignment control.
    final TextAlign textAlign = _parseAlign(el['text_align'] ?? 'center');
    final CrossAxisAlignment crossAlign =
        _crossAxisAlignFor(el['text_align'] ?? 'center');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: crossAlign,
        children: [
          Text(el['title'] ?? 'Title',
              textAlign: textAlign,
              style: TextStyle(
                  fontSize: titleSize,
                  color: titleColor,
                  fontFamily: fontFamily,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(el['description'] ?? '',
              textAlign: textAlign,
              style: TextStyle(
                  fontSize: descSize,
                  color: descColor,
                  fontFamily: fontFamily,
                  height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildSkillsBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#f7f7f7');
    final double radius = _parseNum(el['image_radius'], 16);
    final Color descColor = _parseColor(el['desc_color'] ?? '#333333');
    final double descSize = _parseNum(el['desc_font_size'], 14);
    final String fontFamily = el['font_family'] ?? 'Arial';
    final String src = (el['image_src']?.toString() ?? '').trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: src.isNotEmpty
                ? _wideImage(src, 150)
                : Container(
                    width: double.infinity,
                    height: 150,
                    color: const Color(0xFFE0E0E0),
                    child:
                        const Icon(Icons.person, color: Colors.grey, size: 40),
                  ),
          ),
          const SizedBox(height: 12),
          Text(el['description'] ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: descSize,
                  color: descColor,
                  fontFamily: fontFamily,
                  height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildFooterBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#161616');
    final Color color = _parseColor(el['color'] ?? '#ffffff');
    final double size = _parseNum(el['font_size'], 12);
    final String fontFamily = el['font_family'] ?? 'Arial';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Text(el['text'] ?? '',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: color, fontSize: size, fontFamily: fontFamily)),
    );
  }

  Widget _buildServicesBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#ffffff');
    final Color cardBg = _parseColor(el['card_bg_color'] ?? '#f7f7f7');
    final Color titleColor = _parseColor(el['title_color'] ?? '#000000');
    final Color descColor = _parseColor(el['desc_color'] ?? '#555555');
    final double titleSize = _parseNum(el['title_font_size'], 18);
    final double descSize = _parseNum(el['desc_font_size'], 13);
    final List<Map<String, dynamic>> services =
        List<Map<String, dynamic>>.from((el['services'] as List?) ?? []);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: services.isEmpty
          ? Text('Add service cards →',
              style:
                  TextStyle(color: titleColor.withOpacity(0.6), fontSize: 12))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: services
                    .map((s) => Container(
                          width: 160,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((s['title'] ?? '').toString(),
                                  style: TextStyle(
                                      color: titleColor,
                                      fontSize: titleSize,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text((s['description'] ?? '').toString(),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: descColor, fontSize: descSize)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
    );
  }

  Widget _buildPortfolioBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#ffffff');
    final Color cardBg = _parseColor(el['card_bg_color'] ?? '#f7f7f7');
    final Color titleColor = _parseColor(el['title_color'] ?? '#000000');
    final Color descColor = _parseColor(el['desc_color'] ?? '#555555');
    final double titleSize = _parseNum(el['title_font_size'], 18);
    final double descSize = _parseNum(el['desc_font_size'], 13);
    final List<Map<String, dynamic>> projects =
        List<Map<String, dynamic>>.from((el['projects'] as List?) ?? []);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: projects.isEmpty
          ? Text('Add project cards →',
              style:
                  TextStyle(color: titleColor.withOpacity(0.6), fontSize: 12))
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: projects
                  .map((p) => Container(
                        width: 150,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(10)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((p['title'] ?? '').toString(),
                                style: TextStyle(
                                    color: titleColor,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text((p['description'] ?? '').toString(),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: descColor, fontSize: descSize)),
                            const SizedBox(height: 6),
                            Text(
                                (p['link_text'] ?? '').toString().trim().isEmpty
                                    ? 'Click here to view the project'
                                    : (p['link_text'] ?? '').toString(),
                                style: TextStyle(
                                    color: titleColor,
                                    fontSize: descSize,
                                    decoration: TextDecoration.underline)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
    );
  }

  Widget _buildTestimonialsBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#f7f7f7');
    final Color nameColor = _parseColor(el['name_color'] ?? '#000000');
    final Color textColor = _parseColor(el['text_color'] ?? '#555555');
    final double nameSize = _parseNum(el['name_font_size'], 15);
    final double textSize = _parseNum(el['text_font_size'], 13);
    final List<Map<String, dynamic>> testimonials =
        List<Map<String, dynamic>>.from((el['testimonials'] as List?) ?? []);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: testimonials.isEmpty
          ? Text('Add testimonials →',
              style: TextStyle(color: nameColor.withOpacity(0.6), fontSize: 12))
          : Column(
              children: [
                Builder(builder: (context) {
                  final t = testimonials.first;
                  final String photo = (t['photo'] ?? '').toString().trim();
                  return Column(
                    children: [
                      ClipOval(
                        child: photo.isNotEmpty
                            ? _smallImage(photo, 56)
                            : Container(
                                width: 56,
                                height: 56,
                                color: const Color(0xFFDDDDDD),
                                child: const Icon(Icons.person,
                                    color: Colors.grey, size: 28),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text((t['name'] ?? '').toString(),
                          style: TextStyle(
                              color: nameColor,
                              fontSize: nameSize,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text((t['feedback'] ?? '').toString(),
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: textColor, fontSize: textSize)),
                    ],
                  );
                }),
                const SizedBox(height: 10),
                Text(
                    '${testimonials.length} testimonial(s) · rotates automatically',
                    style: TextStyle(
                        color: textColor.withOpacity(0.6), fontSize: 10)),
              ],
            ),
    );
  }

  Widget _buildContactBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#ffffff');
    final Color headingColor = _parseColor(el['heading_color'] ?? '#000000');
    final Color descColor = _parseColor(el['desc_color'] ?? '#555555');
    final double headingSize = _parseNum(el['heading_font_size'], 24);
    final double descSize = _parseNum(el['desc_font_size'], 14);
    final Color buttonColor = _parseColor(el['button_color'] ?? '#1565c0');
    final Color buttonTextColor =
        _parseColor(el['button_text_color'] ?? '#ffffff');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          Text((el['heading'] ?? '').toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: headingColor,
                  fontSize: headingSize,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text((el['description'] ?? '').toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: descColor, fontSize: descSize)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                width: 150,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Your email address',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                    color: buttonColor, borderRadius: BorderRadius.circular(6)),
                child: Text((el['button_text'] ?? '').toString(),
                    style: TextStyle(
                        color: buttonTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoreBlockContent(Map<String, dynamic> el) {
    final Color bg = _parseColor(el['bg_color'] ?? '#ffffff');
    final Color cardBg = _parseColor(el['card_bg_color'] ?? '#f7f7f7');
    final Color titleColor = _parseColor(el['title_color'] ?? '#000000');
    final Color priceColor = _parseColor(el['price_color'] ?? '#e53935');
    final List<Map<String, dynamic>> products =
        List<Map<String, dynamic>>.from((el['products'] as List?) ?? []);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _canvasBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('Search products...',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            Text('Add products →',
                style:
                    TextStyle(color: titleColor.withOpacity(0.6), fontSize: 12))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              // Store Section Card Backgrounds: each product card can
              // override the block-wide card background color.
              children: products
                  .map((p) => Container(
                        width: 110,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: (p['bg_color']
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ??
                                    false)
                                ? _parseColor(p['bg_color'].toString().trim())
                                : cardBg,
                            borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child:
                                  (p['image']?.toString().trim().isNotEmpty ??
                                          false)
                                      ? _wideImage(p['image'].toString(), 60)
                                      : Container(
                                          width: double.infinity,
                                          height: 60,
                                          color: const Color(0xFFE0E0E0),
                                          child: const Icon(Icons.image,
                                              color: Colors.grey, size: 20),
                                        ),
                            ),
                            const SizedBox(height: 6),
                            Text((p['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: titleColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            Text((p['price'] ?? '').toString(),
                                style:
                                    TextStyle(color: priceColor, fontSize: 11)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _smallImage(String src, double size) {
    final bool isData = src.startsWith('data:');
    Widget img;
    try {
      img = isData
          ? Image.memory(base64Decode(_stripDataUrl(src)),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, o, s) =>
                  Icon(Icons.image, color: Colors.white70, size: size * 0.7))
          : Image.network(src,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, o, s) =>
                  Icon(Icons.image, color: Colors.white70, size: size * 0.7));
    } catch (_) {
      img = Icon(Icons.image, color: Colors.white70, size: size * 0.7);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(6), child: img);
  }

  Widget _wideImage(String src, double height) {
    final bool isData = src.startsWith('data:');
    if (isData) {
      try {
        return Image.memory(base64Decode(_stripDataUrl(src)),
            width: double.infinity,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (c, o, s) => _imagePlaceholder());
      } catch (_) {
        return _imagePlaceholder();
      }
    }
    return Image.network(src,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) => _imagePlaceholder());
  }

  Widget _buildImageView(Map<String, dynamic> el) {
    final src = (el['src'] ?? '').toString().trim();
    if (src.isNotEmpty) {
      final height = _parseNum(el['height'], 100) == 0
          ? 100.0
          : _parseNum(el['height'], 100).toDouble();
      final isData = src.startsWith('data:');
      final Widget img = isData
          ? Image.memory(
              base64Decode(_stripDataUrl(src)),
              fit: BoxFit.cover,
              width: double.infinity,
              height: height,
              errorBuilder: (c, o, s) => _imagePlaceholder(),
            )
          : Image.network(
              src,
              fit: BoxFit.cover,
              width: double.infinity,
              height: height,
              errorBuilder: (c, o, s) => _imagePlaceholder(),
            );
      return ClipRRect(
        borderRadius: BorderRadius.circular(_parseNum(el['border_radius'], 4)),
        child: img,
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 70,
      color: const Color(0xFFE0E0E0),
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey, size: 28),
      ),
    );
  }

  // ---- Unified "On Click" interaction panel ----------------------------
  // Replaces the old standalone JS button in the widget bottom bar with a
  // single entry point that opens a small panel of three action buttons:
  // Click Code (JS), Hover Code (CSS), Active Code (CSS). Each opens its
  // own focused single-field editor.
  void _openOnClickPanel() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('On Click',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _onClickActionButton(
                Icons.javascript, 'Click Code (JavaScript)', 'click_js'),
            _onClickActionButton(Icons.mouse, 'Hover Code (CSS)', 'hover_css'),
            _onClickActionButton(
                Icons.touch_app, 'Active Code (CSS)', 'active_css'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _onClickActionButton(IconData icon, String label, String key) {
    final bool hasCode = (selectedElement?[key]?.toString() ?? '').isNotEmpty;
    return ListTile(
      dense: true,
      leading: Icon(icon,
          color: hasCode ? Colors.lightBlueAccent : Colors.grey, size: 20),
      title: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      trailing: hasCode
          ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16)
          : null,
      onTap: () {
        Navigator.pop(context);
        _openCodeFieldPopup(label, key);
      },
    );
  }

  void _openCodeFieldPopup(String label, String key) {
    final ctrl =
        TextEditingController(text: selectedElement?[key]?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: SingleChildScrollView(child: _jsField(label, ctrl)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() => selectedElement![key] = ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openJsPopup() {
    final TextEditingController clickCtrl =
        TextEditingController(text: selectedElement?['click_js'] ?? '');
    final TextEditingController jsCtrl =
        TextEditingController(text: selectedElement?['js_code'] ?? '');
    final TextEditingController hoverCtrl =
        TextEditingController(text: selectedElement?['hover_css'] ?? '');
    final TextEditingController activeCtrl =
        TextEditingController(text: selectedElement?['active_css'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Interaction & JavaScript Code',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _jsField('Click code (JavaScript)', clickCtrl),
              _jsField('Hover code (CSS)', hoverCtrl),
              _jsField('Active code (CSS)', activeCtrl),
              _jsField('JS code run on page load', jsCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() {
                selectedElement!['click_js'] = clickCtrl.text;
                selectedElement!['hover_css'] = hoverCtrl.text;
                selectedElement!['active_css'] = activeCtrl.text;
                selectedElement!['js_code'] = jsCtrl.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _jsField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        maxLines: 3,
        style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  // Generalized image picker: writes the picked image (as a data: URL)
  // into whichever property [key] the current block/widget uses for its
  // image (e.g. 'src' for the Image widget, 'logo_src' for the Header
  // block, 'image_src' for the Skills / Profile block).
  Future<void> _pickImageInto(String key) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();
      final mime = ext == 'jpg' || ext == 'jpeg'
          ? 'image/jpeg'
          : ext == 'png'
              ? 'image/png'
              : ext == 'webp'
                  ? 'image/webp'
                  : 'image/png';
      if (!mounted) return;
      setState(() {
        selectedElement![key] = 'data:$mime;base64,${base64Encode(bytes)}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  // ------------------------------------------------------------
  //  CUSTOM BACKGROUND SUPPORT (project-wide card/notebook background)
  // ------------------------------------------------------------
  Future<void> _pickCanvasBackgroundImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();
      final mime = ext == 'jpg' || ext == 'jpeg'
          ? 'image/jpeg'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/png';
      if (!mounted) return;
      setState(() {
        canvasBgType = 'image';
        canvasBgImage = 'data:$mime;base64,${base64Encode(bytes)}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  void _openCanvasBackgroundPopup() {
    final urlCtrl = TextEditingController(
        text: canvasBgImage.startsWith('data:') ? '' : canvasBgImage);
    final colorCtrl = TextEditingController(text: canvasBgColor);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Page background',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Solid color',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: colorCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: '#ffffff',
                          hintStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey)),
                        ),
                        onChanged: (v) {
                          setState(() {
                            canvasBgType = 'color';
                            canvasBgColor = v.startsWith('#') ? v : '#$v';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent),
                      onPressed: () {
                        setState(() {
                          canvasBgType = 'color';
                          canvasBgColor = colorCtrl.text.startsWith('#')
                              ? colorCtrl.text
                              : '#${colorCtrl.text}';
                        });
                        setDialogState(() {});
                      },
                      child: const Text('Use color',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Background image',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/background.jpg',
                    hintStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey)),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent),
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Use URL'),
                      onPressed: () {
                        if (urlCtrl.text.trim().isEmpty) return;
                        setState(() {
                          canvasBgType = 'image';
                          canvasBgImage = urlCtrl.text.trim();
                        });
                        setDialogState(() {});
                      },
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent),
                      icon: const Icon(Icons.photo_library, size: 16),
                      label: const Text('From device'),
                      onPressed: () async {
                        await _pickCanvasBackgroundImage();
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
                if (canvasBgType == 'image' && canvasBgImage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    icon: const Icon(Icons.clear,
                        color: Colors.redAccent, size: 16),
                    label: const Text('Remove image, use color instead',
                        style:
                            TextStyle(color: Colors.redAccent, fontSize: 12)),
                    onPressed: () {
                      setState(() {
                        canvasBgType = 'color';
                        canvasBgImage = '';
                      });
                      setDialogState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  //  CUSTOM TTF FONT UPLOAD
  // ------------------------------------------------------------
  Future<void> _uploadCustomFont() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final selected = result.files.first;
      final bytes = selected.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read that font file.')));
        return;
      }
      // Font family name = file name without extension, so it's
      // immediately recognizable in the font picker (e.g.
      // "MyBrandFont.ttf" -> family "MyBrandFont").
      String familyName = selected.name;
      if (familyName.toLowerCase().endsWith('.ttf')) {
        familyName = familyName.substring(0, familyName.length - 4);
      }
      familyName = familyName.trim().isEmpty ? 'CustomFont' : familyName;

      // Register the font with the Flutter engine so it also renders
      // correctly live, right here in the drag & drop canvas — not just
      // in the exported HTML/CSS — the moment it's uploaded.
      final fontLoader = FontLoader(familyName);
      fontLoader.addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      await fontLoader.load();

      if (!mounted) return;
      setState(() {
        customFonts[familyName] = 'data:font/ttf;base64,${base64Encode(bytes)}';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '"$familyName" uploaded — pick it from any Font family menu.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error uploading font: $e')));
    }
  }

  String _typeLabel(String type) {
    const labels = {
      'header_block': 'Header Block (logo + nav menu)',
      'title_desc_block': 'Title & Description Block',
      'skills_block': 'Skills / Profile Block',
      'footer_block': 'Footer Block',
      'services_block': 'Services Block (auto-sliding cards)',
      'portfolio_block': 'Portfolio Block (project cards)',
      'testimonials_block': 'Testimonials Block (auto-rotating)',
      'contact_block': 'Contact Block (email CTA)',
      'store_block': 'Store Block (search + product grid)',
      'buttons_block': 'Custom Buttons Section',
      'social_block': 'Social Media Bar',
      'youtube_widget': 'YouTube Video',
      'custom': 'Custom Component',
      'text': 'Text (p)',
      'edit_number': 'Edit Number (input type=number)',
      'edit_text': 'Edit Text (input)',
      'link': 'Link (a)',
      'button': 'Button',
      'image': 'Image (img)',
    };
    return labels[type] ?? type;
  }

  String _cleanId(String id) {
    final cleaned = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? 'elem' : cleaned;
  }

  Color _parseColor(String hex) {
    if (hex.trim().toLowerCase() == 'transparent') return Colors.transparent;
    final h = hex.replaceAll('#', '');
    if (h.length == 6) {
      return Color(int.parse('FF$h', radix: 16));
    }
    if (h.length == 3) {
      final e = h.split('').map((c) => '$c$c').join();
      return Color(int.parse('FF$e', radix: 16));
    }
    return Colors.black;
  }

  double _parseNum(String val, double def) {
    final m = RegExp(r'[\d.]+').firstMatch(val);
    if (m != null) return double.tryParse(m.group(0)!) ?? def;
    return def;
  }

  // Background Image Customization for All Divs: returns a cover-fit
  // DecorationImage for the given element's bg_image (or
  // container_bg_image) key, or null if none is set — used alongside
  // this Container's background color so the image renders on top of it.
  DecorationImage? _canvasBgImage(Map<String, dynamic> el,
      [String key = 'bg_image']) {
    final String src = (el[key]?.toString() ?? '').trim();
    if (src.isEmpty) return null;
    return DecorationImage(
      image: src.startsWith('data:')
          ? MemoryImage(base64Decode(src.substring(src.indexOf(',') + 1)))
              as ImageProvider
          : NetworkImage(src) as ImageProvider,
      fit: BoxFit.cover,
    );
  }

  TextAlign _parseAlign(String align) {
    switch (align) {
      case 'right':
        return TextAlign.right;
      case 'left':
        return TextAlign.left;
      default:
        return TextAlign.center;
    }
  }

  AlignmentGeometry _parseAlignment(String align) {
    switch (align) {
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.center;
    }
  }

  // Maps a 'left' | 'center' | 'right' text_align value to the matching
  // Column crossAxisAlignment (used by the Title & Desc. block preview).
  CrossAxisAlignment _crossAxisAlignFor(String align) {
    switch (align) {
      case 'left':
        return CrossAxisAlignment.start;
      case 'right':
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.center;
    }
  }

  String _esc(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  String _escJs(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll('\n', ' ');
  }

  String _stripDataUrl(String src) {
    final idx = src.indexOf(',');
    return idx == -1 ? src : src.substring(idx + 1);
  }

  // Background Image Customization for All Divs: every section/container
  // can swap its solid background color for a custom image (device upload
  // or URL), stored in the shared 'bg_image' key. Returns an inline style
  // attribute (or '' if no image is set) meant to be appended right after
  // an opening tag, so it layers on top of that element's own CSS rule
  // (background-color stays as a fallback if the image fails to load).
  String _bgImageAttr(Map<String, dynamic> el, [String key = 'bg_image']) {
    final String img = (el[key]?.toString() ?? '').trim();
    if (img.isEmpty) return '';
    return ' style="background-image: url(\'${_esc(img)}\'); '
        'background-size: cover; background-position: center;"';
  }
}

// ============================================================
//  PREVIEW SCREEN
// ============================================================
class PreviewScreen extends StatelessWidget {
  final String projectName;
  final List<Map<String, dynamic>> elements;
  // Dropdown Menu Functionality: same scroll-to-section approach as the
  // live editor canvas — one GlobalKey per block ID, looked up when a
  // menu item is tapped.
  final Map<String, GlobalKey> _sectionKeys = {};

  PreviewScreen({super.key, required this.projectName, required this.elements});

  GlobalKey _keyForSection(String id) =>
      _sectionKeys.putIfAbsent(id, () => GlobalKey());

  String _cleanId(String id) {
    final cleaned = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? 'elem' : cleaned;
  }

  void _openHeaderMenuDropdown(BuildContext context, Map<String, dynamic> el) {
    final List<Map<String, dynamic>> navItems =
        List<Map<String, dynamic>>.from((el['nav_items'] as List?) ?? []);
    if (navItems.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('Menu',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        children: navItems.map((item) {
          final label = (item['label'] ?? '').toString();
          final target = _cleanId((item['target'] ?? '').toString());
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialogContext);
              final key = _sectionKeys[target];
              if (key?.currentContext != null) {
                Scrollable.ensureVisible(
                  key!.currentContext!,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                );
              }
            },
            child: Text(label.isEmpty ? '(untitled)' : label,
                style: const TextStyle(color: Colors.white)),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Preview: $projectName'),
        backgroundColor: Colors.black,
      ),
      body: Container(
        color: const Color(0xFFF5F5F5),
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double maxW =
                  constraints.maxWidth < 1100 ? constraints.maxWidth : 1100;
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: elements.map((el) {
                    final String id = (el['id']?.toString() ?? '').trim();
                    final Widget content = _buildPreviewWidget(el, context);
                    return id.isEmpty
                        ? content
                        : KeyedSubtree(key: _keyForSection(id), child: content);
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewWidget(Map<String, dynamic> el, BuildContext context) {
    final String type = el['type'];
    switch (type) {
      case 'header_block':
        return _previewHeader(el, context);
      case 'title_desc_block':
        return _previewTitleDesc(el);
      case 'skills_block':
        return _previewSkills(el);
      case 'footer_block':
        return _previewFooter(el);
      case 'services_block':
        return _previewServices(el);
      case 'portfolio_block':
        return _previewPortfolio(el);
      case 'testimonials_block':
        return _previewTestimonials(el);
      case 'contact_block':
        return _previewContact(el);
      case 'store_block':
        return _previewStore(el);
      case 'youtube_widget':
        return _previewYoutube(el);
      case 'buttons_block':
        return _previewButtons(el);
      case 'social_block':
        return _previewSocial(el);
      case 'custom':
        return _customComponentPlaceholder(el);
    }

    final String id = el['id'] ?? '';
    final Color bg = _color(el['bg_color'] ?? '#ffffff');
    final Color color = _color(el['color'] ?? '#000000');
    final double rad = _num(el['border_radius'], 4);
    final double pad = _num(el['padding'], 4);
    final double mar = _num(el['margin'], 2);
    final Color borderC = _color(el['border_color'] ?? '#cccccc');

    Widget content;
    switch (type) {
      case 'text':
        final bool isBold = (el['bold']?.toString() ?? 'false') == 'true';
        final bool isUnderline =
            (el['underline']?.toString() ?? 'false') == 'true';
        final double opacityPct = double.tryParse(
                (el['opacity']?.toString() ?? '100').replaceAll('%', '')) ??
            100;
        content = Opacity(
          opacity: (opacityPct / 100).clamp(0, 1),
          child: Text(
            el['text'] ?? '',
            textAlign: _align(el['text_align']),
            style: TextStyle(
              fontSize: _num(el['font_size'], 14),
              fontFamily: el['font_family'] ?? 'Arial',
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              decoration:
                  isUnderline ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
        );
        break;
      case 'link':
        content = Text(
          el['text'] ?? 'Link',
          textAlign: _align(el['text_align']),
          style: TextStyle(
            fontSize: _num(el['font_size'], 14),
            fontFamily: el['font_family'] ?? 'Arial',
            color: color,
            decoration: TextDecoration.underline,
          ),
        );
        break;
      case 'button':
        content = Container(
          alignment: Alignment.center,
          child: Text(
            el['text'] ?? 'Button',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _num(el['font_size'], 14),
              fontFamily: el['font_family'] ?? 'Arial',
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        break;
      case 'edit_number':
        content = _previewInput(el, keyboard: TextInputType.number);
        break;
      case 'edit_text':
        content = _previewInput(el, keyboard: TextInputType.text);
        break;
      case 'image':
        content = _previewImage(el);
        break;
      default:
        content = const SizedBox();
    }

    final String heightVal = (el['height'] ?? 'auto').toString().trim();
    double? computedWidth;
    if (el['width'] == '100%') {
      computedWidth = double.infinity;
    } else if (el['width'] != null) {
      computedWidth = _num(el['width'], 0);
    } else {
      computedWidth = double.infinity;
    }

    return Container(
      key: ValueKey(id),
      width: computedWidth,
      height: (heightVal.isEmpty || heightVal == 'auto')
          ? null
          : _num(heightVal, 0),
      margin: EdgeInsets.all(mar),
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: bg,
        image: _previewBgImage(el, 'container_bg_image'),
        borderRadius: BorderRadius.circular(rad),
        border: Border.all(color: borderC, width: 1),
      ),
      child: content,
    );
  }

  Widget _previewYoutube(Map<String, dynamic> el) {
    final String videoUrl = (el['video_url'] ?? '').toString().trim();
    final String title = (el['title'] ?? '').toString().trim();
    final String thumb = (el['thumb_src'] ?? '').toString().trim();
    final double radius = _num(el['border_radius'], 10);
    if (videoUrl.isEmpty) return const SizedBox();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 480),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (thumb.isNotEmpty) _previewWideImage(thumb, 480, 270),
                  Center(
                    child: Container(
                      width: 56,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 26),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _previewButtons(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#ffffff');
    final buttons =
        List<Map<String, dynamic>>.from((el['buttons'] as List?) ?? []);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: buttons.map((b) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: _color(b['bg_color'] ?? '#1565c0'),
              borderRadius: BorderRadius.circular(_num(b['border_radius'], 8)),
            ),
            child: Text((b['text'] ?? 'Button').toString(),
                style: TextStyle(
                    color: _color(b['text_color'] ?? '#ffffff'),
                    fontSize: _num(b['font_size'], 14),
                    fontFamily: (b['font_family'] ?? 'Arial').toString(),
                    fontWeight: FontWeight.w600)),
          );
        }).toList(),
      ),
    );
  }

  Widget _previewSocial(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#ffffff');
    final iconStyle = (el['icon_style'] ?? 'color').toString();
    final iconSize = _num(el['icon_size'], 32);
    final items = List<Map<String, dynamic>>.from((el['items'] as List?) ?? []);
    const Map<String, Color> brandColors = {
      'facebook': Color(0xFF1877F2),
      'whatsapp': Color(0xFF25D366),
      'telegram': Color(0xFF26A5E4),
      'x': Color(0xFF000000),
      'instagram': Color(0xFFE1306C),
      'github': Color(0xFF333333),
    };
    const Map<String, String> initials = {
      'facebook': 'f',
      'whatsapp': 'W',
      'telegram': 'T',
      'x': 'X',
      'instagram': 'IG',
      'github': 'GH',
    };
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: items.map((item) {
          final String platform = (item['platform'] ?? '').toString();
          final Color color = iconStyle == 'mono'
              ? const Color(0xFF333333)
              : (brandColors[platform] ?? Colors.grey);
          return Container(
            width: iconSize,
            height: iconSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(initials[platform] ?? '?',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: iconSize / 2.2,
                    fontWeight: FontWeight.bold)),
          );
        }).toList(),
      ),
    );
  }

  Widget _previewHeader(Map<String, dynamic> el, BuildContext context) {
    final bg = _color(el['bg_color'] ?? '#0277BD');
    final h = _num((el['height'] ?? '70').toString(), 70);
    final navColor = _color(el['nav_color'] ?? '#ffffff');
    final navSize = _num((el['nav_font_size'] ?? '14').toString(), 14);
    final navFontFamily = (el['font_family'] ?? 'Arial').toString();
    final headerText = (el['header_text'] ?? '').toString();
    final logo = (el['logo_src']?.toString() ?? '').trim();
    // Header ("Navigation Bar") Section: image + descriptive text pinned
    // far left; "Menu" label + 3-line hamburger icon pinned far right,
    // matching the exported site's collapsed menu bar.
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: h),
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Expanded (not a bare nested Row) is what gives the Flexible
          // ellipsis Text below a bounded width to shrink into — without
          // it, a long header_text throws/overflows instead of trimming.
          Expanded(
            child: Row(
              children: [
                if (logo.isNotEmpty)
                  _previewSmallImage(logo, 40)
                else
                  const SizedBox(width: 0, height: 40),
                if (headerText.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(headerText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: navColor,
                            fontSize: navSize,
                            fontFamily: navFontFamily,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Dropdown Menu Functionality: tapping "Menu" lists the header's
          // sections and smoothly scrolls straight to whichever is picked.
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openHeaderMenuDropdown(context, el),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Menu',
                    style: TextStyle(
                        color: navColor,
                        fontSize: navSize,
                        fontFamily: navFontFamily,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      3,
                      (_) => Container(
                            width: 22,
                            height: 3,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: navColor,
                          )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewTitleDesc(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#ffffff');
    final titleColor = _color(el['title_color'] ?? '#000000');
    final descColor = _color(el['desc_color'] ?? '#444444');
    final titleSize = _num((el['title_font_size'] ?? '26').toString(), 26);
    final descSize = _num((el['desc_font_size'] ?? '15').toString(), 15);
    final fontFamily = (el['font_family'] ?? 'Arial').toString();
    // Title & Description Text Alignment control.
    final String alignKey = (el['text_align'] ?? 'center').toString();
    final TextAlign textAlign = _align(alignKey);
    final CrossAxisAlignment crossAlign = alignKey == 'left'
        ? CrossAxisAlignment.start
        : alignKey == 'right'
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        crossAxisAlignment: crossAlign,
        children: [
          Text(el['title'] ?? '',
              textAlign: textAlign,
              style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: fontFamily,
                  color: titleColor)),
          const SizedBox(height: 10),
          Text(el['description'] ?? '',
              textAlign: textAlign,
              style: TextStyle(
                  fontSize: descSize,
                  color: descColor,
                  fontFamily: fontFamily,
                  height: 1.5)),
        ],
      ),
    );
  }

  Widget _previewSkills(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#f7f7f7');
    final radius = _num((el['image_radius'] ?? '16').toString(), 16);
    final descColor = _color(el['desc_color'] ?? '#333333');
    final descSize = _num((el['desc_font_size'] ?? '15').toString(), 15);
    final fontFamily = (el['font_family'] ?? 'Arial').toString();
    final src = (el['image_src']?.toString() ?? '').trim();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: src.isEmpty
                ? Container(
                    width: 220,
                    height: 150,
                    color: const Color(0xFFE0E0E0),
                    child:
                        const Icon(Icons.person, size: 40, color: Colors.grey),
                  )
                : _previewWideImage(src, 220, 150),
          ),
          const SizedBox(height: 14),
          Text(el['description'] ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: descSize,
                  color: descColor,
                  fontFamily: fontFamily,
                  height: 1.5)),
        ],
      ),
    );
  }

  Widget _previewFooter(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#161616');
    final color = _color(el['color'] ?? '#ffffff');
    final size = _num((el['font_size'] ?? '12').toString(), 12);
    final fontFamily = el['font_family'] ?? 'Arial';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Text(el['text'] ?? '',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: color, fontSize: size, fontFamily: fontFamily)),
    );
  }

  Widget _previewServices(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#ffffff');
    final cardBg = _color(el['card_bg_color'] ?? '#f7f7f7');
    final titleColor = _color(el['title_color'] ?? '#000000');
    final descColor = _color(el['desc_color'] ?? '#555555');
    final titleSize = _num((el['title_font_size'] ?? '18').toString(), 18);
    final descSize = _num((el['desc_font_size'] ?? '13').toString(), 13);
    final services =
        List<Map<String, dynamic>>.from((el['services'] as List?) ?? []);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: services
              .map((s) => Container(
                    width: 180,
                    margin: const EdgeInsets.only(right: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: cardBg, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['title']?.toString() ?? '',
                            style: TextStyle(
                                color: titleColor,
                                fontSize: titleSize,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(s['description']?.toString() ?? '',
                            style: TextStyle(
                                color: descColor, fontSize: descSize)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _previewPortfolio(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#ffffff');
    final cardBg = _color(el['card_bg_color'] ?? '#f7f7f7');
    final titleColor = _color(el['title_color'] ?? '#000000');
    final descColor = _color(el['desc_color'] ?? '#555555');
    final titleSize = _num((el['title_font_size'] ?? '18').toString(), 18);
    final descSize = _num((el['desc_font_size'] ?? '13').toString(), 13);
    final projects =
        List<Map<String, dynamic>>.from((el['projects'] as List?) ?? []);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: projects
            .map((p) => Container(
                  width: 170,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: cardBg, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['title']?.toString() ?? '',
                          style: TextStyle(
                              color: titleColor,
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(p['description']?.toString() ?? '',
                          style:
                              TextStyle(color: descColor, fontSize: descSize)),
                      const SizedBox(height: 6),
                      Text(
                          (p['link_text']?.toString() ?? '').trim().isEmpty
                              ? 'Click here to view the project'
                              : p['link_text'].toString(),
                          style: TextStyle(
                              color: titleColor,
                              fontSize: descSize,
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _previewTestimonials(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#f7f7f7');
    final nameColor = _color(el['name_color'] ?? '#000000');
    final textColor = _color(el['text_color'] ?? '#555555');
    final nameSize = _num((el['name_font_size'] ?? '15').toString(), 15);
    final textSize = _num((el['text_font_size'] ?? '13').toString(), 13);
    final testimonials =
        List<Map<String, dynamic>>.from((el['testimonials'] as List?) ?? []);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: testimonials
            .map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      ClipOval(
                        child:
                            (t['photo']?.toString().trim().isNotEmpty ?? false)
                                ? _previewSmallImage(t['photo'].toString(), 56)
                                : Container(
                                    width: 56,
                                    height: 56,
                                    color: const Color(0xFFDDDDDD),
                                    child: const Icon(Icons.person,
                                        color: Colors.grey, size: 28),
                                  ),
                      ),
                      const SizedBox(height: 8),
                      Text(t['name']?.toString() ?? '',
                          style: TextStyle(
                              color: nameColor,
                              fontSize: nameSize,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(t['feedback']?.toString() ?? '',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: textColor, fontSize: textSize)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _previewContact(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#ffffff');
    final headingColor = _color(el['heading_color'] ?? '#000000');
    final descColor = _color(el['desc_color'] ?? '#555555');
    final headingSize = _num((el['heading_font_size'] ?? '24').toString(), 24);
    final descSize = _num((el['desc_font_size'] ?? '14').toString(), 14);
    final buttonColor = _color(el['button_color'] ?? '#1565c0');
    final buttonTextColor = _color(el['button_text_color'] ?? '#ffffff');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Text(el['heading']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: headingColor,
                  fontSize: headingSize,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(el['description']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: descColor, fontSize: descSize)),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                width: 180,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Your email address',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                decoration: BoxDecoration(
                    color: buttonColor, borderRadius: BorderRadius.circular(6)),
                child: Text(el['button_text']?.toString() ?? '',
                    style: TextStyle(
                        color: buttonTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewStore(Map<String, dynamic> el) {
    final bg = _color(el['bg_color'] ?? '#ffffff');
    final cardBg = _color(el['card_bg_color'] ?? '#f7f7f7');
    final titleColor = _color(el['title_color'] ?? '#000000');
    final priceColor = _color(el['price_color'] ?? '#e53935');
    final descColor = _color(el['desc_color'] ?? '#555555');
    final products =
        List<Map<String, dynamic>>.from((el['products'] as List?) ?? []);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: bg, image: _previewBgImage(el)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('Search products...',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            // Store Section Card Backgrounds: per-product override, falls
            // back to the block-wide card background color.
            children: products
                .map((p) => Container(
                      width: 140,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: (p['bg_color']?.toString().trim().isNotEmpty ??
                                  false)
                              ? _color(p['bg_color'].toString().trim())
                              : cardBg,
                          borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: (p['image']?.toString().trim().isNotEmpty ??
                                    false)
                                ? _previewWideImage(
                                    p['image'].toString(), 140, 80)
                                : Container(
                                    width: double.infinity,
                                    height: 80,
                                    color: const Color(0xFFE0E0E0),
                                    child: const Icon(Icons.image,
                                        color: Colors.grey, size: 24),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(p['name']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: titleColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text(p['price']?.toString() ?? '',
                              style:
                                  TextStyle(color: priceColor, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(p['description']?.toString() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: descColor, fontSize: 11)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _previewSmallImage(String src, double size) {
    if (src.startsWith('data:')) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image(
              image: MemoryImage(base64Decode(_strip(src))),
              width: size,
              height: size,
              fit: BoxFit.cover),
        );
      } catch (_) {
        return SizedBox(width: size, height: size);
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(src,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (c, o, s) => SizedBox(width: size, height: size)),
    );
  }

  Widget _previewWideImage(String src, double width, double height) {
    if (src.startsWith('data:')) {
      try {
        return Image(
            image: MemoryImage(base64Decode(_strip(src))),
            width: width,
            height: height,
            fit: BoxFit.cover);
      } catch (_) {
        return Container(
            width: width, height: height, color: const Color(0xFFE0E0E0));
      }
    }
    return Image.network(src,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (c, o, s) => Container(
            width: width, height: height, color: const Color(0xFFE0E0E0)));
  }

  Widget _previewInput(Map<String, dynamic> el,
      {required TextInputType keyboard}) {
    return TextField(
      keyboardType: keyboard,
      style: TextStyle(
        fontSize: _num(el['font_size'], 14),
        fontFamily: el['font_family'] ?? 'Arial',
        color: _color(el['color'] ?? '#000000'),
      ),
      decoration: InputDecoration(
        hintText: el['hint'] ?? '',
        hintStyle:
            TextStyle(fontSize: _num(el['font_size'], 14), color: Colors.grey),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_num(el['border_radius'], 4)),
          borderSide:
              BorderSide(color: _color(el['border_color'] ?? '#cccccc')),
        ),
      ),
    );
  }

  Widget _previewImage(Map<String, dynamic> el) {
    final src = (el['src'] ?? '').toString().trim();
    if (src.isNotEmpty) {
      final double h = _num(el['height'], 100);
      Widget img;
      if (src.startsWith('data:')) {
        try {
          img = Image(
            image: MemoryImage(base64Decode(_strip(src))),
            fit: BoxFit.cover,
            width: double.infinity,
            height: h,
          );
        } catch (_) {
          img = _placeholder();
        }
      } else {
        img = Image.network(
          src,
          fit: BoxFit.cover,
          width: double.infinity,
          height: h,
          errorBuilder: (c, o, s) => _placeholder(),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(_num(el['border_radius'], 4)),
        child: img,
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      height: 70,
      color: const Color(0xFFE0E0E0),
      child:
          const Center(child: Icon(Icons.image, color: Colors.grey, size: 28)),
    );
  }

  Color _color(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 3) {
      final e = h.split('').map((c) => '$c$c').join();
      return Color(int.parse('FF$e', radix: 16));
    }
    return Colors.black;
  }

  double _num(String val, double def) {
    final m = RegExp(r'[\d.]+').firstMatch(val);
    if (m != null) return double.tryParse(m.group(0)!) ?? def;
    return def;
  }

  DecorationImage? _previewBgImage(Map<String, dynamic> el,
      [String key = 'bg_image']) {
    final String src = (el[key]?.toString() ?? '').trim();
    if (src.isEmpty) return null;
    return DecorationImage(
      image: src.startsWith('data:')
          ? MemoryImage(base64Decode(src.substring(src.indexOf(',') + 1)))
              as ImageProvider
          : NetworkImage(src) as ImageProvider,
      fit: BoxFit.cover,
    );
  }

  TextAlign _align(String a) {
    if (a == 'right') return TextAlign.right;
    if (a == 'left') return TextAlign.left;
    return TextAlign.center;
  }

  String _strip(String src) {
    final idx = src.indexOf(',');
    return idx == -1 ? src : src.substring(idx + 1);
  }
}
