import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'editor_screen.dart';
import 'saved_project_screen.dart';
import 'store_screen.dart';
import 'smart_builder_screen.dart';
import 'learn_screen.dart';
import 'about_screen.dart';
import 'drag_and_drop_home_screen.dart'; // افترضنا اسم ملف الواجهة الجديدة كذا

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<List<SharedMediaFile>>? _sharedMediaSubscription;
  String? _pendingSharedPath;
  String? _lastSharedPath;
  bool _homeReady = false;
  bool _isOpeningSharedFile = false;

  @override
  void initState() {
    super.initState();
    _initSharingIntent();

    // التحقق هل هذه المرة الأولى التي يفتح فيها المستخدم التطبيق أم لا
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstTimeUser().then((_) {
        if (!mounted) return;
        _homeReady = true;
        _openPendingSharedFile();
      });
    });
  }

  // دالة لفتح الروابط الخارجية
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $urlString';
    }
  }

  // دالة لفحص ما إذا ظهرت الشروط من قبل
  Future<void> _checkFirstTimeUser() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasAgreed = prefs.getBool('has_agreed_disclaimer') ?? false;

    if (!hasAgreed) {
      await _showDisclaimerDialog(prefs);
    }
  }

  // نافذة الشروط وإخلاء المسؤولية الإجبارية (تظهر مرة واحدة فقط)
  Future<void> _showDisclaimerDialog(SharedPreferences prefs) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // لا يمكن إغلاق النافذة بالضغط خارجها
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // منع زر الرجوع بالجهاز
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Terms & Disclaimer',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: const SingleChildScrollView(
              child: Text(
                'This application is intended strictly for learning, development, and legitimate coding purposes. We assume no legal or ethical responsibility for any misuse, harmful, or unlawful use of the codes or files created, executed, or shared through this application.\n\n'
                'By clicking "Agree & Continue", you accept these terms and take full responsibility for your use.',
                style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
              ),
            ),
            actions: [
              // زر الرفض: يغلق التطبيق بالكامل
              TextButton(
                onPressed: () {
                  SystemNavigator.pop(); // غلق التطبيق
                },
                child: const Text(
                  'Decline',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              // زر الموافقة: يحفظ الموافقة ولن تظهر النافذة مرة أخرى
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                ),
                onPressed: () async {
                  await prefs.setBool(
                      'has_agreed_disclaimer', true); // حفظ الحالة
                  Navigator.of(context).pop(); // إغلاق النافذة
                },
                child: const Text(
                  'Agree & Continue',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _sharedMediaSubscription?.cancel();
    super.dispose();
  }

  void _initSharingIntent() {
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        _queueSharedFile(value.first.path);
      }
      ReceiveSharingIntent.instance.reset();
    });

    _sharedMediaSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) {
        _queueSharedFile(value.first.path);
      }
    });
  }

  void _queueSharedFile(String? filePath) {
    if (filePath == null || filePath.trim().isEmpty) return;
    if (_lastSharedPath == filePath && _pendingSharedPath == null) return;
    _pendingSharedPath = filePath;
    if (_homeReady) _openPendingSharedFile();
  }

  void _openPendingSharedFile() {
    final path = _pendingSharedPath;
    if (path == null || _isOpeningSharedFile) return;
    _pendingSharedPath = null;
    _lastSharedPath = path;
    _processAndNavigate(path);
  }

  String _normalizeProjectPath(String raw) {
    var value = raw.trim().replaceAll('\\', '/');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
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
    final slash = normalized.lastIndexOf('/');
    return slash <= 0 ? '' : normalized.substring(0, slash);
  }

  String _extensionOf(String path) {
    final name = _normalizeProjectPath(path).split('/').last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool _isCodePath(String path) =>
      const {'html', 'css', 'js'}.contains(_extensionOf(path));

  String _mimeForPath(String path) {
    switch (_extensionOf(path)) {
      case 'svg':
        return 'image/svg+xml';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'css':
        return 'text/css';
      case 'js':
        return 'text/javascript';
      case 'html':
        return 'text/html';
      case 'woff':
        return 'font/woff';
      case 'woff2':
        return 'font/woff2';
      case 'ttf':
        return 'font/ttf';
      case 'otf':
        return 'font/otf';
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  List<int> _archiveEntryBytes(dynamic entry) {
    final content = entry.content;
    return content is List<int> ? content : List<int>.from(content as Iterable);
  }

  Future<void> _processAndNavigate(String filePath) async {
    if (_isOpeningSharedFile) return;
    _isOpeningSharedFile = true;
    try {
      final localPath = filePath.startsWith('file://')
          ? Uri.parse(filePath).toFilePath()
          : filePath;
      final entityType = await FileSystemEntity.type(localPath);
      if (entityType == FileSystemEntityType.notFound) {
        throw StateError('Shared file is no longer available: $filePath');
      }

      final fileName = localPath.split(RegExp(r'[/\\]')).last;
      final extension = _extensionOf(fileName);
      final projectCodeFiles = <String, String>{};
      final projectAssetFiles = <String, String>{};
      final projectFolders = <String>{};
      final expandedFolders = <String>{};

      void addParents(String path) {
        var parent = _parentPath(path);
        while (parent.isNotEmpty) {
          projectFolders.add(parent);
          expandedFolders.add(parent);
          parent = _parentPath(parent);
        }
      }

      Future<void> ingestFile(String rawPath, List<int> entryBytes) async {
        final path = _normalizeProjectPath(rawPath);
        if (path.isEmpty) return;
        addParents(path);
        if (_isCodePath(path)) {
          projectCodeFiles[path] =
              utf8.decode(entryBytes, allowMalformed: true);
        } else {
          projectAssetFiles[path] =
              'data:${_mimeForPath(path)};base64,${base64Encode(entryBytes)}';
        }
      }

      if (entityType == FileSystemEntityType.directory) {
        final root = Directory(localPath);
        await for (final entity
            in root.list(recursive: true, followLinks: false)) {
          final relative =
              entity.path.substring(root.path.length).replaceAll('\\', '/');
          if (entity is Directory) {
            final folder = _normalizeProjectPath(relative);
            if (folder.isNotEmpty) {
              projectFolders.add(folder);
              addParents(folder);
              expandedFolders.add(folder);
            }
          } else if (entity is File) {
            await ingestFile(relative, await entity.readAsBytes());
          }
        }
      } else if (extension == 'zip') {
        final archive =
            ZipDecoder().decodeBytes(await File(localPath).readAsBytes());
        final archivePaths = archive.files
            .map((entry) =>
                _normalizeProjectPath(entry.name.replaceAll('\\', '/')))
            .where((path) => path.isNotEmpty)
            .toList();
        final roots = archivePaths.map((path) => path.split('/').first).toSet();
        final hasRootLevelFile = archive.files.any((entry) {
          if (!entry.isFile) return false;
          final path = _normalizeProjectPath(entry.name.replaceAll('\\', '/'));
          return path.isNotEmpty && !path.contains('/');
        });
        // GitHub ZIPs commonly wrap the real project in one package folder.
        // Treat that single wrapper as the selected project root so the tree
        // matches what the user sees after opening the extracted folder.
        final archiveWrapper =
            roots.length == 1 && !hasRootLevelFile ? roots.first : null;
        for (final entry in archive.files) {
          final rawPath = entry.name.replaceAll('\\', '/');
          var path = _normalizeProjectPath(rawPath);
          if (archiveWrapper != null) {
            path = path == archiveWrapper
                ? ''
                : path.startsWith('$archiveWrapper/')
                    ? path.substring(archiveWrapper.length + 1)
                    : path;
          }
          path = _normalizeProjectPath(path);
          if (path.isEmpty) continue;

          if (!entry.isFile || rawPath.endsWith('/')) {
            projectFolders.add(path);
            addParents(path);
            expandedFolders.add(path);
            continue;
          }

          await ingestFile(path, _archiveEntryBytes(entry));
        }
      } else if (const {'html', 'css', 'js'}.contains(extension)) {
        await ingestFile(fileName, await File(localPath).readAsBytes());
      } else {
        return;
      }

      final filesByType = <String, List<String>>{
        'HTML': <String>[],
        'CSS': <String>[],
        'JS': <String>[],
      };
      final filesMulti = <String, String>{};
      for (final entry in projectCodeFiles.entries) {
        final type = _extensionOf(entry.key) == 'css'
            ? 'CSS'
            : _extensionOf(entry.key) == 'js'
                ? 'JS'
                : 'HTML';
        filesByType[type]!.add(entry.key);
        filesMulti[entry.key] = entry.value;
      }
      for (final list in filesByType.values) {
        list.sort();
      }

      String activeFile(String type) {
        final paths = filesByType[type]!;
        if (type == 'HTML' && paths.contains('index.html')) {
          return 'index.html';
        }
        return paths.isEmpty ? '' : paths.first;
      }

      final activeFileNameByType = <String, String>{
        'HTML': activeFile('HTML'),
        'CSS': activeFile('CSS'),
        'JS': activeFile('JS'),
      };
      final files = <String, String>{
        'HTML': projectCodeFiles[activeFileNameByType['HTML']] ?? '',
        'CSS': projectCodeFiles[activeFileNameByType['CSS']] ?? '',
        'JS': projectCodeFiles[activeFileNameByType['JS']] ?? '',
      };
      final names = <String, String>{
        'HTML': activeFileNameByType['HTML'] ?? '',
        'CSS': activeFileNameByType['CSS'] ?? '',
        'JS': activeFileNameByType['JS'] ?? '',
      };

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => EditorScreen(
            initialCode: jsonEncode({
              'projectName': fileName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
              'externalProject': extension == 'zip' ||
                  entityType == FileSystemEntityType.directory,
              'files': files,
              'fileNames': names,
              'filesByType': filesByType,
              'filesMulti': filesMulti,
              'activeFileNameByType': activeFileNameByType,
              'projectFolders': projectFolders.toList(),
              'projectCodeFiles': projectCodeFiles,
              'projectAssetFiles': projectAssetFiles,
              'expandedFolders': expandedFolders.toList(),
            }),
            initialFileName: activeFileNameByType['HTML']!.isNotEmpty
                ? activeFileNameByType['HTML']
                : fileName,
          ),
        ),
      );
    } catch (e) {
      print("--- ERROR READING SHARED FILE: $e ---");
      _pendingSharedPath = filePath;
    } finally {
      _isOpeningSharedFile = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.code_rounded,
                  size: 70, color: Colors.blueAccent),
              const SizedBox(height: 15),
              const Text(
                'Web Development Platform',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Write your code, preview it instantly, and save easily',
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),

              // 1. Start Code Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label:
                      const Text('Start Code', style: TextStyle(fontSize: 15)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SavedProjectsScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 1.5. Drag and drop web builder Button (تم إضافته تحت زر Start مباشرة وبنفس التنسيق)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.dashboard_customize_rounded),
                  label: const Text('Drag and drop web builder',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const DragDropHomeScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 2. PDF to Website Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.grey),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.folder_shared_rounded),
                  label: const Text('PDF to Website',
                      style: TextStyle(fontSize: 15)),
                  onPressed: () {},
                ),
              ),
              const SizedBox(height: 12),

              // 3. Quick Builder Button
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueAccent,
                        side: const BorderSide(color: Colors.blueAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Quick Builder',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const SmartBuilderScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    const Center(
                      child: Text(
                        'Build visual designs instantly',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Store Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    side: const BorderSide(color: Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.store_rounded),
                  label: const Text('Store', style: TextStyle(fontSize: 15)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const StoreScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // --- LEARN & ABOUT BUTTONS ---
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.school_rounded, size: 18),
                      label:
                          const Text('Learn', style: TextStyle(fontSize: 13)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LearnScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label:
                          const Text('About', style: TextStyle(fontSize: 13)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AboutScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- SOCIAL MEDIA BUTTONS ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.facebook, color: Colors.blue),
                    onPressed: () => _launchURL(
                        'https://www.facebook.com/share/1MYBhRgfGD/'),
                    tooltip: 'Facebook',
                  ),
                  IconButton(
                    icon: const Icon(Icons.smart_display, color: Colors.red),
                    onPressed: () =>
                        _launchURL('https://www.youtube.com/@Sumerwebmaker'),
                    tooltip: 'YouTube',
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.alternate_email, color: Colors.white),
                    onPressed: () => _launchURL('https://x.com/sumerwebmaker'),
                    tooltip: 'X (Twitter)',
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.camera_alt, color: Colors.pinkAccent),
                    onPressed: () =>
                        _launchURL('https://www.instagram.com/sumerwebmaker/'),
                    tooltip: 'Instagram',
                  ),
                  IconButton(
                    icon: const Icon(Icons.telegram, color: Colors.lightBlue),
                    onPressed: () => _launchURL('https://t.me/sumerwebmaker'),
                    tooltip: 'Telegram',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
