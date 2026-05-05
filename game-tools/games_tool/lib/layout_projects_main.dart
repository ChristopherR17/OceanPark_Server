import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_cupertino_desktop_kit/flutter_cupertino_desktop_kit.dart';
import 'package:provider/provider.dart';

import 'app_data.dart';
import 'widgets/editor_form_dialog_scaffold.dart';
import 'widgets/editor_labeled_field.dart';

class LayoutProjectsMain extends StatefulWidget {
  const LayoutProjectsMain({super.key});

  @override
  State<LayoutProjectsMain> createState() => _LayoutProjectsMainState();
}

enum _MissingProjectAction { relink, remove }

enum _ProjectDeleteAction { deleteFolder, unlinkOnly }

class _LayoutProjectsMainState extends State<LayoutProjectsMain> {
  final GlobalKey _selectedEditAnchorKey = GlobalKey();
  bool _isResolvingMissingProjects = false;
  bool _missingProjectsResolutionScheduled = false;

  void _scheduleMissingProjectsResolution() {
    if (_missingProjectsResolutionScheduled || _isResolvingMissingProjects) {
      return;
    }
    _missingProjectsResolutionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _missingProjectsResolutionScheduled = false;
      await _resolveMissingProjects();
    });
  }

  Future<_MissingProjectAction?> _promptMissingProjectAction(
    String missingProjectPath,
    String missingProjectName,
  ) async {
    final CDKDialogController controller = CDKDialogController();
    final Completer<_MissingProjectAction?> completer =
        Completer<_MissingProjectAction?>();
    _MissingProjectAction? result;

    CDKDialogsManager.showModal(
      context: context,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: true,
      controller: controller,
      onHide: () {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      },
      child: _MissingProjectDialog(
        missingProjectName: missingProjectName,
        missingProjectPath: missingProjectPath,
        onRelink: () {
          result = _MissingProjectAction.relink;
          controller.close();
        },
        onRemove: () {
          result = _MissingProjectAction.remove;
          controller.close();
        },
        onCancel: controller.close,
      ),
    );

    return completer.future;
  }

  Future<void> _resolveMissingProjects() async {
    if (_isResolvingMissingProjects || !mounted) {
      return;
    }
    _isResolvingMissingProjects = true;
    final AppData appData = Provider.of<AppData>(context, listen: false);
    try {
      while (mounted) {
        final String? missingPath = appData.nextMissingProjectPath;
        if (missingPath == null) {
          break;
        }
        final String missingProjectName =
            appData.projectDisplayNameForPath(missingPath);

        final _MissingProjectAction? action =
            await _promptMissingProjectAction(missingPath, missingProjectName);
        if (!mounted || action == null) {
          break;
        }

        if (action == _MissingProjectAction.remove) {
          await appData.removeMissingProjectPath(missingPath);
          continue;
        }

        String? initialDirectory;
        try {
          final Directory missingDirectory = Directory(missingPath);
          if (await missingDirectory.exists()) {
            // If possible, open picker directly in the project folder to relink.
            initialDirectory = missingDirectory.path;
          } else {
            initialDirectory = missingDirectory.parent.path;
          }
        } catch (_) {}
        final String? replacementPath = await appData.pickDirectory(
          dialogTitle: "Relink project folder: $missingProjectName",
          initialDirectory: initialDirectory,
        );
        if (replacementPath == null) {
          break;
        }

        final bool relinked = await appData.relinkMissingProjectPath(
          missingProjectPath: missingPath,
          replacementProjectPath: replacementPath,
        );
        if (!relinked) {
          appData.projectStatusMessage =
              "Invalid folder. The selected path is not a valid project or is already linked.";
          appData.update();
        }
      }
    } finally {
      _isResolvingMissingProjects = false;
    }
  }

  Future<_ProjectDialogData?> _promptProjectData({
    required String title,
    required String confirmLabel,
    String initialName = '',
    String initialDescription = '',
    String? projectPath,
    String? editingProjectId,
    GlobalKey? anchorKey,
    bool useArrowedPopover = false,
    bool liveEditMode = false,
    Future<void> Function(String value)? onNameAutoSave,
    Future<void> Function(String value)? onDescriptionAutoSave,
    VoidCallback? onDelete,
    VoidCallback? onChangeFolder,
  }) async {
    final AppData appData = Provider.of<AppData>(context, listen: false);
    final Set<String> existingNames = appData.projects
        .where((project) => project.id != editingProjectId)
        .map((project) => project.name.trim().toLowerCase())
        .toSet();
    final CDKDialogController controller = CDKDialogController();
    final Completer<_ProjectDialogData?> completer =
        Completer<_ProjectDialogData?>();
    _ProjectDialogData? result;

    final Widget dialogChild = _ProjectFormDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialDescription: initialDescription,
      projectPath: projectPath,
      liveEditMode: liveEditMode,
      existingNames: existingNames,
      onNameAutoSave: onNameAutoSave,
      onDescriptionAutoSave: onDescriptionAutoSave,
      onConfirm: (value) {
        result = value;
        controller.close();
      },
      onCancel: controller.close,
      onDelete: onDelete == null
          ? null
          : () {
              controller.close();
              onDelete();
            },
      onChangeFolder: onChangeFolder == null
          ? null
          : () {
              controller.close();
              onChangeFolder();
            },
    );

    if (useArrowedPopover &&
        anchorKey != null &&
        anchorKey.currentContext != null) {
      CDKDialogsManager.showPopoverArrowed(
        context: context,
        anchorKey: anchorKey,
        isAnimated: true,
        animateContentResize: false,
        dismissOnEscape: true,
        dismissOnOutsideTap: true,
        showBackgroundShade: false,
        controller: controller,
        onHide: () {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        },
        child: dialogChild,
      );
    } else {
      CDKDialogsManager.showModal(
        context: context,
        dismissOnEscape: true,
        dismissOnOutsideTap: false,
        showBackgroundShade: true,
        controller: controller,
        onHide: () {
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        },
        child: dialogChild,
      );
    }

    return completer.future;
  }

  Future<void> _promptAndAddProject() async {
    final _ProjectDialogData? data = await _promptProjectData(
      title: "New empty project",
      confirmLabel: "Continue",
    );
    if (data == null || !mounted) {
      return;
    }

    final AppData appData = Provider.of<AppData>(context, listen: false);
    final String? workingDirectoryPath = await appData.pickDirectory(
      dialogTitle: "Select project root folder",
      initialDirectory: appData.projectsPath,
    );
    if (workingDirectoryPath == null || !mounted) {
      return;
    }

    await appData.createProject(
      projectName: data.name,
      projectDescription: data.description,
      workingDirectoryPath: workingDirectoryPath,
    );
  }

  Future<void> _promptAndEditProject(
    StoredProject project,
    GlobalKey anchorKey,
  ) async {
    String currentProjectId = project.id;
    String currentProjectName = project.name;
    String currentProjectDescription = project.description;
    await _promptProjectData(
      title: "Edit project",
      confirmLabel: "Save",
      initialName: project.name,
      initialDescription: project.description,
      projectPath: project.folderPath,
      editingProjectId: project.id,
      anchorKey: anchorKey,
      useArrowedPopover: true,
      liveEditMode: true,
      onNameAutoSave: (String value) async {
        final AppData appData = Provider.of<AppData>(context, listen: false);
        final bool updated = await appData.updateProjectInfo(
          currentProjectId,
          newName: value,
          newDescription: currentProjectDescription,
        );
        if (updated) {
          currentProjectName = value;
        }
      },
      onDescriptionAutoSave: (String value) async {
        final AppData appData = Provider.of<AppData>(context, listen: false);
        final bool updated = await appData.updateProjectInfo(
          currentProjectId,
          newName: currentProjectName,
          newDescription: value,
        );
        if (updated) {
          currentProjectDescription = value;
        }
      },
      onDelete: () async {
        final _ProjectDeleteAction? deleteAction =
            await _promptDeleteAction(project);
        if (deleteAction == null || !mounted) {
          return;
        }
        final AppData appData = Provider.of<AppData>(context, listen: false);
        await appData.deleteProject(
          project.id,
          deleteFolder: deleteAction == _ProjectDeleteAction.deleteFolder,
        );
      },
      onChangeFolder: () async {
        final AppData appData = Provider.of<AppData>(context, listen: false);
        final String? destinationRootPath = await appData.pickDirectory(
          dialogTitle: "Select new destination folder",
          initialDirectory: project.folderPath,
        );
        if (destinationRootPath == null || !mounted) {
          return;
        }
        final bool? keepOldFolder = await CDKDialogsManager.showConfirm(
          context: context,
          title: "Keep old project folder?",
          message:
              "The project will be copied to the new destination.\n\nChoose whether to keep or delete the previous folder.",
          confirmLabel: "Keep old folder",
          cancelLabel: "Delete old folder",
          showBackgroundShade: true,
        );
        if (keepOldFolder == null || !mounted) {
          return;
        }
        await appData.relocateProject(
          projectId: project.id,
          destinationRootPath: destinationRootPath,
          deleteOldFolderIfCopied: !keepOldFolder,
        );
        final String selectedId = appData.selectedProjectId.trim();
        if (selectedId.isNotEmpty) {
          currentProjectId = selectedId;
        }
      },
    );
  }

  Future<_ProjectDeleteAction?> _promptDeleteAction(
    StoredProject project,
  ) async {
    final CDKDialogController controller = CDKDialogController();
    final Completer<_ProjectDeleteAction?> completer =
        Completer<_ProjectDeleteAction?>();
    _ProjectDeleteAction? result;

    CDKDialogsManager.showModal(
      context: context,
      dismissOnEscape: true,
      dismissOnOutsideTap: true,
      showBackgroundShade: true,
      controller: controller,
      onHide: () {
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      },
      child: _DeleteProjectDialog(
        projectName: project.name,
        projectPath: project.folderPath,
        onDeleteFolder: () {
          result = _ProjectDeleteAction.deleteFolder;
          controller.close();
        },
        onUnlinkOnly: () {
          result = _ProjectDeleteAction.unlinkOnly;
          controller.close();
        },
        onCancel: controller.close,
      ),
    );
    return completer.future;
  }

  String _formatLastModified(String updatedAtRaw) {
    final DateTime? parsed = DateTime.tryParse(updatedAtRaw);
    if (parsed == null) {
      return "Last modified: unknown";
    }
    final DateTime local = parsed.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final String date =
        "${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}";
    final String time = "${twoDigits(local.hour)}:${twoDigits(local.minute)}";
    return "Last modified: $date $time";
  }

  @override
  Widget build(BuildContext context) {
    final AppData appData = Provider.of<AppData>(context);
    final cdkColors = CDKThemeNotifier.colorTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);

    if (!appData.storageReady) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (appData.hasMissingProjectPaths) {
      _scheduleMissingProjectsResolution();
    }

    if (appData.projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CDKText(
              'No projects found.\nCreate a new project or add an existing one.',
              textAlign: TextAlign.center,
              role: CDKTextRole.body,
              color: CupertinoColors.black,
            ),
            const SizedBox(height: 10),
            CDKButton(
              style: CDKButtonStyle.action,
              onPressed: _promptAndAddProject,
              child: const Text('+ Project'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              CDKText(
                'Projects',
                role: CDKTextRole.title,
                style: typography.title.copyWith(fontSize: 28),
              ),
              const Spacer(),
              CDKButton(
                style: CDKButtonStyle.action,
                onPressed: _promptAndAddProject,
                child: const Text('+ Project'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: appData.projects.length,
            itemBuilder: (context, index) {
              final StoredProject project = appData.projects[index];
              final bool isSelected = project.id == appData.selectedProjectId;
              return GestureDetector(
                onTap: () async {
                  await appData.openProject(project.id);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? CupertinoColors.systemBlue.withValues(alpha: 0.2)
                        : cdkColors.backgroundSecondary0,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.systemGrey4,
                      width: isSelected ? 1.3 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: isSelected ? 12 : 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CDKText(
                                project.name,
                                role: isSelected
                                    ? CDKTextRole.bodyStrong
                                    : CDKTextRole.body,
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 2),
                              CDKText(
                                _formatLastModified(project.updatedAt),
                                role: CDKTextRole.caption,
                                color: isSelected
                                    ? cdkColors.colorTextSecondary
                                    : cdkColors.colorText,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isSelected)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: CupertinoButton(
                            key: _selectedEditAnchorKey,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(20, 20),
                            onPressed: () async {
                              await _promptAndEditProject(
                                project,
                                _selectedEditAnchorKey,
                              );
                            },
                            child: Icon(
                              CupertinoIcons.ellipsis_circle,
                              size: 16,
                              color: cdkColors.colorText,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProjectDialogData {
  const _ProjectDialogData({
    required this.name,
    required this.description,
  });

  final String name;
  final String description;
}

class _ProjectFormDialog extends StatefulWidget {
  const _ProjectFormDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    this.initialDescription = '',
    this.projectPath,
    this.liveEditMode = false,
    required this.existingNames,
    this.onNameAutoSave,
    this.onDescriptionAutoSave,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
    this.onChangeFolder,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final String initialDescription;
  final String? projectPath;
  final bool liveEditMode;
  final Set<String> existingNames;
  final Future<void> Function(String value)? onNameAutoSave;
  final Future<void> Function(String value)? onDescriptionAutoSave;
  final ValueChanged<_ProjectDialogData> onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onChangeFolder;

  @override
  State<_ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<_ProjectFormDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initialDescription);
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();
  late String _lastSavedName = widget.initialName.trim();
  late String _lastSavedDescription = widget.initialDescription.trim();
  bool _savingName = false;
  bool _savingDescription = false;
  String? _errorText;

  bool get _isValid {
    final String cleaned = _nameController.text.trim();
    return cleaned.isNotEmpty &&
        !widget.existingNames.contains(cleaned.toLowerCase());
  }

  void _validateName(String value) {
    final String cleaned = value.trim();
    String? error;
    if (cleaned.isEmpty) {
      error = 'Project name is required.';
    } else if (widget.existingNames.contains(cleaned.toLowerCase())) {
      error = 'Another project is named like that.';
    }
    setState(() {
      _errorText = error;
    });
  }

  void _confirm() {
    final String cleaned = _nameController.text.trim();
    _validateName(cleaned);
    if (!_isValid) {
      return;
    }
    widget.onConfirm(
      _ProjectDialogData(
        name: cleaned,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  Future<void> _saveNameIfNeeded() async {
    if (!widget.liveEditMode || widget.onNameAutoSave == null || _savingName) {
      return;
    }
    final String cleaned = _nameController.text.trim();
    _validateName(cleaned);
    if (!_isValid || cleaned == _lastSavedName) {
      return;
    }
    setState(() {
      _savingName = true;
    });
    await widget.onNameAutoSave!(cleaned);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastSavedName = cleaned;
      _savingName = false;
    });
  }

  Future<void> _saveDescriptionIfNeeded() async {
    if (!widget.liveEditMode ||
        widget.onDescriptionAutoSave == null ||
        _savingDescription) {
      return;
    }
    final String cleaned = _descriptionController.text.trim();
    if (cleaned == _lastSavedDescription) {
      return;
    }
    setState(() {
      _savingDescription = true;
    });
    await widget.onDescriptionAutoSave!(cleaned);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastSavedDescription = cleaned;
      _savingDescription = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus) {
        _saveNameIfNeeded();
      }
    });
    _descriptionFocusNode.addListener(() {
      if (!_descriptionFocusNode.hasFocus) {
        _saveDescriptionIfNeeded();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    final typography = CDKThemeNotifier.typographyTokensOf(context);
    return EditorFormDialogScaffold(
      title: widget.title,
      description: widget.liveEditMode ? '' : 'Set project details.',
      confirmLabel: widget.confirmLabel,
      confirmEnabled: _isValid,
      onConfirm: _confirm,
      onCancel: widget.onCancel,
      liveEditMode: widget.liveEditMode,
      onDelete: widget.onDelete,
      headerTrailing: widget.onDelete == null
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(20, 20),
              onPressed: widget.onDelete,
              child: const Icon(
                CupertinoIcons.trash,
                size: 16,
                color: CupertinoColors.systemGrey,
              ),
            ),
      minWidth: 340,
      maxWidth: 460,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorLabeledField(
            label: 'Project name',
            child: CDKFieldText(
              placeholder: 'Project name',
              controller: _nameController,
              focusNode: _nameFocusNode,
              onChanged: _validateName,
              onSubmitted: (_) {
                if (widget.liveEditMode) {
                  _saveNameIfNeeded();
                  return;
                }
                _confirm();
              },
            ),
          ),
          SizedBox(height: spacing.sm),
          EditorLabeledField(
            label: 'Project description',
            child: SizedBox(
              height: 66,
              child: CDKFieldText(
                placeholder: 'Project description',
                controller: _descriptionController,
                focusNode: _descriptionFocusNode,
                keyboardType: TextInputType.multiline,
                maxLines: null,
              ),
            ),
          ),
          if (widget.liveEditMode && (_savingName || _savingDescription)) ...[
            SizedBox(height: spacing.xs),
            const CDKText(
              'Saving...',
              role: CDKTextRole.caption,
              secondary: true,
            ),
          ],
          if (_errorText != null) ...[
            SizedBox(height: spacing.xs),
            CDKText(
              _errorText!,
              role: CDKTextRole.caption,
              color: CupertinoColors.systemRed,
            ),
          ],
          if (widget.onChangeFolder != null &&
              widget.projectPath != null &&
              widget.projectPath!.trim().isNotEmpty) ...[
            SizedBox(height: spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.projectPath!,
                    style: typography.caption,
                    softWrap: true,
                  ),
                ),
                SizedBox(width: spacing.sm),
                CDKButton(
                  style: CDKButtonStyle.normal,
                  onPressed: widget.onChangeFolder,
                  child: const Text('Change Folder Destination'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MissingProjectDialog extends StatelessWidget {
  const _MissingProjectDialog({
    required this.missingProjectName,
    required this.missingProjectPath,
    required this.onRelink,
    required this.onRemove,
    required this.onCancel,
  });

  final String missingProjectName;
  final String missingProjectPath;
  final VoidCallback onRelink;
  final VoidCallback onRemove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 360, maxWidth: 500),
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CDKText(
              'Project "$missingProjectName" needs relink',
              role: CDKTextRole.bodyStrong,
            ),
            SizedBox(height: spacing.sm),
            const CDKText(
              "Stored project folder is no longer accessible:",
              role: CDKTextRole.body,
            ),
            SizedBox(height: spacing.xs),
            CDKText(
              missingProjectPath,
              role: CDKTextRole.caption,
              secondary: true,
            ),
            SizedBox(height: spacing.md),
            CDKText(
              'Relink "$missingProjectName" to a valid project folder, or remove it from the list.',
              role: CDKTextRole.body,
            ),
            SizedBox(height: spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CDKButton(
                  style: CDKButtonStyle.normal,
                  onPressed: onCancel,
                  child: const Text("Later"),
                ),
                SizedBox(width: spacing.sm),
                CDKButton(
                  style: CDKButtonStyle.destructive,
                  onPressed: onRemove,
                  child: const Text("Remove"),
                ),
                SizedBox(width: spacing.sm),
                CDKButton(
                  style: CDKButtonStyle.action,
                  onPressed: onRelink,
                  child: const Text("Relink"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteProjectDialog extends StatelessWidget {
  const _DeleteProjectDialog({
    required this.projectName,
    required this.projectPath,
    required this.onDeleteFolder,
    required this.onUnlinkOnly,
    required this.onCancel,
  });

  final String projectName;
  final String projectPath;
  final VoidCallback onDeleteFolder;
  final VoidCallback onUnlinkOnly;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final spacing = CDKThemeNotifier.spacingTokensOf(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 420, maxWidth: 560),
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CDKText(
              'Delete "$projectName"',
              role: CDKTextRole.bodyStrong,
            ),
            SizedBox(height: spacing.sm),
            const CDKText(
              'Choose what to do with the project folder contents:',
              role: CDKTextRole.body,
            ),
            SizedBox(height: spacing.xs),
            CDKText(
              projectPath,
              role: CDKTextRole.caption,
              secondary: true,
            ),
            SizedBox(height: spacing.md),
            const CDKText(
              'Delete folder: remove project from list and permanently delete the folder and files.',
              role: CDKTextRole.caption,
              secondary: true,
            ),
            SizedBox(height: spacing.xs),
            const CDKText(
              'Unlink only: remove project from list but keep folder and files on disk.',
              role: CDKTextRole.caption,
              secondary: true,
            ),
            SizedBox(height: spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CDKButton(
                  style: CDKButtonStyle.normal,
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
                SizedBox(width: spacing.sm),
                CDKButton(
                  style: CDKButtonStyle.normal,
                  onPressed: onUnlinkOnly,
                  child: const Text('Unlink Only'),
                ),
                SizedBox(width: spacing.sm),
                CDKButton(
                  style: CDKButtonStyle.destructive,
                  onPressed: onDeleteFolder,
                  child: const Text('Delete Folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
