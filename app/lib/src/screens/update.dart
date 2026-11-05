import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../controller.dart';

/// A newer release, offered above every screen until it is installed or put off: "Update and restart" for a copy that
/// installs it itself (not during a call), "Download" for one that cannot (the .deb, a Mac app its user cannot
/// replace).
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller});
  final Controller controller;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final u = controller.update;
    if (u == null || controller.updateDismissed == u.version) return const SizedBox.shrink();
    final downloading = controller.updateStatus == 'downloading';
    final failed = controller.updateStatus == 'failed';
    return MaterialBanner(
      key: const Key('update-banner'),
      leading: const Icon(Icons.system_update),
      content: Text(switch ((downloading, failed, u.canInstall, controller.inCall)) {
        (true, _, _, _) => s.updateDownloading(u.version),
        (_, true, _, _) => s.updateFailed(controller.updateError ?? ''),
        (_, _, false, _) => s.updateByHand(u.version, u.reason ?? ''),
        (_, _, true, true) => s.updateAfterCall(u.version),
        _ => s.updateAvailable(u.version),
      }),
      actions: [
        TextButton(onPressed: () => launchUrl(Uri.parse(u.notes)), child: Text(s.updateNotes)),
        TextButton(onPressed: downloading ? null : controller.dismissUpdate, child: Text(s.updateLater)),
        if (u.canInstall)
          FilledButton(
            onPressed: downloading || controller.inCall ? null : controller.installUpdate,
            child: Text(s.updateInstall),
          )
        else if (u.download != null)
          FilledButton(onPressed: () => launchUrl(Uri.parse(u.download!)), child: Text(s.updateDownload)),
      ],
    );
  }
}

/// This copy's version, a check by hand, and what it found.
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key, required this.controller});
  final Controller controller;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final u = controller.update;
    final status = switch (controller.updateStatus) {
      'checking' => s.updateChecking,
      'latest' => s.updateLatest,
      'downloading' => s.updateDownloading(u?.version ?? ''),
      'failed' => s.updateFailed(controller.updateError ?? ''),
      _ => u == null ? null : s.updateAvailable(u.version),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.settingsVersion(controller.client.appVersion()), key: const Key('app-version')),
        // A phone's store updates its app.
        if (controller.mobile == null) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              key: const Key('check-updates'),
              onPressed: controller.updateStatus == 'checking' || controller.updateStatus == 'downloading'
                  ? null
                  : controller.checkForUpdate,
              child: Text(s.updateCheck),
            ),
            if (status != null) Text(status, key: const Key('update-status')),
          ],
        ),
        ],
      ],
    );
  }
}
