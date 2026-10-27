import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property var pluginService: null
    property string pluginId: ""
    property string instanceId: ""
    property var instanceData: null
    property var screen: null
    property bool acceptsKeyboardFocus: true
    property real widgetWidth: 300
    property real widgetHeight: 320
    property real defaultWidth: 300
    property real defaultHeight: 320
    property real minWidth: 220
    property real minHeight: 220
    property var notes: []
    property int current: 0
    property bool ready: false
    property string problem: ""
    property string lastWritten: ""
    property var trash: null
    property var deskIds: []
    property var hitRegions: []
    property int settingsRevision: 0
    // Pointer gestures that start on the stack surface. The stack itself never
    // moves mid-gesture, so its local coordinates stay stable; the desk surface
    // draws the moving preview and the result is applied on release.
    property bool movingStack: false
    property point stackDelta: Qt.point(0, 0)
    property bool tearing: false
    property point tearPos: Qt.point(0, 0)
    property bool dropHover: false
    readonly property var colors: ["#fff1a8", "#ffd1d3", "#cfeccf", "#cfe7f6", "#e4d8f5", "#fbe1c3"]
    readonly property var fonts: ["Gochi Hand", "Sans Serif", "Monospace"]
    readonly property var fontLabels: ["Handwriting", "Shell font", "Mono"]
    readonly property string handFont: setting("handwritingFont", "Gochi Hand") || "Gochi Hand"
    readonly property real textScale: setting("textSize", 100) / 100
    readonly property string notesFolder: resolveFolder(setting("notesFolder", ""))
    readonly property color ink: "#3f3528"
    readonly property real band: Theme.iconSize + Theme.spacingXS
    readonly property real buttonSize: Theme.iconSize + Theme.spacingXXS
    readonly property real margin: Theme.spacingM
    readonly property real sheetWidth: 240
    readonly property real sheetHeight: 240
    readonly property var stackNotes: notes.filter((n) => {
        return !n.detached;
    })
    readonly property var activeNote: stackNotes.length ? stackNotes[Math.max(0, Math.min(current, stackNotes.length - 1))] : null
    readonly property string activeId: activeNote ? activeNote.id : ""
    readonly property string activeText: activeNote ? activeNote.text : ""
    readonly property bool chrome: hover.hovered || editor.editing
    // Dux's content loader is our parent and carries the widget geometry, which
    // gives the stack's on-screen origin and Dux's own position saving.
    readonly property var hostGeometry: parent && parent.geometry !== undefined ? parent.geometry : null
    readonly property point stackOrigin: hostGeometry ? Qt.point(hostGeometry.widgetX, hostGeometry.widgetY) : Qt.point(0, 0)
    // The part of the screen left after panels (Dux's bar, docks, or any other
    // layer-shell client) reserve their exclusive zones. A probe surface that
    // honours those zones reports the size; Dux's bar and dock settings tell
    // which edge the space came from.
    readonly property rect workArea: {
        const sw = screen ? screen.width : 1920;
        const sh = screen ? screen.height : 1080;
        const w = probe.width > 0 ? Math.min(probe.width, sw) : sw;
        const h = probe.height > 0 ? Math.min(probe.height, sh) : sh;
        const edges = reservedEdges();
        return Qt.rect(startInset(sw - w, edges.left, edges.right), startInset(sh - h, edges.top, edges.bottom), w, h);
    }

    function noteById(id) {
        return notes.find((n) => {
            return n.id === id;
        }) || null;
    }

    // Per-instance settings, falling back to the plugin-wide ones.
    function setting(key, fallback) {
        void instanceData;
        void settingsRevision;
        return pluginService ? pluginService.loadPluginData(pluginId, key, fallback) : fallback;
    }

    function resolveFolder(path) {
        const home = Quickshell.env("HOME");
        if (!path)
            return (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/sticky-notes";

        return path.trim().replace(/^~(?=\/|$)/, home).replace(/\/+$/, "");
    }

    function openStore() {
        if (saveTimer.running)
            persist();

        ready = false;
        notes = [];
        lastWritten = "";
        problem = "";
        store.path = "";
        makeFolder.running = false;
        makeFolder.running = true;
    }

    function fontFamily(name) {
        if (name === "Sans Serif")
            return Theme.fontFamily;

        if (name === "Monospace")
            return Theme.monoFontFamily;

        return handFont;
    }

    function fontSize(name) {
        const base = name === "Sans Serif" || name === "Monospace" ? Theme.fontSizeLarge : Theme.fontSizeXLarge;
        return Math.round(base * textScale);
    }

    function nextFont(name) {
        return fonts[(Math.max(0, fonts.indexOf(name)) + 1) % fonts.length];
    }

    function tiltFor(id) {
        let hash = 0;
        for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) % 997
        return (hash % 5 - 2) * 0.7;
    }

    function topZ() {
        return notes.reduce((z, n) => {
            return Math.max(z, n.z || 0);
        }, 0);
    }

    function update(id, changes) {
        const index = notes.findIndex((n) => {
            return n.id === id;
        });
        if (index < 0)
            return ;

        const copy = notes.slice();
        copy[index] = Object.assign({
        }, copy[index], changes);
        notes = copy;
        saveTimer.restart();
    }

    function persist() {
        if (!ready)
            return ;

        saveTimer.stop();
        // Nothing was loaded and nothing has been written yet, so an empty
        // save could only overwrite a file this stack never saw.
        if (!lastWritten && !notes.length)
            return ;

        lastWritten = JSON.stringify({
            "version": 1,
            "notes": notes
        }, null, 2) + "\n";
        store.setText(lastWritten);
    }

    function addNote(text) {
        if (!ready)
            return ;

        // A blank sheet is already waiting; don't pile up empty ones.
        if (activeNote && !activeNote.text.trim() && !text) {
            editor.forceActiveFocus();
            return ;
        }
        const copy = notes.slice();
        copy.push({
            "id": Date.now().toString(36) + Math.random().toString(36).slice(2),
            "text": text || "",
            "color": activeNote ? colors[(colors.indexOf(activeNote.color) + 1) % colors.length] : colors[0],
            "font": activeNote ? activeNote.font : fonts[0]
        });
        notes = copy;
        current = stackNotes.length - 1;
        persist();
        editor.forceActiveFocus();
        if (text)
            editor.cursorPosition = text.length;

    }

    function deleteNote(id) {
        const index = notes.findIndex((n) => {
            return n.id === id;
        });
        if (index < 0)
            return ;

        trash = {
            "note": notes[index],
            "index": index
        };
        const copy = notes.slice();
        copy.splice(index, 1);
        notes = copy;
        current = Math.max(0, Math.min(current, stackNotes.length - 1));
        persist();
        undoTimer.restart();
    }

    function undoDelete() {
        if (!trash)
            return ;

        const copy = notes.slice();
        copy.splice(Math.min(trash.index, copy.length), 0, trash.note);
        notes = copy;
        if (!trash.note.detached)
            current = stackNotes.findIndex((n) => {
            return n.id === trash.note.id;
        });

        trash = null;
        undoTimer.stop();
        persist();
    }

    function navigate(offset) {
        const target = Math.max(0, Math.min(stackNotes.length - 1, current + offset));
        if (target === current)
            return ;

        if (saveTimer.running)
            persist();

        current = target;
        pageIn.offset = offset * 14;
        pageIn.restart();
    }

    // Which edges Dux's own bars and docks reserve, and how much where known.
    function reservedEdges() {
        const edges = ["top", "bottom", "left", "right"];
        const found = {
        };
        edges.forEach((e) => {
            return found[e] = {
                "bar": false,
                "dock": 0
            };
        });
        try {
            for (const bar of SettingsData.barConfigs) {
                if (bar.enabled && (bar.visible ?? true) && !bar.autoHide && SettingsData.barConfigCoversScreen(bar, screen))
                    found[edges[[0, 1, 2, 3, 0, 1][bar.position] ?? 0]].bar = true;

            }
            edges.forEach((e) => {
                return found[e].dock = SettingsData.dockReservationForEdge(screen, e) || 0;
            });
        } catch (error) {
        }
        return found;
    }

    // How much of an axis's reserved space sits at its start (top or left) edge.
    function startInset(total, start, end) {
        const atStart = start.bar || start.dock > 0;
        const atEnd = end.bar || end.dock > 0;
        if (total <= 0 || (atEnd && !atStart))
            return 0;

        if (!atEnd)
            return total;

        if (!end.bar)
            return Math.max(0, total - end.dock);

        if (!start.bar)
            return Math.min(total, start.dock);

        return total / 2;
    }

    // Keep a w×h box inside the work area.
    function clampToArea(x, y, w, h) {
        // A small gap so a tilted sheet's corner doesn't touch a panel.
        const gap = 6;
        const a = workArea;
        return Qt.point(Math.max(a.x + gap, Math.min(x, a.x + a.width - w - gap)), Math.max(a.y + gap, Math.min(y, a.y + a.height - h - gap)));
    }

    function detachAt(id, x, y) {
        if (!screen)
            return ;

        const index = stackNotes.findIndex((n) => {
            return n.id === id;
        });
        update(id, {
            "detached": true,
            "x": Math.round(clampToArea(x, y, sheetWidth, sheetHeight).x),
            "y": Math.round(clampToArea(x, y, sheetWidth, sheetHeight).y),
            "w": noteById(id).w || sheetWidth,
            "h": noteById(id).h || sheetHeight,
            "z": topZ() + 1
        });
        current = Math.max(0, Math.min(index, stackNotes.length - 1));
        persist();
    }

    function peelBeside(id) {
        // Place the sheet next to the stack, on whichever side has room.
        const right = stackOrigin.x + width + 8;
        const x = right + sheetWidth <= workArea.x + workArea.width ? right : stackOrigin.x - sheetWidth - 8;
        detachAt(id, x, stackOrigin.y + margin);
    }

    function returnToStack(id) {
        update(id, {
            "detached": false
        });
        current = Math.max(0, stackNotes.findIndex((n) => {
            return n.id === id;
        }));
        persist();
    }

    function stackDrop() {
        const g = hostGeometry;
        const p = g.dragMoveTo(g.widgetX, g.widgetY, stackDelta.x, stackDelta.y);
        // The transparent shadow margin may overlap a panel; the paper may not.
        const c = clampToArea(p.x + margin, p.y + margin, width - 2 * margin, height - 2 * margin);
        return Qt.point(c.x - margin, c.y - margin);
    }

    function overStack(cx, cy) {
        return cx >= stackOrigin.x && cx <= stackOrigin.x + width && cy >= stackOrigin.y && cy <= stackOrigin.y + height;
    }

    function syncEditor() {
        editor.syncing = true;
        editor.text = activeText;
        editor.syncing = false;
    }

    onActiveIdChanged: syncEditor()
    onNotesFolderChanged: openStore()
    onActiveTextChanged: {
        if (!editor.editing && editor.text !== activeText)
            syncEditor();

    }
    onNotesChanged: {
        const ids = notes.filter((n) => {
            return n.detached;
        }).map((n) => {
            return n.id;
        });
        if (ids.join() !== deskIds.join())
            deskIds = ids;

    }
    Component.onDestruction: {
        if (saveTimer.running)
            persist();

    }

    Timer {
        id: saveTimer

        interval: 600
        onTriggered: root.persist()
    }

    Timer {
        id: undoTimer

        interval: 6000
        onTriggered: root.trash = null
    }

    Connections {
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.settingsRevision++;

        }

        target: root.pluginService
        enabled: root.pluginService !== null
    }

    Process {
        id: makeFolder

        command: ["mkdir", "-p", root.notesFolder]
        running: true
        onExited: (code) => {
            if (code === 0)
                store.path = root.notesFolder + "/notes.json";
            else
                root.problem = "Couldn't create the notes folder";
        }
    }

    FileView {
        id: store

        path: ""
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const raw = text();
            // Our own write echoing back, or another stack's change arriving
            // while we still have unsaved edits (ours win on the next save).
            if (raw === root.lastWritten || (root.ready && saveTimer.running))
                return ;

            try {
                const data = JSON.parse(raw);
                if (data.version !== 1 || !Array.isArray(data.notes) || !data.notes.every((n) => {
                    return n && typeof n.id === "string" && typeof n.text === "string" && typeof n.color === "string" && typeof n.font === "string";
                }))
                    throw new Error("Invalid notes format");

                root.lastWritten = raw;
                root.notes = data.notes;
                root.current = Math.max(0, Math.min(root.current, root.stackNotes.length - 1));
                root.ready = true;
                root.problem = "";
            } catch (error) {
                root.problem = "Couldn't read notes.json — left it untouched";
                console.warn("Sticky Notes: " + error);
            }
        }
        onLoadFailed: (error) => {
            // A missing file is a fresh start; the first save creates it.
            if (error === FileViewError.FileNotFound) {
                root.ready = true;
                root.problem = "";
            } else {
                root.problem = "Couldn't read notes.json";
            }
        }
        onSaved: root.problem = ""
        onSaveFailed: root.problem = "Couldn't save — check folder permissions"
    }

    HoverHandler {
        id: hover
    }

    Item {
        id: stack

        anchors.fill: parent
        anchors.margins: root.margin
        opacity: root.movingStack ? 0.3 : 1

        // Sheets underneath, tinted with the notes that are actually below.
        Repeater {
            model: Math.max(0, Math.min(2, root.stackNotes.length - 1))

            Sheet {
                required property int index

                anchors.fill: parent
                z: -index - 1
                band: false
                rotation: index === 0 ? 1.4 : -2
                paper: root.stackNotes[(root.current + index + 1) % root.stackNotes.length].color
            }

        }

        Sheet {
            id: top

            anchors.fill: parent
            paper: root.activeNote ? root.activeNote.color : root.colors[0]

            NumberAnimation {
                id: pageIn

                property real offset: 0

                target: pageShift
                property: "x"
                from: offset
                to: 0
                duration: 170
                easing.type: Easing.OutCubic
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadiusXXS
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0.25, 0.2, 0.1, 0.35)
                visible: root.dropHover
            }

            // Adhesive band: drag to move the stack, scroll to flip sheets.
            MouseArea {
                id: grip

                property point pressAt

                width: parent.width
                height: root.band
                cursorShape: pressed && root.movingStack ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: (mouse) => {
                    return pressAt = Qt.point(mouse.x, mouse.y);
                }
                onPositionChanged: (mouse) => {
                    const dx = mouse.x - pressAt.x;
                    const dy = mouse.y - pressAt.y;
                    if (!root.movingStack && Math.hypot(dx, dy) > 6)
                        root.movingStack = !!root.hostGeometry;

                    if (root.movingStack)
                        root.stackDelta = Qt.point(dx, dy);

                }
                onReleased: {
                    if (root.movingStack) {
                        const g = root.hostGeometry;
                        const p = root.stackDrop();
                        g.savePosition(p.x, p.y);
                    }
                    root.movingStack = false;
                }
                onCanceled: root.movingStack = false
                onWheel: (wheel) => {
                    return root.navigate(wheel.angleDelta.y > 0 ? -1 : 1);
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXS
                y: (root.band - root.buttonSize) / 2
                spacing: 0

                IconButton {
                    icon: "chevron_left"
                    tip: "Previous note"
                    visible: root.chrome && root.stackNotes.length > 1
                    enabled: root.current > 0
                    onClicked: root.navigate(-1)
                }

                Text {
                    height: root.buttonSize
                    leftPadding: Theme.spacingXXS
                    rightPadding: Theme.spacingXXS
                    verticalAlignment: Text.AlignVCenter
                    visible: root.stackNotes.length > 1
                    text: (root.current + 1) + " / " + root.stackNotes.length
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: root.ink
                    opacity: 0.55
                }

                IconButton {
                    icon: "chevron_right"
                    tip: "Next note"
                    visible: root.chrome && root.stackNotes.length > 1
                    enabled: root.current < root.stackNotes.length - 1
                    onClicked: root.navigate(1)
                }

                IconButton {
                    icon: "add"
                    tip: "New note (Ctrl+N)"
                    visible: root.chrome
                    enabled: root.ready
                    onClicked: root.addNote("")
                }

            }

            DTextEdit {
                id: editor

                property bool syncing: false
                property bool editing: false

                enabled: root.ready
                backgroundColor: "transparent"
                borderWidth: 0
                focusedBorderWidth: 0
                topPadding: Theme.spacingXS
                textColor: root.ink
                placeholderColor: Qt.rgba(0.25, 0.2, 0.15, 0.45)
                hidePlaceholderOnFocus: false
                font.family: root.fontFamily(root.activeNote ? root.activeNote.font : root.fonts[0])
                font.pixelSize: root.fontSize(root.activeNote ? root.activeNote.font : root.fonts[0])
                placeholderText: !root.ready ? (root.problem || "Opening notes…") : root.activeNote ? "Write something…" : "Start typing to add a note"
                keyForwardTargets: [editorKeys]
                onFocusStateChanged: (hasFocus) => {
                    return editing = hasFocus;
                }
                onTextEdited: {
                    if (syncing || !editing)
                        return ;

                    if (root.activeNote)
                        root.update(root.activeId, {
                        "text": text
                    });
                    else if (text.length)
                        root.addNote(text);
                }

                anchors {
                    fill: parent
                    topMargin: root.band
                    bottomMargin: root.band + Theme.spacingS
                }

            }

            Item {
                id: editorKeys

                Keys.onPressed: (event) => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Escape)
                        editor.setFocus(false);
                    else if (ctrl && event.key === Qt.Key_N)
                        root.addNote("");
                    else if (ctrl && event.key === Qt.Key_PageUp)
                        root.navigate(-1);
                    else if (ctrl && event.key === Qt.Key_PageDown)
                        root.navigate(1);
                    else if (ctrl && event.key === Qt.Key_S)
                        root.persist();
                    else
                        return ;
                    event.accepted = true;
                }
            }

            Row {
                height: root.buttonSize
                spacing: Theme.spacingXXS
                visible: root.chrome && !!root.activeNote && !root.trash

                anchors {
                    left: parent.left
                    leftMargin: Theme.spacingS
                    bottom: parent.bottom
                    bottomMargin: Theme.spacingXS
                }

                Swatches {
                    anchors.verticalCenter: parent.verticalCenter
                    selected: root.activeNote ? root.activeNote.color : ""
                    onPicked: (color) => {
                        return root.update(root.activeId, {
                            "color": color
                        });
                    }
                }

                Item {
                    width: Theme.spacingXS
                    height: 1
                }

                IconButton {
                    icon: "text_fields"
                    tip: root.activeNote ? "Font: " + root.fontLabels[root.fonts.indexOf(root.nextFont(root.activeNote.font))] : ""
                    onClicked: root.update(root.activeId, {
                        "font": root.nextFont(root.activeNote.font)
                    })
                }

                IconButton {
                    icon: "delete"
                    tip: "Delete note"
                    onClicked: root.deleteNote(root.activeId)
                }

            }

            // Undo / problem banner, in place of the toolbar.
            Rectangle {
                height: root.buttonSize
                radius: height / 2
                color: Theme.inverseSurface
                visible: !!root.trash || (root.problem !== "" && root.ready)

                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    margins: Theme.spacingXS
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: undo.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.trash ? "Note deleted" : root.problem
                    elide: Text.ElideRight
                    color: Theme.inverseOnSurface
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                }

                Text {
                    id: undo

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!root.trash
                    text: "Undo"
                    color: Theme.inversePrimary
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.spacingS
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.undoDelete()
                    }

                }

            }

            // Dog-ear: drag it to tear the sheet off; click to peel it beside the stack.
            Item {
                id: corner

                property real extent: peel.containsMouse || peel.pressed ? 45 : 27

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: extent
                height: extent
                visible: !!root.activeNote && !root.trash

                Canvas {
                    id: fold

                    property color paper: top.paper
                    property color under: root.stackNotes.length > 1 ? root.stackNotes[(root.current + 1) % root.stackNotes.length].color : Qt.darker(top.paper, 1.18)

                    anchors.fill: parent
                    onPaperChanged: requestPaint()
                    onUnderChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d");
                        const s = width;
                        c.reset();
                        // What's revealed beneath the lifted corner.
                        c.fillStyle = under;
                        c.beginPath();
                        c.moveTo(s, 0);
                        c.lineTo(s, s);
                        c.lineTo(0, s);
                        c.closePath();
                        c.fill();
                        // The back of the folded flap.
                        const g = c.createLinearGradient(0, 0, s, s);
                        g.addColorStop(0, Qt.darker(paper, 1.04));
                        g.addColorStop(1, Qt.darker(paper, 1.16));
                        c.fillStyle = g;
                        c.beginPath();
                        c.moveTo(0, 0);
                        c.lineTo(s, 0);
                        c.lineTo(0, s);
                        c.closePath();
                        c.fill();
                        c.strokeStyle = Qt.rgba(0.2, 0.15, 0.05, 0.18);
                        c.lineWidth = 1;
                        c.beginPath();
                        c.moveTo(s, 0);
                        c.lineTo(0, s);
                        c.stroke();
                    }
                }

                MouseArea {
                    id: peel

                    property point pressAt

                    anchors.fill: parent
                    anchors.margins: -12
                    hoverEnabled: true
                    cursorShape: root.tearing ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: (mouse) => {
                        return pressAt = Qt.point(mouse.x, mouse.y);
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed)
                            return ;

                        if (!root.tearing && Math.hypot(mouse.x - pressAt.x, mouse.y - pressAt.y) > 6)
                            root.tearing = true;

                        if (root.tearing) {
                            const p = mapToItem(root, mouse.x, mouse.y);
                            // Hold the torn sheet by its corner, as you'd peel it.
                            root.tearPos = root.clampToArea(root.stackOrigin.x + p.x - root.sheetWidth + 20, root.stackOrigin.y + p.y - root.sheetHeight + 20, root.sheetWidth, root.sheetHeight);
                        }
                    }
                    onReleased: {
                        const id = root.activeId;
                        if (root.tearing)
                            root.detachAt(id, root.tearPos.x, root.tearPos.y);
                        else
                            root.peelBeside(id);
                        root.tearing = false;
                    }
                    onCanceled: root.tearing = false
                }

                DTooltipHost {
                    text: "Drag to peel off"
                    target: corner
                    hoverArea: peel
                }

                Behavior on extent {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }

                }

            }

            transform: Translate {
                id: pageShift
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }

        }

    }

    PanelWindow {
        id: probe

        screen: root.screen
        visible: !!root.screen
        color: "transparent"
        WlrLayershell.namespace: "dms:sticky-notes-workarea"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.exclusionMode: ExclusionMode.Normal
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }

        mask: Region {
        }

    }

    // Peeled sheets are ordinary items on one stationary, full-screen surface,
    // so dragging one never moves a Wayland surface. The input mask covers only
    // the sheets; clicks anywhere else reach the desktop.
    PanelWindow {
        id: desk

        screen: root.screen
        visible: !!root.screen && root.ready
        color: "transparent"
        WlrLayershell.namespace: "dms:sticky-notes-desk"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: PopoutManager.screenshotActive ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand

        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }

        Repeater {
            model: root.deskIds

            Item {
                id: loose

                required property string modelData
                readonly property var note: root.noteById(modelData)
                readonly property string noteText: note ? note.text : ""
                readonly property bool active: looseHover.hovered || looseEditor.editing || dragging || sizing
                property bool dragging: false
                property bool sizing: false
                property Region hit

                function raise() {
                    if ((note.z || 0) < root.topZ())
                        root.update(modelData, {
                        "z": root.topZ() + 1
                    });

                }

                function rebind() {
                    x = Qt.binding(() => {
                        return root.clampToArea(note ? note.x : 100, note ? note.y : 100, width, height).x;
                    });
                    y = Qt.binding(() => {
                        return root.clampToArea(note ? note.x : 100, note ? note.y : 100, width, height).y;
                    });
                    width = Qt.binding(() => {
                        return note ? (note.w || root.sheetWidth) : root.sheetWidth;
                    });
                    height = Qt.binding(() => {
                        return note ? (note.h || root.sheetHeight) : root.sheetHeight;
                    });
                }

                x: root.clampToArea(note ? note.x : 100, note ? note.y : 100, width, height).x
                y: root.clampToArea(note ? note.x : 100, note ? note.y : 100, width, height).y
                width: note ? (note.w || root.sheetWidth) : root.sheetWidth
                height: note ? (note.h || root.sheetHeight) : root.sheetHeight
                z: note ? (note.z || 0) : 0
                rotation: looseEditor.editing || dragging || sizing ? 0 : root.tiltFor(modelData)
                scale: dragging ? 1.02 : 1
                onNoteTextChanged: {
                    if (!looseEditor.editing && looseEditor.text !== noteText) {
                        looseEditor.syncing = true;
                        looseEditor.text = noteText;
                        looseEditor.syncing = false;
                    }
                }
                Component.onCompleted: {
                    looseEditor.syncing = true;
                    looseEditor.text = noteText;
                    looseEditor.syncing = false;
                    root.hitRegions = root.hitRegions.concat([hit]);
                }
                Component.onDestruction: root.hitRegions = root.hitRegions.filter((r) => {
                    return r !== hit;
                })

                HoverHandler {
                    id: looseHover
                }

                Sheet {
                    anchors.fill: parent
                    paper: loose.note ? loose.note.color : root.colors[0]
                    lifted: loose.dragging

                    MouseArea {
                        width: parent.width
                        height: root.band
                        cursorShape: loose.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: loose
                        drag.threshold: 4
                        drag.minimumX: root.clampToArea(-1e+06, -1e+06, loose.width, loose.height).x
                        drag.minimumY: root.clampToArea(-1e+06, -1e+06, loose.width, loose.height).y
                        drag.maximumX: root.clampToArea(1e+06, 1e+06, loose.width, loose.height).x
                        drag.maximumY: root.clampToArea(1e+06, 1e+06, loose.width, loose.height).y
                        onPressed: loose.raise()
                        onPositionChanged: {
                            if (drag.active) {
                                loose.dragging = true;
                                root.dropHover = root.overStack(loose.x + loose.width / 2, loose.y + loose.height / 2);
                            }
                        }
                        onReleased: {
                            if (!loose.dragging)
                                return ;

                            loose.dragging = false;
                            if (root.dropHover) {
                                root.dropHover = false;
                                root.returnToStack(loose.modelData);
                                return ;
                            }
                            root.update(loose.modelData, {
                                "x": Math.round(loose.x),
                                "y": Math.round(loose.y)
                            });
                            loose.rebind();
                        }
                    }

                    IconButton {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingXS
                        y: (root.band - root.buttonSize) / 2
                        icon: "stacks"
                        tip: "Put back on the stack (or drag it there)"
                        visible: loose.active
                        onClicked: root.returnToStack(loose.modelData)
                    }

                    DTextEdit {
                        id: looseEditor

                        property bool syncing: false
                        property bool editing: false

                        backgroundColor: "transparent"
                        borderWidth: 0
                        focusedBorderWidth: 0
                        topPadding: Theme.spacingXS
                        textColor: root.ink
                        placeholderColor: Qt.rgba(0.25, 0.2, 0.15, 0.45)
                        hidePlaceholderOnFocus: false
                        font.family: root.fontFamily(loose.note ? loose.note.font : root.fonts[0])
                        font.pixelSize: root.fontSize(loose.note ? loose.note.font : root.fonts[0])
                        placeholderText: "Write something…"
                        keyForwardTargets: [looseKeys]
                        onFocusStateChanged: (hasFocus) => {
                            editing = hasFocus;
                            if (hasFocus)
                                loose.raise();

                        }
                        onTextEdited: {
                            if (!syncing && editing)
                                root.update(loose.modelData, {
                                "text": text
                            });

                        }

                        anchors {
                            fill: parent
                            topMargin: root.band
                            bottomMargin: root.band + Theme.spacingXS
                        }

                    }

                    Item {
                        id: looseKeys

                        Keys.onEscapePressed: looseEditor.setFocus(false)
                    }

                    Row {
                        height: root.buttonSize
                        spacing: Theme.spacingXXS
                        visible: loose.active

                        anchors {
                            left: parent.left
                            leftMargin: Theme.spacingS
                            bottom: parent.bottom
                            bottomMargin: Theme.spacingXS
                        }

                        Swatches {
                            anchors.verticalCenter: parent.verticalCenter
                            selected: loose.note ? loose.note.color : ""
                            onPicked: (color) => {
                                return root.update(loose.modelData, {
                                    "color": color
                                });
                            }
                        }

                        Item {
                            width: Theme.spacingXS
                            height: 1
                        }

                        IconButton {
                            icon: "text_fields"
                            tip: loose.note ? "Font: " + root.fontLabels[root.fonts.indexOf(root.nextFont(loose.note.font))] : ""
                            onClicked: root.update(loose.modelData, {
                                "font": root.nextFont(loose.note.font)
                            })
                        }

                        IconButton {
                            icon: "delete"
                            tip: "Delete note (undo on the stack)"
                            onClicked: root.deleteNote(loose.modelData)
                        }

                    }

                    MouseArea {
                        property point pressAt
                        property size startSize

                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: Theme.iconSizeSmall + Theme.spacingXXS
                        height: width
                        cursorShape: Qt.SizeFDiagCursor
                        onPressed: (mouse) => {
                            pressAt = mapToItem(loose.parent, mouse.x, mouse.y);
                            startSize = Qt.size(loose.width, loose.height);
                            loose.sizing = true;
                            loose.raise();
                        }
                        onPositionChanged: (mouse) => {
                            const p = mapToItem(loose.parent, mouse.x, mouse.y);
                            loose.width = Math.max(180, Math.min(startSize.width + p.x - pressAt.x, root.workArea.x + root.workArea.width - loose.x));
                            loose.height = Math.max(160, Math.min(startSize.height + p.y - pressAt.y, root.workArea.y + root.workArea.height - loose.y));
                        }
                        onReleased: {
                            loose.sizing = false;
                            root.update(loose.modelData, {
                                "w": Math.round(loose.width),
                                "h": Math.round(loose.height)
                            });
                            loose.rebind();
                        }

                        DIcon {
                            anchors.centerIn: parent
                            visible: loose.active
                            name: "south_east"
                            size: Theme.iconSizeSmall
                            color: root.ink
                            opacity: 0.35
                        }

                    }

                }

                hit: Region {
                    item: loose
                }

                Behavior on rotation {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }

                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                    }

                }

            }

        }

        // Preview of a sheet being torn off the stack.
        Sheet {
            visible: root.tearing
            x: root.tearPos.x
            y: root.tearPos.y
            z: 100000
            width: root.sheetWidth
            height: root.sheetHeight
            rotation: -1.5
            lifted: true
            paper: root.activeNote ? root.activeNote.color : root.colors[0]

            Text {
                anchors.fill: parent
                anchors.topMargin: root.band + Theme.spacingXS
                anchors.margins: Theme.spacingM
                text: root.activeText
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                color: root.ink
                font.family: root.fontFamily(root.activeNote ? root.activeNote.font : root.fonts[0])
                font.pixelSize: root.fontSize(root.activeNote ? root.activeNote.font : root.fonts[0])
            }

        }

        // Preview of the whole stack while it is being moved.
        Rectangle {
            visible: root.movingStack
            x: root.movingStack ? root.stackDrop().x + root.margin : 0
            y: root.movingStack ? root.stackDrop().y + root.margin : 0
            z: 100000
            width: root.width - 2 * root.margin
            height: root.height - 2 * root.margin
            radius: Theme.cornerRadiusXXS
            color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 2
            border.color: Qt.rgba(0.25, 0.2, 0.12, 0.55)
        }

        mask: Region {
            regions: root.hitRegions
        }

    }

    component IconButton: Item {
        id: button

        property string icon
        property string tip

        signal clicked()

        width: root.buttonSize
        height: root.buttonSize
        opacity: enabled ? 1 : 0.3

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.ink
            opacity: area.pressed ? 0.18 : area.containsMouse ? 0.09 : 0
        }

        DIcon {
            anchors.centerIn: parent
            name: button.icon
            size: Theme.iconSizeSmall
            color: root.ink
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }

        DTooltipHost {
            text: button.tip
            target: button
            hoverArea: area
        }

    }

    component Swatches: Row {
        id: swatches

        property string selected

        signal picked(string color)

        spacing: Theme.spacingXS

        Repeater {
            model: root.colors

            Rectangle {
                required property string modelData

                width: Theme.iconSizeSmall
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: modelData
                border.width: swatches.selected === modelData ? 2 : 1
                border.color: Qt.rgba(0.25, 0.2, 0.15, swatches.selected === modelData ? 0.75 : 0.3)

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -2
                    cursorShape: Qt.PointingHandCursor
                    onClicked: swatches.picked(parent.modelData)
                }

            }

        }

    }

    // A sheet of paper: soft shadow, a faint top-to-bottom tone, and the
    // slightly darker adhesive band that doubles as the grab handle.
    component Sheet: Item {
        id: sheet

        property color paper: root.colors[0]
        property bool lifted: false
        property bool band: true
        default property alias content: face.data

        RectangularShadow {
            anchors.fill: face
            offset.y: sheet.lifted ? 14 : 5
            blur: sheet.lifted ? 30 : 14
            spread: 0
            radius: face.radius
            color: Qt.rgba(0.1, 0.07, 0.02, sheet.lifted ? 0.45 : 0.38)

            Behavior on offset.y {
                NumberAnimation {
                    duration: 140
                }

            }

            Behavior on blur {
                NumberAnimation {
                    duration: 140
                }

            }

        }

        Rectangle {
            id: face

            anchors.fill: parent
            radius: Theme.cornerRadiusXXS

            Rectangle {
                visible: sheet.band
                width: parent.width
                height: root.band
                color: Qt.rgba(0.35, 0.25, 0.05, 0.06)
            }

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: sheet.paper
                }

                GradientStop {
                    position: 0.85
                    color: Qt.darker(sheet.paper, 1.015)
                }

                GradientStop {
                    position: 1
                    color: Qt.darker(sheet.paper, 1.05)
                }

            }

        }

    }

}
