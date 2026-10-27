import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "stickyNotes"

    StringSetting {
        id: folderSetting

        settingKey: "notesFolder"
        label: "Notes folder"
        description: "Where notes.json is kept. Leave empty to use ~/.local/share/sticky-notes; a folder you choose here must already exist."
        placeholder: "~/.local/share/sticky-notes"
        onValueChanged: folderCheck.check()
    }

    Text {
        width: parent.width
        visible: folderCheck.result !== ""
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        font.family: Theme.fontFamily
        color: folderCheck.result === "ok" ? Theme.surfaceVariantText : Theme.error
        text: {
            switch (folderCheck.result) {
            case "ok":
                return "Folder found.";
            case "relative":
                return "Use an absolute path, or one starting with ~.";
            case "missing":
                return "This folder doesn't exist or isn't writable. Create it first; until then the stack shows an error.";
            }
            return "";
        }
    }

    Process {
        id: folderCheck

        property string result: ""
        property string path: ""

        function check() {
            const value = folderSetting.value.trim();
            running = false;
            if (!value) {
                result = "";
                return ;
            }
            path = value.replace(/^~(?=\/|$)/, Quickshell.env("HOME")).replace(/(.)\/+$/, "$1");
            if (!path.startsWith("/")) {
                result = "relative";
                return ;
            }
            running = true;
        }

        command: ["test", "-d", path, "-a", "-w", path]
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
