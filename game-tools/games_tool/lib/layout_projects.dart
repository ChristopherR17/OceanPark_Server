import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';

import 'app_data.dart';

class LayoutProjects extends StatelessWidget {
  const LayoutProjects({super.key});

  @override
  Widget build(BuildContext context) {
    final AppData appData = Provider.of<AppData>(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);

    if (!appData.storageReady) {
      return const Center(child: CupertinoActivityIndicator());
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cdkColors.backgroundSecondary0,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CupertinoColors.systemGrey4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CDKText(
              "Add Existing Project",
              role: CDKTextRole.bodyStrong,
              color: CupertinoColors.black,
            ),
            const SizedBox(height: 4),
            const CDKText(
              "Choose a folder containing game_data.json and add it to the known projects list.",
              role: CDKTextRole.caption,
              color: CupertinoColors.black,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: CDKButton(
                style: CDKButtonStyle.action,
                onPressed: () async {
                  await appData.addExistingProjectFromFolder(
                    initialDirectory: appData.projectsPath,
                  );
                },
                child: const Text("Add Existing"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
