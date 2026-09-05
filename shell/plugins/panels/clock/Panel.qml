import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null
  property var service: null
  property string activeTab: "calendar"
  property string plannerView: "plan"

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    if (plannerLoader.item && typeof plannerLoader.item.cancelEditor === "function")
      plannerLoader.item.cancelEditor()
    root.activeTab = "calendar"
    root.plannerView = "plan"
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function openPlanner() {
    root.activeTab = "planner"
    root.plannerView = "plan"
    root.open()
  }

  function openAgenda() {
    root.activeTab = "planner"
    root.plannerView = "agenda"
    root.open()
  }

  function selectView(view) {
    if (view === "calendar") {
      root.activeTab = "calendar"
      root.plannerView = "plan"
    } else {
      root.activeTab = "planner"
      root.plannerView = view
    }
  }

  function injectPlanner() {
    if (!plannerLoader.item) return
    plannerLoader.item.service = root.service
    plannerLoader.item.bar = root.bar
    plannerLoader.item.activeView = root.plannerView
    if (root.activeTab !== "calendar" && plannerLoader.item.editorMode === "")
      Qt.callLater(function() { if (plannerLoader.item) plannerLoader.item.focusFirst() })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife(bornText, expectancyText) {
    var born = Model.parseBirthYear(bornText, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyText)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(tabs.implicitHeight + Style.space(14)
      + (root.activeTab === "calendar"
        ? calendarView.implicitHeight
        : plannerLoader.item && plannerLoader.item.editorMode !== ""
          && plannerLoader.item.editorImplicitHeight > 0
          ? plannerLoader.item.editorImplicitHeight
          : Math.max(calendarView.implicitHeight, Style.space(500))))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife || root.activeTab !== "calendar"
      onMoveRequested: function(dx, dy) {
        if (root.activeTab !== "calendar") return
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: {
        if (root.activeTab === "calendar") root.goToToday()
      }
      onCloseRequested: {
        if (root.activeTab !== "calendar") {
          root.activeTab = "calendar"
          root.plannerView = "plan"
        } else {
          root.close()
        }
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.activeTab !== "calendar") return
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "a" || t === "A") root.openAgenda()
        else if (t === "p" || t === "P") root.openPlanner()
      }

      CalendarTabs {
        id: tabs
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        selected: root.activeTab === "calendar" ? "calendar" : root.plannerView
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onTabRequested: function(view) { root.selectView(view) }
      }

      CalendarView {
        id: calendarView
        visible: root.activeTab === "calendar"
        anchors.top: tabs.bottom
        anchors.topMargin: Style.space(14)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        service: root.service
        bar: root.bar
        today: root.today
        viewYear: root.viewYear
        viewMonth: root.viewMonth
        weekStart: root.weekStart
        editingLife: root.editingLife
        birthYear: root.birthYear
        lifeExpectancy: root.lifeExpectancy
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        onTodayRequested: root.goToToday()
        onMonthRequested: function(delta) { root.moveMonth(delta) }
        onWeekStartRequested: root.toggleWeekStart()
        onPlannerRequested: root.openPlanner()
        onLifeEditRequested: root.startEditingLife()
        onLifeClearRequested: root.clearLife()
        onLifeCommitRequested: function(birth, expectancy) { root.commitLife(birth, expectancy) }
        onLifeCancelRequested: root.cancelEditingLife()
      }

      Loader {
        id: plannerLoader
        anchors.top: tabs.bottom
        anchors.topMargin: Style.space(14)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: root.activeTab !== "calendar"
        source: Qt.resolvedUrl("PlannerView.qml")
        onLoaded: {
          root.injectPlanner()
          Qt.callLater(root.injectPlanner)
        }
      }

      Connections {
        target: plannerLoader.item
        function onCalendarRequested() { root.activeTab = "calendar" }
        function onAddTaskRequested() { root.plannerView = "plan" }
        function onSettingsRequested() { root.plannerView = "plan" }
        function onReviewProposalRequested() { root.plannerView = "plan" }
      }
    }
  }

  onServiceChanged: injectPlanner()
  onPlannerViewChanged: injectPlanner()
  onActiveTabChanged: injectPlanner()
}
