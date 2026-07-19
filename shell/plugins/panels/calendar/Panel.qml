import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.calendar"
  ipcTarget: "omarchy.calendar"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    setCenterHoverRevealSuppressed(true)
    root.controller.show()
    root.goToToday()
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Calendar state -----------------------------------------------------

  property date today: new Date()
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property date selectedDate: today

  readonly property bool weekStartsMonday: setting("weekStart", "monday") !== "sunday"
  readonly property string selectedIso: Model.isoFromDate(selectedDate)

  readonly property var monthGrid: Model.buildMonthGrid(root.viewYear, root.viewMonth, root.weekStartsMonday, root.today)
  readonly property var weekdayHeader: Model.weekdayLabels(root.weekStartsMonday, function(dayIndex) {
    // 2023-01-01 was a Sunday; offsetting from it gives every weekday a
    // stable reference date to hand to Qt's locale-aware formatter.
    return Qt.formatDate(new Date(2023, 0, 1 + dayIndex), "ddd")
  })
  readonly property string monthLabel: Model.monthTitle(root.viewYear, root.viewMonth, function(y, m) {
    return Qt.formatDate(new Date(y, m, 1), "MMMM yyyy")
  })

  // Keeps "today" correct across midnight while the panel is left open.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.today = new Date()
  }

  function goToMonth(delta) {
    var next = Model.addMonths(root.viewYear, root.viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function goToToday() {
    root.viewYear = root.today.getFullYear()
    root.viewMonth = root.today.getMonth()
    root.selectedDate = root.today
  }

  function selectDate(date) {
    root.selectedDate = date
    if (!Model.isSameMonth(date, new Date(root.viewYear, root.viewMonth, 1))) {
      root.viewYear = date.getFullYear()
      root.viewMonth = date.getMonth()
    }
  }

  // dx moves by a day, dy by a week — matches PanelKeyCatcher's grid
  // vocabulary (h/j/k/l and arrow keys) onto actual calendar geometry.
  function moveSelection(dx, dy) {
    var next = new Date(root.selectedDate)
    next.setDate(next.getDate() + dx + dy * 7)
    root.selectDate(next)
  }

  // ---- Notes ----------------------------------------------------------

  property var notesMap: ({})
  readonly property var selectedNotes: Model.notesFor(root.notesMap, root.selectedIso)
  readonly property int monthNotesCount: {
    var prefix = root.viewYear + "-" + (root.viewMonth < 9 ? "0" : "") + (root.viewMonth + 1) + "-"
    var count = 0
    for (var key in root.notesMap) {
      if (key.indexOf(prefix) === 0) count += root.notesMap[key].length
    }
    return count
  }

  function saveNotes() {
    notesFile.setText(Model.serializeNotes(root.notesMap))
  }

  function addNoteText(text) {
    if (String(text || "").trim() === "") return
    root.notesMap = Model.addNote(root.notesMap, root.selectedIso, text)
    root.saveNotes()
  }

  function removeNoteAt(index) {
    root.notesMap = Model.removeNote(root.notesMap, root.selectedIso, index)
    root.saveNotes()
  }

  function removeLastNote() {
    if (root.selectedNotes.length === 0) return
    root.removeNoteAt(root.selectedNotes.length - 1)
  }

  property FileView notesFile: FileView {
    id: notesFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/calendar-notes.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.notesMap = Model.parseNotes(text())
    onLoadFailed: root.notesMap = Model.parseNotes("")
    onFileChanged: reload()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function jumpToToday(): void { root.openFromHotkey() }
  }

  // ---- Presentation -----------------------------------------------------

  readonly property int cellSize: Style.space(32)
  readonly property int cellGap: Style.space(4)
  // Single source of truth for horizontal breathing room. Every row below
  // (hero, separator, notes list, input) anchors off this instead of its
  // own hardcoded margin, so all their left/right edges line up instead
  // of drifting between 0, 12 and "whatever centers this row" like before.
  readonly property int hPad: Style.space(14)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(280))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: noteField.activeFocus

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveSelection(dx, dy) }
      onActivateRequested: Qt.callLater(function() { noteField.forceActiveFocus() })
      onDeleteRequested: root.removeLastNote()
      onTextKey: function(t) {
        if (t === "t") root.goToToday()
        else if (t === "[") root.goToMonth(-1)
        else if (t === "]") root.goToMonth(1)
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: calendarColumn
          width: calendarScroll.width
          spacing: Style.space(8)

          // ---- Hero: big glyph + big selected-day number, with the
          //      month/year label anchored top-right on the SAME row.
          //      calMonthLabel's left edge is pinned to calHeroTop's right
          //      edge (with a minimum gap), so its available width shrinks
          //      automatically for long names — combined with elide, this
          //      guarantees the two can never visually collide, regardless
          //      of month name length ("September", "November"...) or font.
          Item {
            width: parent.width
            height: calHeroTop.implicitHeight

            Row {
              id: calHeroTop
              anchors.left: parent.left
              anchors.leftMargin: root.hPad
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -5
                text: "\uf133" // nf-fa-calendar (outline)
                color: Qt.darker(root.bar.foreground, 1.2)
                font.family: root.bar.fontFamily
                // A calendar glyph is decorative, not informational (unlike
                // Weather's condition icon), so it stays modest next to the
                // big number instead of matching Weather's 64px hero size.
                font.pixelSize: 18
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  id: calDayBig
                  text: String(root.selectedDate.getDate())
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  // Hero day-of-month read-out; deliberately oversized,
                  // outside the Style.font.* scale (matches Weather's temp).
                  font.pixelSize: 32
                  font.bold: true
                }
                Text {
                  text: Qt.formatDate(root.selectedDate, "ddd").toUpperCase()
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.top: calDayBig.top
                  anchors.topMargin: Style.space(5)
                }
              }
            }

            Text {
              id: calMonthLabel
              anchors.left: calHeroTop.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: root.hPad
              anchors.verticalCenter: calHeroTop.verticalCenter
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              text: root.monthLabel.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }
          }

          // ---- WEEK / NOTES: two equal-width stat columns, evenly spread
          //      across the panel and center-aligned so each label sits
          //      directly above its value. (A third "TODAY" column used to
          //      live here showing today's weekday — dropped because it
          //      just duplicated the "SUN" already shown next to the big
          //      day number above whenever the selected day was today.)
          Row {
            id: calHeroStats
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - root.hPad * 2

            Repeater {
              model: [
                { label: "WEEK", value: String(Model.isoWeek(root.selectedDate)) },
                { label: "NOTES", value: String(root.monthNotesCount) }
              ]

              Column {
                required property var modelData
                width: calHeroStats.width / 2
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData.label
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.5
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData.value
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
              }
            }
          }

          // ---- Month navigation.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            Button {
              iconText: "‹"
              tooltipText: "Previous month"
              foreground: root.bar.foreground
              onClicked: root.goToMonth(-1)
            }

            Button {
              text: "Today"
              foreground: root.bar.foreground
              onClicked: root.goToToday()
            }

            Button {
              iconText: "›"
              tooltipText: "Next month"
              foreground: root.bar.foreground
              onClicked: root.goToMonth(1)
            }
          }

          // ---- Weekday header row.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.cellGap

            Repeater {
              model: root.weekdayHeader

              Text {
                required property string modelData
                width: root.cellSize
                horizontalAlignment: Text.AlignHCenter
                text: modelData.toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.5
              }
            }
          }

          // ---- Month grid: fixed 6 weeks x 7 days so the popup never
          //      resizes when flipping between short and long months.
          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.cellGap

            Repeater {
              model: 6

              Row {
                required property int index
                spacing: root.cellGap

                Repeater {
                  model: root.monthGrid.slice(index * 7, index * 7 + 7)

                  Rectangle {
                    id: dayCell
                    required property var modelData
                    readonly property bool isSelected: Model.isSameDate(modelData.date, root.selectedDate)
                    readonly property bool hasNotes: Model.notesFor(root.notesMap, modelData.iso).length > 0

                    width: root.cellSize
                    height: root.cellSize
                    radius: Style.cornerRadius
                    color: isSelected
                      ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                      : (cellMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent")
                    border.width: modelData.isToday ? Math.max(1, Style.space(1)) : 0
                    border.color: Color.accent

                    Text {
                      anchors.centerIn: parent
                      anchors.verticalCenterOffset: dayCell.hasNotes ? -Style.space(3) : 0
                      text: String(dayCell.modelData.day)
                      color: !dayCell.modelData.inMonth
                        ? Qt.darker(root.bar.foreground, 2.2)
                        : (dayCell.isSelected ? Style.selectedStateColor(root.bar.foreground, Color.accent) : root.bar.foreground)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: dayCell.modelData.isToday || dayCell.isSelected
                    }

                    Rectangle {
                      visible: dayCell.hasNotes
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.space(5)
                      width: Style.space(4)
                      height: Style.space(4)
                      radius: width / 2
                      color: dayCell.isSelected ? Style.selectedStateColor(root.bar.foreground, Color.accent) : Color.accent
                    }

                    MouseArea {
                      id: cellMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectDate(dayCell.modelData.date)
                    }
                  }
                }
              }
            }
          }

          PanelSeparator {
            x: root.hPad
            width: parent.width - root.hPad * 2
            foreground: root.bar.foreground
          }

          // ---- Notes for the selected day. (No date subtitle here — the
          //      hero row above already shows day number, weekday and
          //      month/year, so repeating "Sunday, July 19" here was just
          //      restating what's already on screen.)
          PanelSectionHeader {
            x: root.hPad
            text: "Notes"
            foreground: root.bar.foreground
          }

          Column {
            x: root.hPad
            width: parent.width - root.hPad * 2
            spacing: Style.space(4)
            visible: root.selectedNotes.length > 0

            Repeater {
              model: root.selectedNotes

              Row {
                required property string modelData
                required property int index
                width: parent.width
                spacing: Style.space(8)

                Text {
                  width: Style.space(12)
                  horizontalAlignment: Text.AlignHCenter
                  text: "•"
                  color: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  // Budget the remaining width exactly: bullet + close
                  // button + the two Row spacings between all three
                  // children, so the "x" never overflows past the edge
                  // and gets clipped by the Flickable above.
                  width: parent.width - Style.space(12) - Style.space(24) - Style.space(16)
                  text: modelData
                  wrapMode: Text.Wrap
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Item {
                  width: Style.space(24)
                  height: Style.space(24)

                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removeNoteAt(index)
                  }
                }
              }
            }
          }

          Text {
            x: root.hPad
            visible: root.selectedNotes.length === 0
            text: "No notes for this day"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          TextField {
            id: noteField
            x: root.hPad
            width: parent.width - root.hPad * 2
            placeholderText: "Add a note for this day…"
            foreground: root.bar.foreground
            onAccepted: {
              root.addNoteText(text)
              text = ""
            }
          }
        }
      }
    }
  }
}
