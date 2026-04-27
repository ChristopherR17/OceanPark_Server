# games_tool

cd games_tool
flutter config --enable-macos-desktop
flutter pub get
flutter run -d macos

## Projects Storage

Projects are stored in the OS app-data location under an app-managed folder:

- macOS: `~/Library/Application Support/GamesTool/projects`
- Linux: `~/.local/share/GamesTool/projects` (or `$XDG_DATA_HOME/GamesTool/projects`)
- Windows: `%APPDATA%\\GamesTool\\projects`

The editor keeps a registry in:

- `.../GamesTool/projects_index.json`

Use the **Projects** section as follows:

- main area: choose the working project from the list
- main area: create new empty projects with `+ Add Project`
- main area: rename by clicking project name (inline edit) and click outside to save
- main area: delete selected project with the trash icon
- sidebar: import/export project archives (`.zip`)
