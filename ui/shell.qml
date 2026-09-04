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
    property string optClient: "x11"
    property bool optFullscreen: true

    // Delete confirmation state
    property string profileToDelete: ""
    property bool showDeleteConfirm: false

    // New connection modal state
    property bool showNewConnectionModal: false
    property string newConnErrorText: ""

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
        root.optFullscreen = (p.fullscreen !== 0);
        root.optClient = (p.client && p.client.length > 0) ? p.client : "x11";

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
            client: root.optClient,
            fullscreen: root.optFullscreen,
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

    function promptDeleteProfile(name) {
        root.profileToDelete = name;
        root.showDeleteConfirm = true;
    }

    function executeDeleteProfile(name) {
        root.showDeleteConfirm = false;
        deleteProfileProc.command = [
            "bash", "-c",
            "rm -f \"$HOME/.config/rdp/profiles/" + name + ".env\" \"$HOME/.dotfiles/dot_config/private_rdp/private_profiles/private_" + name + ".env\" 2>/dev/null || true"
        ];
        deleteProfileProc.running = true;

        var updated = [];
        for (var i = 0; i < root.profiles.length; i++) {
            if (root.profiles[i].name !== name) {
                updated.push(root.profiles[i]);
            }
        }
        root.profiles = updated;
        if (root.profiles.length === 0) {
            root.selectedProfileIndex = -1;
        } else if (root.selectedProfileIndex >= updated.length) {
            root.selectProfile(updated.length - 1);
        } else {
            root.selectProfile(root.selectedProfileIndex);
        }
    }

    function openNewConnectionDialog() {
        root.newConnErrorText = "";
        root.showNewConnectionModal = true;
    }

    function saveNewConnection(name, host, user, pass, domain) {
        var cleanName = (name || "").trim().replace(/[^a-zA-Z0-9_-]/g, "_");
        var cleanHost = (host || "").trim();
        var cleanUser = (user || "").trim();
        var cleanPass = pass || "";
        var cleanDomain = (domain || "").trim();

        if (!cleanName || !cleanHost) {
            root.newConnErrorText = "Nombre y Servidor son requeridos.";
            return false;
        }

        for (var i = 0; i < root.profiles.length; i++) {
            if (root.profiles[i].name === cleanName) {
                root.newConnErrorText = "Ya existe un perfil con ese nombre.";
                return false;
            }
        }

        var content = 'HOST="' + cleanHost + '"\n' +
                      'DOMAIN="' + cleanDomain + '"\n' +
                      'USER_RDP="' + cleanUser + '"\n' +
                      'PASS_RDP="' + cleanPass + '"\n' +
                      'VPN_CHECK=""\n' +
                      'PREFERRED_WS="3"\n' +
                      'LANG_OVERRIDE=""\n\n' +
                      'AUDIO_REDIRECT=1\n' +
                      'DRIVE_REDIRECT=1\n' +
                      'CLIPBOARD_SYNC=1\n' +
                      'CLIENT="x11"\n' +
                      'FULLSCREEN=1\n';

        saveProfileProc.command = [
            "bash", "-c",
            "mkdir -p \"$HOME/.config/rdp/profiles\" && cat > \"$HOME/.config/rdp/profiles/" + cleanName + ".env\" << 'EOF'\n" + content + "EOF\nchmod 600 \"$HOME/.config/rdp/profiles/" + cleanName + ".env\"\n"
        ];
        saveProfileProc.running = true;

        var newObj = {
            name: cleanName,
            host: cleanHost,
            user: cleanUser,
            client: "x11",
            fullscreen: 1,
            audio: 1,
            clipboard: 1,
            drive: 1,
            usb: 0,
            webcam: 0,
            monitors: []
        };

        var updatedList = root.profiles.slice();
        updatedList.push(newObj);
        root.profiles = updatedList;
        root.showNewConnectionModal = false;
        root.selectProfile(updatedList.length - 1);
        return true;
    }

    Process {
        id: writeResultProc
        onExited: {
            Qt.quit();
        }
    }

    Process {
        id: deleteProfileProc
    }

    Process {
        id: saveProfileProc
    }

    // Key handlers
    FocusScope {
        anchors.fill: parent
        focus: !root.showNewConnectionModal && !root.showDeleteConfirm
        Keys.onEscapePressed: {
            if (root.showNewConnectionModal) {
                root.showNewConnectionModal = false;
            } else if (root.showDeleteConfirm) {
                root.showDeleteConfirm = false;
            } else {
                root.doCancel();
            }
        }
        Keys.onReturnPressed: {
            if (!root.showNewConnectionModal && !root.showDeleteConfirm) {
                root.doConnect();
            }
        }
        Keys.onUpPressed: {
            if (!root.showNewConnectionModal && !root.showDeleteConfirm && root.selectedProfileIndex > 0) {
                root.selectProfile(root.selectedProfileIndex - 1);
            }
        }
        Keys.onDownPressed: {
            if (!root.showNewConnectionModal && !root.showDeleteConfirm && root.selectedProfileIndex < root.profiles.length - 1) {
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
        height: 630
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
                    Layout.preferredWidth: 345
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
                                anchors.rightMargin: 10
                                spacing: 10

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

                                Rectangle {
                                    id: btnDelete
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 4
                                    color: delHover.hovered ? "#3d1f24" : "transparent"
                                    border.color: delHover.hovered ? "#f38ba8" : "transparent"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰆴"
                                        font.pixelSize: 14
                                        color: delHover.hovered ? "#f38ba8" : root.colMuted
                                    }

                                    HoverHandler { id: delHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.promptDeleteProfile(modelData.name);
                                        }
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

                            // Fullscreen Switch
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
                                    Text { text: "󰍺"; font.pixelSize: 15; color: root.colAccent }
                                    Text { text: "Pantalla Completa"; color: root.colFg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideNone }
                                    Switch { checked: root.optFullscreen; onToggled: root.optFullscreen = checked }
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

                    // FreeRDP Engine Selector
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "MOTOR FREERDP (CLIENTE)"
                            font.pixelSize: 11
                            font.bold: true
                            color: root.colMuted
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [
                                    { id: "x11", label: "X11 (VAAPI / H.264)", icon: "󰍹" },
                                    { id: "sdl", label: "SDL3 (Wayland)", icon: "󰨇" },
                                    { id: "wayland", label: "Wayland (wl)", icon: "󰟀" }
                                ]
                                delegate: Rectangle {
                                    id: clientChip
                                    Layout.fillWidth: true
                                    height: 36
                                    radius: 4
                                    property bool isSelected: root.optClient === modelData.id
                                    color: isSelected ? root.colAccent : root.colCard
                                    border.color: isSelected ? root.colAccent : root.colBorder
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text {
                                            text: modelData.icon
                                            font.pixelSize: 13
                                            color: clientChip.isSelected ? "#000000" : root.colAccent
                                        }
                                        Text {
                                            text: modelData.label
                                            font.pixelSize: 11
                                            font.bold: clientChip.isSelected
                                            color: clientChip.isSelected ? "#000000" : root.colFg
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.optClient = modelData.id;
                                        }
                                    }
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

                // Create Connection Button (Bottom Left)
                Rectangle {
                    width: 160
                    height: 38
                    radius: 4
                    color: btnNewHover.hovered ? "#1b2522" : root.colCard
                    border.color: root.colAccent
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: "󰐕"; font.pixelSize: 15; color: root.colAccent }
                        Text { text: "Nueva Conexión"; font.pixelSize: 13; font.bold: true; color: root.colAccent }
                    }

                    HoverHandler { id: btnNewHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openNewConnectionDialog()
                    }
                }

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

        // Delete Confirmation Modal Overlay
        Rectangle {
            id: deleteConfirmModal
            anchors.fill: parent
            visible: root.showDeleteConfirm
            color: "#cc070d0b"
            radius: 4
            z: 100

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Rectangle {
                anchors.centerIn: parent
                width: 440
                height: 210
                radius: 6
                color: root.colCard
                border.color: "#f38ba8"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    RowLayout {
                        spacing: 12
                        Text {
                            text: "󰆴"
                            font.pixelSize: 22
                            color: "#f38ba8"
                        }
                        Text {
                            text: "¿Eliminar conexión?"
                            font.pixelSize: 16
                            font.bold: true
                            color: root.colFg
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "¿Estás seguro de que deseas eliminar el perfil '" + root.profileToDelete + "'?\nEsta acción eliminará el archivo de configuración permanentemente."
                        font.pixelSize: 12
                        color: root.colFg
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 100
                            height: 36
                            radius: 4
                            color: cancelDelHover.hovered ? "#222a28" : root.colBg
                            border.color: root.colBorder
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Cancelar"
                                font.pixelSize: 12
                                color: root.colFg
                            }
                            HoverHandler { id: cancelDelHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showDeleteConfirm = false
                            }
                        }

                        Rectangle {
                            width: 110
                            height: 36
                            radius: 4
                            color: confirmDelHover.hovered ? "#e05575" : "#f38ba8"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: "󰆴"; font.pixelSize: 13; color: "#000000" }
                                Text { text: "Eliminar"; font.pixelSize: 12; font.bold: true; color: "#000000" }
                            }
                            HoverHandler { id: confirmDelHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.executeDeleteProfile(root.profileToDelete)
                            }
                        }
                    }
                }
            }
        }

        // New Connection Modal Overlay
        Rectangle {
            id: newConnectionModal
            anchors.fill: parent
            visible: root.showNewConnectionModal
            color: "#cc070d0b"
            radius: 4
            z: 100

            onVisibleChanged: {
                if (visible) {
                    newNameInput.text = "";
                    newHostInput.text = "";
                    newUserInput.text = "";
                    newPassInput.text = "";
                    newDomainInput.text = "";
                    root.newConnErrorText = "";
                    newNameInput.forceActiveFocus();
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Rectangle {
                anchors.centerIn: parent
                width: 480
                height: 480
                radius: 6
                color: root.colCard
                border.color: root.colAccent
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "󰐕"
                            font.pixelSize: 20
                            color: root.colAccent
                        }
                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Nueva Conexión RDP"
                                font.pixelSize: 16
                                font.bold: true
                                color: root.colFg
                            }
                            Text {
                                text: "Configuración básica del perfil"
                                font.pixelSize: 11
                                color: root.colMuted
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 4
                            color: closeNewHover.hovered ? "#30ffffff" : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 12
                                color: root.colMuted
                            }
                            HoverHandler { id: closeNewHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showNewConnectionModal = false
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colBorder
                    }

                    // Error text
                    Text {
                        Layout.fillWidth: true
                        visible: root.newConnErrorText.length > 0
                        text: root.newConnErrorText
                        font.pixelSize: 11
                        font.bold: true
                        color: "#f38ba8"
                    }

                    // Form fields
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Profile Name
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Nombre del Perfil *"; font.pixelSize: 11; font.bold: true; color: root.colMuted }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 4
                                color: root.colBg
                                border.color: newNameInput.activeFocus ? root.colAccent : root.colBorder
                                border.width: 1
                                TextInput {
                                    id: newNameInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: root.colFg
                                    font.pixelSize: 12
                                    selectByMouse: true
                                    clip: true
                                    KeyNavigation.tab: newHostInput
                                    Keys.onReturnPressed: newHostInput.forceActiveFocus()
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "ej: Oficina"
                                        color: root.colMuted
                                        font.pixelSize: 12
                                        visible: !newNameInput.text && !newNameInput.activeFocus
                                    }
                                }
                            }
                        }

                        // Host / IP
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Servidor / Host (IP o dominio) *"; font.pixelSize: 11; font.bold: true; color: root.colMuted }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 4
                                color: root.colBg
                                border.color: newHostInput.activeFocus ? root.colAccent : root.colBorder
                                border.width: 1
                                TextInput {
                                    id: newHostInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: root.colFg
                                    font.pixelSize: 12
                                    selectByMouse: true
                                    clip: true
                                    KeyNavigation.tab: newUserInput
                                    Keys.onReturnPressed: newUserInput.forceActiveFocus()
                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "ej: 192.168.1.100 o rdp.empresa.cl"
                                        color: root.colMuted
                                        font.pixelSize: 12
                                        visible: !newHostInput.text && !newHostInput.activeFocus
                                    }
                                }
                            }
                        }

                        // User and Domain row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Usuario"; font.pixelSize: 11; font.bold: true; color: root.colMuted }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 36
                                    radius: 4
                                    color: root.colBg
                                    border.color: newUserInput.activeFocus ? root.colAccent : root.colBorder
                                    border.width: 1
                                    TextInput {
                                        id: newUserInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.colFg
                                        font.pixelSize: 12
                                        selectByMouse: true
                                        clip: true
                                        KeyNavigation.tab: newDomainInput
                                        Keys.onReturnPressed: newDomainInput.forceActiveFocus()
                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: "ej: admin@dominio.cl"
                                            color: root.colMuted
                                            font.pixelSize: 12
                                            visible: !newUserInput.text && !newUserInput.activeFocus
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text { text: "Dominio"; font.pixelSize: 11; font.bold: true; color: root.colMuted }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 36
                                    radius: 4
                                    color: root.colBg
                                    border.color: newDomainInput.activeFocus ? root.colAccent : root.colBorder
                                    border.width: 1
                                    TextInput {
                                        id: newDomainInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.colFg
                                        font.pixelSize: 12
                                        selectByMouse: true
                                        clip: true
                                        KeyNavigation.tab: newPassInput
                                        Keys.onReturnPressed: newPassInput.forceActiveFocus()
                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: "MicrosoftAccount / vacío"
                                            color: root.colMuted
                                            font.pixelSize: 12
                                            visible: !newDomainInput.text && !newDomainInput.activeFocus
                                        }
                                    }
                                }
                            }
                        }

                        // Password
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Contraseña"; font.pixelSize: 11; font.bold: true; color: root.colMuted }
                            Rectangle {
                                id: passFieldRect
                                Layout.fillWidth: true
                                height: 36
                                radius: 4
                                color: root.colBg
                                border.color: newPassInput.activeFocus ? root.colAccent : root.colBorder
                                border.width: 1
                                property bool showPass: false

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    TextInput {
                                        id: newPassInput
                                        Layout.fillWidth: true
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.colFg
                                        font.pixelSize: 12
                                        echoMode: passFieldRect.showPass ? TextInput.Normal : TextInput.Password
                                        selectByMouse: true
                                        clip: true
                                        Keys.onReturnPressed: root.saveNewConnection(newNameInput.text, newHostInput.text, newUserInput.text, newPassInput.text, newDomainInput.text)
                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: "Contraseña RDP"
                                            color: root.colMuted
                                            font.pixelSize: 12
                                            visible: !newPassInput.text && !newPassInput.activeFocus
                                        }
                                    }

                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 3
                                        color: passEyeHover.hovered ? "#222a28" : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: passFieldRect.showPass ? "󰈈" : "󰈉"
                                            font.pixelSize: 13
                                            color: root.colMuted
                                        }
                                        HoverHandler { id: passEyeHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: passFieldRect.showPass = !passFieldRect.showPass
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Action buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 100
                            height: 36
                            radius: 4
                            color: cancelNewHover.hovered ? "#222a28" : root.colBg
                            border.color: root.colBorder
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Cancelar"
                                font.pixelSize: 12
                                color: root.colFg
                            }
                            HoverHandler { id: cancelNewHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showNewConnectionModal = false
                            }
                        }

                        Rectangle {
                            width: 130
                            height: 36
                            radius: 4
                            color: saveNewHover.hovered ? Qt.lighter(root.colAccent, 1.1) : root.colAccent

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: "󰄬"; font.pixelSize: 13; color: "#000000" }
                                Text { text: "Crear Perfil"; font.pixelSize: 12; font.bold: true; color: "#000000" }
                            }
                            HoverHandler { id: saveNewHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.saveNewConnection(newNameInput.text, newHostInput.text, newUserInput.text, newPassInput.text, newDomainInput.text)
                            }
                        }
                    }
                }
            }
        }
    }
}
