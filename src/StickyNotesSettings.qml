import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "stickyNotes"

    StringSetting {
        settingKey: "notesFolder"
        label: "Notes folder"
        description: "Where notes.json is kept. Leave empty to use ~/.local/share/sticky-notes."
        placeholder: "~/.local/share/sticky-notes"
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
