import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:share_plus/share_plus.dart';
import 'editor_screen.dart'; // تأكد من مطابقة اسم ملف الإيدتور عندك

class SavedProjectsScreen extends StatefulWidget {
  const SavedProjectsScreen({super.key});

  @override
  State<SavedProjectsScreen> createState() => _SavedProjectsScreenState();
}

class _SavedProjectsScreenState extends State<SavedProjectsScreen> {
  List<Map<String, String>> projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  // تحميل المشاريع المحفوظة من الـ SharedPreferences
  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedProjects = prefs.getStringList('projects_list') ?? [];

    if (!mounted) return;
    setState(() {
      projects = savedProjects.map((item) {
        List<String> parts = item.split('|||');
        return {
          'name': parts.isNotEmpty ? parts[0] : 'Untitled',
          'code': parts.length > 1 ? parts[1] : '',
        };
      }).toList();
    });
  }

  Future<void> _showCreateProjectDialog() async {
    final nameController = TextEditingController();
    String? validationError;
    bool isCreating = false;

    Future<void> createProject(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (isCreating) return;
      final projectName = nameController.text.trim();
      if (projectName.isEmpty) {
        setDialogState(() => validationError = 'Enter a project name.');
        return;
      }
      if (projectName.contains('|||')) {
        setDialogState(
          () => validationError = 'Project names cannot contain "|||".',
        );
        return;
      }

      isCreating = true;
      setDialogState(() {});
      final prefs = await SharedPreferences.getInstance();
      if (!dialogContext.mounted) return;
      final savedProjects = prefs.getStringList('projects_list') ?? [];
      final normalizedName = projectName.toLowerCase();
      final nameAlreadyExists = savedProjects.any((entry) {
        final separator = entry.indexOf('|||');
        final existingName =
            separator < 0 ? entry : entry.substring(0, separator);
        return existingName.trim().toLowerCase() == normalizedName;
      });

      if (nameAlreadyExists) {
        setDialogState(() {
          validationError = 'A project with this name already exists.';
          isCreating = false;
        });
        return;
      }

      // Reserve the name immediately. The editor loads its default starter
      // template because initialCode is omitted, then saves its project data
      // back into this entry when the user chooses Save.
      savedProjects.add('$projectName|||');
      await prefs.setStringList('projects_list', savedProjects);

      if (!mounted || !dialogContext.mounted) return;
      Navigator.pop(dialogContext, projectName);
    }

    final dialogNavigator = Navigator.of(context, rootNavigator: true);
    final dialogRoute = DialogRoute<String>(
      context: context,
      themes: InheritedTheme.capture(
        from: context,
        to: dialogNavigator.context,
      ),
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Create Project',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: nameController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Project Name',
              labelStyle: const TextStyle(color: Colors.grey),
              errorText: validationError,
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent),
              ),
            ),
            onChanged: (_) {
              if (validationError != null) {
                setDialogState(() => validationError = null);
              }
            },
            onSubmitted: (_) => createProject(dialogContext, setDialogState),
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: isCreating
                  ? null
                  : () => createProject(dialogContext, setDialogState),
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    final createdProjectName = await dialogNavigator.push(dialogRoute);
    // The route result can arrive before its reverse transition has removed
    // the dialog's inherited widgets. Wait for the route to finish disposing
    // before mounting the editor as the next screen.
    await dialogRoute.completed;

    nameController.dispose();

    // Open the editor only for a successfully created project.
    if (createdProjectName == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditorScreen(initialProjectName: createdProjectName),
      ),
    );
    if (mounted) _loadProjects();
  }

  // حذف مشروع نهائياً
  Future<void> _deleteProject(String projectName) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Confirm deletion',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this project?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Confirm',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    List<String> savedProjects = prefs.getStringList('projects_list') ?? [];

    savedProjects.removeWhere((p) => p.startsWith("$projectName|||"));
    await prefs.setStringList('projects_list', savedProjects);

    _loadProjects(); // إعادة تحميل القائمة لتحديث الواجهة

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Project deleted successfully!')),
    );
  }

  // دالة لتعديل اسم المشروع باستخدام زر القلم مع التحقق من التكرار
  void _showRenameDialog(String oldName, String currentCode) {
    TextEditingController nameController = TextEditingController(text: oldName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            const Text('Rename Project', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'New Project Name',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              String newName = nameController.text.trim();
              if (newName.isEmpty) return;

              final prefs = await SharedPreferences.getInstance();
              List<String> savedProjects =
                  prefs.getStringList('projects_list') ?? [];

              // التحقق إذا الاسم الجديد موجود مسبقاً (وليس هو نفس الاسم القديم)
              bool nameExists = savedProjects.any(
                  (p) => p.startsWith("$newName|||") && oldName != newName);

              if (nameExists) {
                if (!context.mounted) return;
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF2C2C2C),
                    title: const Text('Name Exists',
                        style: TextStyle(color: Colors.orangeAccent)),
                    content: const Text(
                        'A project with this name already exists! Please choose another name.',
                        style: TextStyle(color: Colors.white)),
                    actions: [
                      TextButton(
                        child: const Text('OK',
                            style: TextStyle(color: Colors.blueAccent)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                );
                return;
              }

              // حذف المشروع القديم وتحديثه بالاسم الجديد مع الحفاظ على الكود
              savedProjects.removeWhere((p) => p.startsWith("$oldName|||"));
              savedProjects.add("$newName|||$currentCode");
              await prefs.setStringList('projects_list', savedProjects);

              if (!context.mounted) return;
              Navigator.pop(context); // غلق نافذة التعديل
              _loadProjects(); // تحديث القائمة
            },
          ),
        ],
      ),
    );
  }

  // زر الرفع من ذاكرة الهاتف الحقيقية (Upload HTML File from Device)
  Future<void> _uploadExternalProject() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm', 'txt', 'zip'],
      );

      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        String fileName = result.files.single.name;
        final extension = fileName.toLowerCase().split('.').last;

        // إزالة امتداد الملف من الاسم ليتم عرضه بشكل نظيف
        if (fileName.contains('.')) {
          fileName = fileName.substring(0, fileName.lastIndexOf('.'));
        }

        final file = File(filePath);
        String initialCode;

        if (extension == 'zip') {
          final bytes = await file.readAsBytes();
          final archive = ZipDecoder().decodeBytes(bytes);
          final files = <String, String>{
            'HTML': '',
            'CSS': '',
            'JS': '',
          };
          final names = <String, String>{
            'HTML': 'index.html',
            'CSS': 'style.css',
            'JS': 'script.js',
          };

          // نأخذ أول ملف من كل نوع، مع تفضيل الأسماء الشائعة للمشاريع.
          final candidates = <String, List<ArchiveFile>>{
            'HTML': [],
            'CSS': [],
            'JS': [],
          };
          for (final entry in archive) {
            if (!entry.isFile) continue;
            final lowerName = entry.name.toLowerCase();
            final type =
                lowerName.endsWith('.html') || lowerName.endsWith('.htm')
                    ? 'HTML'
                    : lowerName.endsWith('.css')
                        ? 'CSS'
                        : lowerName.endsWith('.js')
                            ? 'JS'
                            : null;
            if (type != null) candidates[type]!.add(entry);
          }

          for (final type in ['HTML', 'CSS', 'JS']) {
            final entries = candidates[type]!;
            if (entries.isEmpty) continue;
            entries.sort((a, b) {
              int rank(ArchiveFile item) {
                final name = item.name.toLowerCase().split('/').last;
                if (type == 'HTML' && name == 'index.html') return 0;
                if (type == 'CSS' && name == 'style.css') return 0;
                if (type == 'JS' && name == 'script.js') return 0;
                return 1;
              }

              return rank(a).compareTo(rank(b));
            });
            final entry = entries.first;
            // في إصدارات archive الحالية محتوى الملف موجود داخل content.
            final entryBytes = entry.content as List<int>;
            files[type] = utf8.decode(entryBytes, allowMalformed: true);
            names[type] = entry.name.split('/').last;
          }

          if (files.values.every((content) => content.trim().isEmpty)) {
            throw Exception('ZIP لا يحتوي ملفات HTML أو CSS أو JS');
          }

          initialCode = jsonEncode({
            'projectName': fileName,
            'files': files,
            'fileNames': names,
          });
        } else {
          initialCode = await file.readAsString();
        }

        if (!mounted) return;
        // فتح الإيدتور مباشرة بالملف المرفوع من الذاكرة
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(
              initialFileName: fileName,
              initialCode: initialCode,
            ),
          ),
        ).then((_) => _loadProjects());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file: $e')),
      );
    }
  }

  Future<void> _shareProject(String projectName, String projectCode) async {
    try {
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(projectCode);
        data = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{
                'files': {'HTML': projectCode}
              };
      } catch (_) {
        data = <String, dynamic>{
          'files': {'HTML': projectCode}
        };
      }

      final rawFiles = data['files'];
      final rawNames = data['fileNames'];
      final files =
          rawFiles is Map ? rawFiles : <String, dynamic>{'HTML': projectCode};
      final names = rawNames is Map ? rawNames : <String, dynamic>{};
      final archive = Archive();

      final defaults = {
        'HTML': '$projectName.html',
        'CSS': 'style.css',
        'JS': 'script.js',
      };
      for (final type in ['HTML', 'CSS', 'JS']) {
        final content = files[type]?.toString() ?? '';
        if (content.trim().isEmpty) continue;
        final name = names[type]?.toString().trim().isNotEmpty == true
            ? names[type].toString()
            : defaults[type]!;
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      if (archive.files.isEmpty) throw Exception('المشروع فارغ');
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) throw Exception('تعذر إنشاء ملف ZIP');

      final tempDir = await getTemporaryDirectory();
      final safeName = projectName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final zipFile = File('${tempDir.path}/$safeName.zip');
      await zipFile.writeAsBytes(zipBytes, flush: true);

      await Share.shareXFiles(
        [XFile(zipFile.path, mimeType: 'application/zip')],
        text: 'مشروع $projectName',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ بالمشاركة: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text('Saved Projects',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // زر الرفع من الذاكرة الحقيقية
          IconButton(
            icon:
                const Icon(Icons.upload_file_rounded, color: Colors.blueAccent),
            tooltip: 'Upload HTML File from Device',
            onPressed: _uploadExternalProject,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SizedBox(
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
                icon: const Icon(Icons.add_rounded),
                label: const Text(
                  'Create Project',
                  style: TextStyle(fontSize: 15),
                ),
                onPressed: _showCreateProjectDialog,
              ),
            ),
          ),
          Expanded(
            child: projects.isEmpty
                ? const Center(
                    child: Text(
                      'No saved projects yet!',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    itemCount: projects.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        child: ListTile(
                          title: Text(
                            '${project['name']}.html',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'HTML, CSS, JS Project',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          // الضغط على الكارت يفتح المشروع للتعديل وبنفس الكود المخزون
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditorScreen(
                                  initialProjectName: project['name'],
                                  initialCode: project['code'],
                                ),
                              ),
                            ).then((_) => _loadProjects());
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // زر التعديل بالقلم (يفتح نافذة تغيير الاسم فقط)
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: Colors.amber, size: 20),
                                tooltip: 'Rename Project',
                                onPressed: () => _showRenameDialog(
                                    project['name']!, project['code']!),
                              ),
                              // زر الحذف
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.redAccent, size: 20),
                                tooltip: 'Delete Project',
                                onPressed: () =>
                                    _deleteProject(project['name']!),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_rounded,
                                    color: Colors.lightBlueAccent, size: 20),
                                tooltip: 'Share Project ZIP',
                                onPressed: () => _shareProject(
                                    project['name']!, project['code']!),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
