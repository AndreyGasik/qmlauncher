import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami

Window {
    id: root
    width: 300
    minimumWidth: 300
    height: 480
    visible: true
    title: "QM Launcher"

    color: "#00000000"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

    property bool useTerminal: pythonBackend.getUseTerminal()
    property bool isRunning: false
    property bool menuOpen: false
    property int menuIndex: -1
    property int lastHoveredIndex: -1
    property int lastActionIndex: -1
    property int hoveredIndex: -1
    readonly property int itemHeight: 44
    property bool isDialogOpen: false
    property string errorMessage: ""

    // Drag & Drop
    property int dragSourceIndex: -1
    property int dragTargetIndex: -1
    property real dragGhostY: 0
    property bool isDragging: false
    property string dragGhostName: ""
    property string dragGhostColor: ""

    // Координаты мыши (локальные относительно окна)
    property real windowMouseX: 0
    property real windowMouseY: 0

    property color baseColor: Kirigami.Theme.backgroundColor
    property color textColor: Kirigami.Theme.textColor
    property color highlightColor: Kirigami.Theme.highlightColor
    property real opacityLevel: 0.55
    property color bgColor: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, opacityLevel)
    property color hoverColor: Qt.rgba(highlightColor.r, highlightColor.g, highlightColor.b, 0.4)

    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    onVisibleChanged: {
        if (visible) {
            opacity = 1
            updateWidth()
        } else {
            opacity = 0
        }
    }

    function updateWidth() {
        // Верхний предел: длинное имя не должно раздувать окно за экран
        var limit = Math.max(300, Screen.desktopAvailableWidth - 100)
        var maxWidth = Math.min(pythonBackend.getMaxNameWidth(), limit)
        root.minimumWidth = maxWidth
        root.width = maxWidth
    }

    onErrorMessageChanged: {
        if (errorMessage.length > 0) {
            errorToastTimer.restart()
        }
    }

    // Пересчитываем ширину сразу при изменении списка (добавление/переименование/удаление),
    // а не только при показе окна
    Connections {
        target: scriptModel
        function onRowsInserted() { updateWidth() }
        function onRowsRemoved() { updateWidth() }
        function onDataChanged() { updateWidth() }
        function onModelReset() { updateWidth() }
    }

    Timer {
        id: errorToastTimer
        interval: 3500
        repeat: false
        onTriggered: root.errorMessage = ""
    }

    onIsDialogOpenChanged: {
        if (!isDialogOpen) {
            timerClose.stop()
            timerRestoreAfterDialog.start()
        } else {
            timerClose.stop()
        }
    }

    Timer {
        id: timerRestoreAfterDialog
        interval: 150
        repeat: false
        onTriggered: {
            root.requestActivate()
            root.raise()
            restoreFocus()
            updateWidth()
        }
    }

    // Таймер восстановления hover после удаления
    Timer {
        id: timerAfterRemove
        interval: 80
        repeat: false
        onTriggered: {
            if (root.isDragging) return

            appList.forceLayout()

            var mousePos = mouseTracker.mapToItem(appList, windowMouseX, windowMouseY)
            // indexAt ждёт координаты contentItem, а не видимой области
            var idx = appList.indexAt(mousePos.x + appList.contentX, mousePos.y + appList.contentY)

            if (idx === -1) {
                // Fallback: учитываем прокрутку
                var adjustedY = mousePos.y + appList.contentY
                idx = Math.floor(adjustedY / root.itemHeight)
                var count = scriptModel.rowCount()
                idx = Math.max(0, Math.min(idx, count - 1))
            }

            root.hoveredIndex = -1

            if (idx !== -1) {
                root.hoveredIndex = idx
                root.lastHoveredIndex = idx
            }
        }
    }

    Timer {
        id: timerClose
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.active && !root.menuOpen && !root.isDialogOpen) {
                Qt.quit()
            }
        }
    }

    onActiveChanged: {
        if (!active) {
            if (!root.menuOpen && !root.isDialogOpen) timerClose.start()
        } else {
            timerClose.stop()
        }
    }

    // Глобальный трекер мыши (только координаты)
    MouseArea {
        id: mouseTracker
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        z: -1
        onPositionChanged: (mouse) => {
            windowMouseX = mouse.x
            windowMouseY = mouse.y
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 16
        color: root.bgColor
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!root.menuOpen && !root.isDialogOpen && !root.isDragging) Qt.quit()
            }
        }

        Item {
            id: headerArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 32
            z: 10

            Rectangle {
                id: closeBtn
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                width: 26
                height: 26
                radius: 13
                color: closeMouse.containsMouse ? "#ff5c5c" : Qt.rgba(1, 1, 1, 0.1)
                Behavior on color { ColorAnimation { duration: 80 } }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Qt.quit()
                    cursorShape: Qt.PointingHandCursor
                }
                Text {
                    text: "✕"
                    anchors.centerIn: parent
                    color: "white"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: 40
                cursorShape: Qt.SizeAllCursor
                onPressed: root.startSystemMove()
            }
        }

        ColumnLayout {
            anchors.top: headerArea.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            anchors.bottomMargin: 40
            spacing: 8
            z: 5

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Кастомная hover-подсветка: живёт внутри appList.contentItem,
                // поэтому скроллится вместе с контентом мгновенно (как раньше
                // делал встроенный highlight), а Behavior анимирует только
                // реальную смену наведённой строки, а не каждый кадр скролла.
                Rectangle {
                    id: hoverPill
                    parent: appList.contentItem
                    z: -1
                    property bool shineEnabled: true   // false — отключить быстрый блик при смене строки
                    visible: root.hoveredIndex >= 0 && !root.isDragging
                    x: 4
                    width: appList.width - 8
                    height: root.itemHeight
                    radius: 10
                    color: root.hoverColor
                    y: root.hoveredIndex * root.itemHeight
                    Behavior on y { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }

                    // «Стеклянный» объём. Все слои — дочерние элементы плашки, поэтому
                    // они едут вместе с ней, а анимация Behavior on y не затрагивается.
                    // Верх светлее, низ чуть темнее:
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.14) }
                        }
                    }
                    // Тонкий внутренний кант:
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                    }
                    // Зеркальная линия света у верхней кромки:
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 20
                        height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.45) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        }
                    }
                    // Быстрый блик: светлая полоса пробегает слева направо при смене строки.
                    // Контейнер с отступом 3 px: его прямые углы целиком лежат внутри
                    // скругления радиусом 10, поэтому clip не даёт артефактов по краям.
                    Item {
                        id: shineClip
                        anchors.fill: parent
                        anchors.margins: 3
                        clip: true

                        Rectangle {
                            id: shineStreak
                            width: 34
                            height: parent.height * 2
                            y: -parent.height / 2
                            x: -width - 16
                            rotation: 20
                            opacity: 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.26) }
                                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                            }
                        }

                        ParallelAnimation {
                            id: shineAnim
                            NumberAnimation {
                                target: shineStreak; property: "x"
                                from: -shineStreak.width - 16; to: shineClip.width + 16
                                duration: 260; easing.type: Easing.OutCubic
                            }
                            SequentialAnimation {
                                NumberAnimation { target: shineStreak; property: "opacity"; from: 0; to: 1; duration: 60 }
                                NumberAnimation { target: shineStreak; property: "opacity"; from: 1; to: 0; duration: 200 }
                            }
                        }
                    }
                    Connections {
                        target: root
                        function onHoveredIndexChanged() {
                            if (hoverPill.shineEnabled && root.hoveredIndex >= 0) shineAnim.restart()
                        }
                    }
                }

                ListView {
                    id: appList
                    anchors.fill: parent
                    model: scriptModel
                    clip: true

                    flickDeceleration: 5000
                    maximumFlickVelocity: 3000
                    interactive: !root.isDragging

                    delegate: Item {
                        id: delegateItem
                        width: appList.width
                        height: root.itemHeight

                        property int clickedIndex: -1
                        property real pressStartY: 0
                        property real pressListY: 0
                        property bool dragStarted: false
                        readonly property color tint: itemColor
                        readonly property string badgeText: getBadgeForPath(path)

                        opacity: (root.isDragging && index === root.dragSourceIndex) ? 0.25 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            radius: 10
                            color: (root.isDragging && index === root.dragTargetIndex && index !== root.dragSourceIndex)
                                   ? Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, 0.25)
                                   : "transparent"
                            Behavior on color { ColorAnimation { duration: 60 } }

                            Rectangle {
                                visible: root.isDragging && index === root.dragTargetIndex && index !== root.dragSourceIndex && root.dragTargetIndex < root.dragSourceIndex
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 2
                                radius: 1
                                color: root.highlightColor
                                opacity: 0.8
                            }

                            Rectangle {
                                visible: root.isDragging && index === root.dragTargetIndex && index !== root.dragSourceIndex && root.dragTargetIndex > root.dragSourceIndex
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 2
                                radius: 1
                                color: root.highlightColor
                                opacity: 0.8
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            // Значок-бейдж: плитка в цвете пункта + короткая метка типа файла
                            Item {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 7
                                    color: delegateItem.tint
                                    opacity: 0.18
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 7
                                    color: "transparent"
                                    border.width: 1
                                    border.color: delegateItem.tint
                                    opacity: 0.55
                                }
                                Text {
                                    id: badgeLabel
                                    anchors.fill: parent
                                    text: delegateItem.badgeText
                                    color: delegateItem.tint
                                    font.pixelSize: badgeLabel.text.length > 2 ? 8 : 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.3
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Text {
                                text: name
                                color: itemColor
                                font.pointSize: 12
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: delegateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: root.isDragging ? Qt.DragMoveCursor : Qt.PointingHandCursor

                            onEntered: {
                                root.lastHoveredIndex = index
                                if (!root.menuOpen && !root.isDragging) {
                                    root.hoveredIndex = index
                                }
                            }

                            onPressed: (mouse) => {
                                mouse.accepted = true
                                if (mouse.button === Qt.LeftButton) {
                                    delegateItem.pressStartY = mouse.y
                                    delegateItem.pressListY = delegateItem.y - appList.contentY + mouse.y
                                    delegateItem.dragStarted = false
                                    delegateItem.clickedIndex = index
                                }
                            }

                            onPositionChanged: (mouse) => {
                                if (pressed && mouse.buttons === Qt.LeftButton) {
                                    var dy = Math.abs(mouse.y - delegateItem.pressStartY)
                                    if (!delegateItem.dragStarted && dy > 8) {
                                        delegateItem.dragStarted = true
                                        delegateItem.clickedIndex = -1
                                        root.isDragging = true
                                        root.dragSourceIndex = index
                                        root.dragTargetIndex = index
                                        root.dragGhostName = name
                                        root.dragGhostColor = itemColor
                                    }
                                    if (delegateItem.dragStarted) {
                                        var delta = mouse.y - delegateItem.pressStartY
                                        var visY = delegateItem.pressListY + delta
                                        root.dragGhostY = visY - 22
                                        var contY = visY + appList.contentY
                                        var targetIdx = Math.floor(contY / root.itemHeight)
                                        targetIdx = Math.max(0, Math.min(scriptModel.rowCount() - 1, targetIdx))
                                        root.dragTargetIndex = targetIdx
                                    }
                                }
                            }

                            onReleased: (mouse) => {
                                if (root.isDragging) {
                                    if (root.dragSourceIndex !== root.dragTargetIndex
                                            && root.dragSourceIndex >= 0
                                            && root.dragTargetIndex >= 0) {
                                        pythonBackend.moveItem(root.dragSourceIndex, root.dragTargetIndex)
                                    }
                                    root.isDragging = false
                                    root.dragSourceIndex = -1
                                    root.dragTargetIndex = -1
                                    root.dragGhostName = ""
                                    root.dragGhostColor = ""
                                    root.hoveredIndex = index
                                } else if (delegateItem.clickedIndex !== -1 && !delegateItem.dragStarted) {
                                    if (!root.isRunning) {
                                        root.isRunning = true
                                        pythonBackend.runScript(index)
                                        timerResetRunning.start()
                                    }
                                }
                                delegateItem.clickedIndex = -1
                                delegateItem.dragStarted = false
                            }

                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    root.hoveredIndex = index
                                    root.menuIndex = index
                                    contextMenu.popup()
                                }
                            }
                        }

                        Timer {
                            id: timerResetRunning
                            interval: 1000
                            onTriggered: root.isRunning = false
                        }

                        function getBadgeForPath(filePath) {
                            var p = filePath.toLowerCase()
                            if (p.endsWith(".appimage")) return "APP"
                            if (p.endsWith(".py")) return "PY"
                            if (p.endsWith(".fish")) return "FSH"
                            if (p.endsWith(".sh") || p.endsWith(".bash")) return "SH"
                            if (p.endsWith(".exe")) return "EXE"
                            if (p.endsWith(".desktop")) return "DT"
                            return "▸"
                        }
                    }
                }

                // Призрак в родителе списка, а не в contentItem:
                // иначе при прокрутке он уезжает вместе с контентом.
                Rectangle {
                    id: dragGhost
                    parent: appList.parent
                    visible: root.isDragging
                    x: 4
                    y: Math.max(0, Math.min(appList.height - height, root.dragGhostY))
                    width: appList.width - 8
                    height: 44
                    radius: 10
                    color: Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, 0.55)
                    border.color: root.highlightColor
                    border.width: 1.5
                    z: 999
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: parent.radius + 4
                        color: "transparent"
                        border.color: Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, 0.2)
                        border.width: 4
                        z: -1
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        Text {
                            text: "⠿"
                            font.pixelSize: 16
                            color: root.dragGhostColor || root.textColor
                            opacity: 0.9
                            Layout.preferredWidth: 24
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            text: root.dragGhostName
                            color: root.dragGhostColor || root.textColor
                            font.pointSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                            font.bold: true
                        }
                    }
                }
            }

            CheckBox {
                text: "Терминал для SH/FISH"
                checked: root.useTerminal
                onToggled: {
                    root.useTerminal = checked
                    pythonBackend.setUseTerminal(checked)
                }
                contentItem: Text {
                    text: parent.text
                    color: root.textColor
                    font.pointSize: 10
                    leftPadding: parent.indicator.width + parent.spacing
                }
                indicator: Rectangle {
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: 5
                    color: parent.checked ? root.highlightColor : Qt.darker(root.baseColor, 1.2)
                    border.color: Qt.lighter(root.baseColor, 1.5)
                    Rectangle {
                        visible: parent.parent.checked
                        width: 10
                        height: 10
                        anchors.centerIn: parent
                        radius: 3
                        color: "white"
                    }
                }
                background: Rectangle { color: "transparent" }
            }
        }

        Rectangle {
            id: addBtn
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            width: 26
            height: 26
            radius: 13
            color: mouseAddArea.containsMouse ? root.highlightColor : Qt.darker(root.baseColor, 1.15)
            border.color: Qt.rgba(1, 1, 1, 0.2)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 80 } }

            // Анимируемые параметры: блик и цвет плюса плавно меняются
            // в такт со сменой цвета кнопки (те же 80 мс).
            property real glossAlpha: mouseAddArea.containsMouse ? 0.30 : 0.16
            property color plusColor: mouseAddArea.containsMouse ? "white" : root.textColor
            Behavior on glossAlpha { NumberAnimation { duration: 80 } }
            Behavior on plusColor { ColorAnimation { duration: 80 } }

            // Блик: мягкий светлый градиент в верхней половине кнопки
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0;  color: Qt.rgba(1, 1, 1, addBtn.glossAlpha) }
                    GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }

            // Плюс из двух скруглённых планок: ровно по центру кнопки
            // (в отличие от эмодзи «➕», у которого свои метрики шрифта)
            Rectangle {
                anchors.centerIn: parent
                width: 10; height: 2; radius: 1
                color: addBtn.plusColor
            }
            Rectangle {
                anchors.centerIn: parent
                width: 2; height: 10; radius: 1
                color: addBtn.plusColor
            }

            MouseArea {
                id: mouseAddArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pythonBackend.addFile()
            }
        }

        // Тост с сообщением об ошибке запуска
        Rectangle {
            id: errorToast
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            height: errorText.implicitHeight + 16
            radius: 10
            color: Qt.rgba(0.65, 0.1, 0.1, 0.92)
            z: 1000
            visible: opacity > 0
            opacity: root.errorMessage.length > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Text {
                id: errorText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 10
                text: root.errorMessage
                color: "white"
                font.pointSize: 9
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.errorMessage = ""
            }
        }
    }

    Menu {
        id: contextMenu

        onOpened: {
            root.menuOpen = true
            root.lastActionIndex = root.menuIndex
        }

        onClosed: {
            root.menuOpen = false
            root.requestActivate()
        }

        MenuItem {
            text: "✏ Переименовать"
            onTriggered: pythonBackend.renameItem(root.menuIndex)
        }
        MenuItem {
            text: "📂 Изменить путь"
            onTriggered: pythonBackend.editPath(root.menuIndex)
        }
        MenuItem {
            text: "🎨 Выбрать цвет..."
            onTriggered: pythonBackend.chooseColor(root.menuIndex)
        }
        MenuSeparator {}
        MenuItem {
            text: "🗑 Удалить"
            onTriggered: {
                var removedIndex = root.menuIndex
                pythonBackend.removeItem(removedIndex)
                var newCount = scriptModel.rowCount()
                root.lastActionIndex = newCount > 0 ? Math.min(removedIndex, newCount - 1) : -1
                timerAfterRemove.restart()
            }
        }
    }

    function restoreFocus() {
        if (root.menuOpen || root.isDialogOpen) return
        if (typeof scriptModel === 'undefined' || scriptModel === null) return
        var count = scriptModel.rowCount()
        if (count === 0) {
            root.hoveredIndex = -1
            return
        }
        var target = -1
        if (root.lastActionIndex >= 0 && root.lastActionIndex < count) {
            target = root.lastActionIndex
        } else if (root.lastHoveredIndex >= 0 && root.lastHoveredIndex < count) {
            target = root.lastHoveredIndex
        } else {
            target = count - 1
        }
        root.hoveredIndex = target
        appList.positionViewAtIndex(target, ListView.Contain)
    }

    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
}
