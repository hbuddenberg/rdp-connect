import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "#90000504"

    // Paths
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string userStr: Quickshell.env("USER") || "user"
    readonly property string dataFile: "/tmp/rdp-data-" + userStr + ".json"
    readonly property string resultFile: "/tmp/rdp-result-" + userStr + ".json"

    // Theme properties (with defaults)
    property color colBg: "#0b1110"
    property color colCard: "#141c1a"
    property color colCardSelected: "#1f2c29"
    property color colBorder: "#2a3632"
    property color colBorderActive: "#96b192"
    property color colFg: "#F8FDE6"
    property color colMuted: "#7a8280"
    property color colAccent: "#96b192"

    // Data models
    property var profiles: []
    property var monitors: []
    property int selectedProfileIndex: 0

    // Connection settings state
    property var checkedMonitors: ({})
    property bool optAudio: true
    property bool optClipboard: true
    property bool optDrive: true
    property bool optUsb: false
    property bool optWebcam: false

    // Load data on startup
    FileView {
        id: dataFileReader
        path: root.dataFile
        watchChanges: false
        onLoaded: {
            try {
                var json = JSON.parse(text());
                if (json.theme) {
                    if (json.theme.bg) root.colBg = json.theme.bg;
                    if (json.theme.card_bg) root.colCard = json.theme.card_bg;
                    if (json.theme.border) root.colBorder = json.theme.border;
                    if (json.theme.fg) root.colFg = json.theme.fg;
                    if (json.theme.accent) root.colAccent = json.theme.accent;
                    if (json.theme.muted) root.colMuted = json.theme.muted;
                }
                if (json.profiles && json.profiles.length > 0) {
                    root.profiles = json.profiles;
                    root.selectProfile(0);
                }
                if (json.monitors) {
                    root.monitors = json.monitors;
                    var m = {};
                    for (var i = 0; i < json.monitors.length; i++) {
                        m[json.monitors[i].id] = true;
                    }
                    root.checkedMonitors = m;
                }
            } catch (e) {
                console.log("Error parsing RDP data JSON: " + e);
            }
        }
    }

    function selectProfile(index) {
        if (index < 0 || index >= profiles.length) return;
        selectedProfileIndex = index;
        var p = profiles[index];
        root.optAudio = (p.audio !== 0);
        root.optClipboard = (p.clipboard !== 0);
        root.optDrive = (p.drive !== 0);
        root.optUsb = (p.usb === 1);
        root.optWebcam = (p.webcam === 1);

        if (p.monitors && Array.isArray(p.monitors) && p.monitors.length > 0) {
            var m = {};
            for (var i = 0; i < p.monitors.length; i++) {
                m[p.monitors[i]] = true;
            }
            root.checkedMonitors = m;
        }
    }

    function doConnect() {
        if (profiles.length === 0) {
            doCancel();
            return;
        }
        var p = profiles[selectedProfileIndex];
        var monList = [];
        for (var k in checkedMonitors) {
            if (checkedMonitors[k]) monList.push(k);
        }

        var res = {
            action: "connect",
            profile: p.name,
            monitors: monList,
            audio: root.optAudio,
            clipboard: root.optClipboard,
            drive: root.optDrive,
            usb: root.optUsb,
            webcam: root.optWebcam
        };

        writeResultProc.command = ["bash", "-c", "cat > " + root.resultFile + " << 'EOJSON'\n" + JSON.stringify(res, null, 2) + "\nEOJSON\n"];
        writeResultProc.running = true;
    }

    function doCancel() {
        var res = { action: "cancel" };
        writeResultProc.command = ["bash", "-c", "cat > " + root.resultFile + " << 'EOJSON'\n" + JSON.stringify(res) + "\nEOJSON\n"];
        writeResultProc.running = true;
    }

    Process {
        id: writeResultProc
        onExited: {
            Qt.quit();
        }
    }

    // Key handlers
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.doCancel()
        Keys.onReturnPressed: root.doConnect()
        Keys.onUpPressed: {
            if (root.selectedProfileIndex > 0) {
                root.selectProfile(root.selectedProfileIndex - 1);
            }
        }
        Keys.onDownPressed: {
            if (root.selectedProfileIndex < root.profiles.length - 1) {
                root.selectProfile(root.selectedProfileIndex + 1);
            }
        }
    }

    // Live theme reader
    FileView {
        id: themeFileReader
        path: root.homeDir + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        onLoaded: {
            try {
                var txt = text();
                var mAccent = txt.match(/^accent\s*=\s*"([^"]+)"/m);
                if (mAccent && mAccent[1]) root.colAccent = mAccent[1];
                var mBg = txt.match(/^bg\s*=\s*"([^"]+)"/m);
                if (mBg && mBg[1]) root.colBg = mBg[1];
                var mFg = txt.match(/^fg\s*=\s*"([^"]+)"/m);
                if (mFg && mFg[1]) root.colFg = mFg[1];
                var mCard = txt.match(/^lighter_bg\s*=\s*"([^"]+)"/m);
                if (mCard && mCard[1]) root.colCard = mCard[1];
                var mBorder = txt.match(/^muted\s*=\s*"([^"]+)"/m);
                if (mBorder && mBorder[1]) root.colBorder = mBorder[1];
            } catch (e) {}
        }
    }

    // Modal Background Click (Cancel)
    MouseArea {
        anchors.fill: parent
        onClicked: root.doCancel()
    }

    // Main Card
    Rectangle {
        id: mainCard
        anchors.centerIn: parent
        width: 940
        height: 580
        radius: 4
        color: root.colBg
        border.color: root.colAccent
        border.width: 2

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "󰍹"
                    font.pixelSize: 24
                    color: root.colAccent
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Conexión de Escritorio Remoto (RDP)"
                        font.pixelSize: 18
                        font.bold: true
                        color: root.colFg
                    }
                    Text {
                        text: "Selecciona el perfil y ajusta las opciones de conexión"
                        font.pixelSize: 12
                        color: root.colMuted
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 28
                    height: 28
                    radius: 4
                    color: closeHover.hovered ? "#30ffffff" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 14
                        color: root.colMuted
                    }
                    HoverHandler { id: closeHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.doCancel()
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.colBorder
            }

            // Body
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 20

                // Left Panel: Profiles
                ColumnLayout {
                    Layout.preferredWidth: 330
                    Layout.fillHeight: true
                    spacing: 8

                    Text {
                        text: "PERFILES GUARDADOS"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.colMuted
                    }

                    ListView {
                        id: profileList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: root.profiles

                        delegate: Rectangle {
                            id: profileItem
                            width: profileList.width
                            height: 64
                            radius: 4
                            color: root.selectedProfileIndex === index ? root.colCardSelected : (itemHover.hovered ? "#182220" : root.colCard)
                            border.color: root.selectedProfileIndex === index ? root.colAccent : root.colBorder
                            border.width: root.selectedProfileIndex === index ? 2 : 1

                            HoverHandler { id: itemHover }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.selectProfile(index)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 4
                                    color: root.selectedProfileIndex === index ? "#23332f" : "#16201e"
                                    border.color: root.selectedProfileIndex === index ? root.colAccent : root.colBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰍹"
                                        font.pixelSize: 18
                                        color: root.selectedProfileIndex === index ? root.colAccent : root.colMuted
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name || "Sin nombre"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: root.colFg
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.user ? modelData.user + " @ " : "") + (modelData.host || "IP no configurada")
                                        font.pixelSize: 11
                                        color: root.colMuted
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                // Vertical Divider
                Rectangle {
                    Layout.fillHeight: true
                    width: 1
                    color: root.colBorder
                }

                // Right Panel: Monitor & Features Tuning
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16

                    // Monitors section
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "PANTALLAS ACTIVAS"
                            font.pixelSize: 11
                            font.bold: true
                            color: root.colMuted
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: root.monitors
                                delegate: Rectangle {
                                    id: monChip
                                    width: monText.implicitWidth + 24
                                    height: 32
                                    radius: 4
                                    property bool isChecked: !!root.checkedMonitors[modelData.id]
                                    color: isChecked ? root.colAccent : root.colCard
                                    border.color: isChecked ? root.colAccent : root.colBorder
                                    border.width: 1

                                    Text {
                                        id: monText
                                        anchors.centerIn: parent
                                        text: (monChip.isChecked ? "✓ " : "") + (modelData.desc || modelData.id)
                                        font.pixelSize: 11
                                        font.bold: monChip.isChecked
                                        color: monChip.isChecked ? "#000000" : root.colFg
                                        elide: Text.ElideMiddle
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var m = Object.assign({}, root.checkedMonitors);
                                            m[modelData.id] = !m[modelData.id];
                                            root.checkedMonitors = m;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colBorder
                    }

                    // Toggles section
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "DISPOSITIVOS Y REDIRECCIONES"
                            font.pixelSize: 11
                            font.bold: true
                            color: root.colMuted
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 10
                            columnSpacing: 14

                            // Audio Switch
                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: 4
                                color: root.colCard
                                border.color: root.colBorder
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Text { text: "󰕾"; font.pixelSize: 15; color: root.colAccent }
                                    Text { text: "Audio Local"; color: root.colFg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideNone }
                                    Switch { checked: root.optAudio; onToggled: root.optAudio = checked }
                                }
                            }

                            // Clipboard Switch
                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: 4
                                color: root.colCard
                                border.color: root.colBorder
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Text { text: "󰅌"; font.pixelSize: 15; color: root.colAccent }
                                    Text { text: "Portapapeles"; color: root.colFg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideNone }
                                    Switch { checked: root.optClipboard; onToggled: root.optClipboard = checked }
                                }
                            }

                            // Shared Drive Switch
                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: 4
                                color: root.colCard
                                border.color: root.colBorder
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Text { text: "󰉉"; font.pixelSize: 15; color: root.colAccent }
                                    Text { text: "Disco Compartido"; color: root.colFg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideNone }
                                    Switch { checked: root.optDrive; onToggled: root.optDrive = checked }
                                }
                            }

                            // USB Redirect Switch
                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: 4
                                color: root.colCard
                                border.color: root.colBorder
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Text { text: "󰕓"; font.pixelSize: 15; color: root.colAccent }
                                    Text { text: "Redirección USB"; color: root.colFg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideNone }
                                    Switch { checked: root.optUsb; onToggled: root.optUsb = checked }
                                }
                            }

                            // Webcam Switch
                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: 4
                                color: root.colCard
                                border.color: root.colBorder
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Text { text: "󰄀"; font.pixelSize: 15; color: root.colAccent }
                                    Text { text: "Cámara Web"; color: root.colFg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideNone }
                                    Switch { checked: root.optWebcam; onToggled: root.optWebcam = checked }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Footer Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                // Cancel Button
                Rectangle {
                    width: 110
                    height: 38
                    radius: 4
                    color: btnCancelHover.hovered ? "#222a28" : root.colCard
                    border.color: root.colBorder
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Cancelar"
                        font.pixelSize: 13
                        color: root.colFg
                    }

                    HoverHandler { id: btnCancelHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.doCancel()
                    }
                }

                // Connect Button
                Rectangle {
                    width: 140
                    height: 38
                    radius: 4
                    color: btnConnHover.hovered ? Qt.lighter(root.colAccent, 1.1) : root.colAccent

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "󰐊"; font.pixelSize: 14; color: "#000000" }
                        Text { text: "Conectar"; font.pixelSize: 13; font.bold: true; color: "#000000" }
                    }

                    HoverHandler { id: btnConnHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.doConnect()
                    }
                }
            }
        }
    }
}
