import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';
import 'app_data.dart';
import 'game_data.dart';
import 'titled_text_filed.dart';

class LayoutGame extends StatefulWidget {
  const LayoutGame({super.key});

  @override
  LayoutGameState createState() => LayoutGameState();
}

class LayoutGameState extends State<LayoutGame> {
  late TextEditingController nameController;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final appData = Provider.of<AppData>(context, listen: false);
    nameController = TextEditingController(text: appData.gameData.name);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    nameController.dispose();
    super.dispose();
  }

  String _shortenFilePath(String path, {int maxLength = 35}) {
    if (path.length <= maxLength) return path;

    int keepLength =
        (maxLength / 2).floor(); // Part a mantenir a l'inici i al final
    return "${path.substring(0, keepLength)}...${path.substring(path.length - keepLength)}";
  }

  @override
  Widget build(BuildContext context) {
    final appData = Provider.of<AppData>(context);

    if (nameController.text != appData.gameData.name) {
      nameController.text = appData.gameData.name;
      nameController.selection =
          TextSelection.collapsed(offset: nameController.text.length);
    }

    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CDKText(
              'Game settings:',
              role: CDKTextRole.bodyStrong,
            ),
          ),
          Expanded(
            child: CupertinoScrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TitledTextfield(
                      title: 'Game name',
                      controller: nameController,
                      onChanged: (value) {
                        setState(() {
                          appData.gameData = GameData(
                            name: value,
                            levels: appData.gameData.levels,
                            levelGroups: appData.gameData.levelGroups,
                            mediaAssets: appData.gameData.mediaAssets,
                            mediaGroups: appData.gameData.mediaGroups,
                            animations: appData.gameData.animations,
                            animationGroups: appData.gameData.animationGroups,
                            zoneTypes: appData.gameData.zoneTypes,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const CDKText(
                      "Project path:",
                      role: CDKTextRole.bodyStrong,
                    ),
                    CDKText(
                      appData.filePath.isEmpty
                          ? "Project path not set"
                          : _shortenFilePath(appData.filePath),
                      role: CDKTextRole.body,
                      secondary: true,
                    ),
                    const SizedBox(height: 16),
                    const CDKText(
                      "File name:",
                      role: CDKTextRole.bodyStrong,
                    ),
                    CDKText(
                      appData.fileName.isEmpty
                          ? "File name not set"
                          : appData.fileName,
                      role: CDKTextRole.body,
                      secondary: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CDKButton(
                  style: CDKButtonStyle.action,
                  onPressed: appData.selectedProject == null
                      ? null
                      : () {
                          appData.reloadWorkingProject();
                        },
                  child: const Text('Reload'),
                ),
                CDKButton(
                  style: CDKButtonStyle.action,
                  onPressed: appData.selectedProject == null
                      ? null
                      : () {
                          appData.saveGame();
                        },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
