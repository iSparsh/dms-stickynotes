import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.FileBrowser
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "stickyNotes"

    // Picked with Dux's folder browser rather than typed, so the setting is
    // always a real, absolute folder.
    Column {
        id: folderSetting

        property string value: ""
        readonly property string home: Quickshell.env("HOME")

        function loadValue() {
            value = root.loadValue("notesFolder", "");
            folderCheck.check();
        }

        function choose(path) {
            let folder = String(path || "");
            if (folder.startsWith("file://"))
                folder = decodeURIComponent(folder.slice(7));

            value = folder.replace(/(.)\/+$/, "$1");
            root.saveValue("notesFolder", value);
            folderCheck.check();
        }

        width: parent.width
        spacing: Theme.spacingS
        Component.onCompleted: loadValue()

        Text {
            text: "Notes folder"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            font.family: Theme.fontFamily
            color: Theme.surfaceText
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Where notes.json is kept. Each stack can use its own folder."
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
            color: Theme.surfaceVariantText
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            Text {
                width: parent.width - chooseButton.width - (resetButton.visible ? resetButton.width + parent.spacing : 0) - parent.spacing
                height: chooseButton.height
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
                text: folderSetting.value ? folderSetting.value.replace(folderSetting.home, "~") : "~/.local/share/sticky-notes (default)"
                font.pixelSize: Theme.fontSizeMedium
                font.family: Theme.fontFamily
                color: Theme.surfaceText
            }

            DButton {
                id: resetButton

                visible: folderSetting.value !== ""
                text: "Use default"
                onClicked: folderSetting.choose("")
            }

            DButton {
                id: chooseButton

                text: "Choose…"
                onClicked: {
                    pickerLoader.active = true;
                    if (pickerLoader.item)
                        pickerLoader.item.open();

                }
            }

        }

        Text {
            width: parent.width
            visible: folderCheck.result === "missing"
            wrapMode: Text.WordWrap
            text: "This folder is no longer available or isn't writable. Choose another one or use the default."
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
            color: Theme.error
        }

    }

    Loader {
        id: pickerLoader

        active: false

        sourceComponent: Component {
            FileBrowserModal {
                browserTitle: "Choose notes folder"
                mode: "openFolder"
                startPath: folderSetting.value || folderSetting.home
                onAccepted: (paths) => {
                    if (paths.length > 0)
                        folderSetting.choose(paths[0]);

                }
            }

        }

    }

    Process {
        id: folderCheck

        property string result: ""

        function check() {
            running = false;
            result = "";
            if (folderSetting.value)
                running = true;

        }

        command: ["test", "-d", folderSetting.value, "-a", "-w", folderSetting.value]
        onExited: (code) => {
            return result = code === 0 ? "ok" : "missing";
        }
    }

    Column {
        id: fontSetting

        property string value: "Gochi Hand"
        property var families: []

        function loadValue() {
            value = root.loadValue("handwritingFont", "Gochi Hand");
        }

        width: parent.width
        spacing: Theme.spacingS
        Component.onCompleted: {
            loadValue();
            families = Qt.fontFamilies().filter((f) => {
                return !f.startsWith(".");
            }).sort();
        }

        DDropdown {
            width: parent.width
            text: "Handwriting font"
            description: "Used by notes in the handwriting style. Notes can also use your shell or monospace font."
            enableFuzzySearch: true
            currentValue: fontSetting.value
            options: fontSetting.families
            onValueChanged: (newValue) => {
                fontSetting.value = newValue;
                root.saveValue("handwritingFont", newValue);
            }
        }

    }

    SliderSetting {
        settingKey: "textSize"
        label: "Text size"
        description: "Note text size, relative to your shell font size."
        defaultValue: 100
        minimum: 70
        maximum: 160
        unit: "%"
    }

}
