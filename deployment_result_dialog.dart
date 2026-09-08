import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showDeploymentResultDialog(
  BuildContext context, {
  required String url,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DeploymentResultDialog(url: url),
  );
}

class DeploymentResultDialog extends StatelessWidget {
  const DeploymentResultDialog({
    super.key,
    required this.url,
  });

  final String url;

  Future<void> _openBrowser(BuildContext context) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_done_rounded,
                color: Colors.greenAccent, size: 52),
            const SizedBox(height: 12),
            const Text(
              'Deployment Successful!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your website is live at:',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 14),
            SelectableText(
              url,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Link'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openBrowser(context),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Open in Browser'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.cyanAccent,
                side: const BorderSide(color: Colors.cyanAccent),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}