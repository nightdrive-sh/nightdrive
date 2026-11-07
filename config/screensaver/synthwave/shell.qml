// A Nightdrive screensaver, run by screensaver/start as its own Quickshell instance (qs -p this folder): the windows
// are ../SaverShell.qml, which shows this folder's face (also the lock's, greeter/LockSaver.qml). Loaded by path, as
// Quickshell doesn't import a folder above its own.
import Quickshell

ShellRoot {
    LazyLoader { active: true; source: Quickshell.shellDir + "/../SaverShell.qml" }
}
