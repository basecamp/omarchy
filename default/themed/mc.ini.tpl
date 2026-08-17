# Midnight Commander skin, rendered from the active Omarchy theme.
# Applied via bin/omarchy-theme-set-mc.

[skin]
    description = Omarchy
    truecolors = true

[Lines]
    horiz = ─
    vert = │
    lefttop = ┌
    righttop = ┐
    leftbottom = └
    rightbottom = ┘
    topmiddle = ┬
    bottommiddle = ┴
    leftmiddle = ├
    rightmiddle = ┤
    cross = ┼
    dhoriz = ═
    dvert = ║
    dlefttop = ╔
    drighttop = ╗
    dleftbottom = ╚
    drightbottom = ╝
    dtopmiddle = ╤
    dbottommiddle = ╧
    dleftmiddle = ╟
    drightmiddle = ╢

[core]
    _default_ = {{ foreground }};{{ background }}
    selected = {{ bright_foreground }};{{ selection }}
    marked = {{ yellow }};;bold
    markselect = {{ yellow }};{{ selection }};bold
    gauge = ;{{ accent }}
    input = {{ foreground }};{{ muted }}
    inputunchanged = {{ dark_foreground }};{{ muted }}
    inputmark = {{ background }};{{ accent }}
    disabled = {{ dark_foreground }};{{ lighter_background }}
    reverse = {{ background }};{{ accent }}
    commandlinemark = {{ background }};{{ accent }}
    header = {{ accent }};;bold
    shadow = {{ darker_background }};{{ dark_background }}

[dialog]
    _default_ = {{ foreground }};{{ lighter_background }}
    dfocus = ;{{ muted }}
    dhotnormal = {{ accent }};;underline
    dhotfocus = {{ accent }};{{ muted }};underline
    dtitle = {{ accent }};;bold

[error]
    _default_ = {{ bright_foreground }};{{ red }}
    errdfocus = {{ background }};{{ bright_red }}
    errdhotnormal = {{ background }};;underline
    errdhotfocus = {{ background }};{{ bright_red }};underline
    errdtitle = {{ background }};;bold

[filehighlight]
    directory = {{ blue }};;bold
    executable = {{ green }}
    symlink = {{ cyan }}
    hardlink =
    stalelink = {{ red }}
    device = {{ magenta }}
    special = {{ orange }}
    core = {{ red }}
    temp = {{ dark_foreground }}
    archive = {{ magenta }}
    doc = {{ brown }}
    source = {{ cyan }}
    media = {{ green }}
    graph = {{ bright_cyan }}
    database = {{ bright_red }}

[menu]
    _default_ = {{ foreground }};{{ lighter_background }}
    menusel = {{ foreground }};{{ muted }}
    menuhot = {{ accent }};{{ lighter_background }};underline
    menuhotsel = {{ accent }};{{ muted }};underline
    menuinactive = {{ dark_foreground }};{{ lighter_background }}

[popupmenu]
    _default_ = {{ foreground }};{{ lighter_background }}
    menusel = {{ foreground }};{{ muted }}
    menutitle = {{ accent }};;bold

[buttonbar]
    hotkey = {{ background }};{{ accent }}
    button = {{ foreground }};{{ lighter_background }}

[statusbar]
    _default_ = {{ foreground }};{{ lighter_background }}

[help]
    _default_ = {{ foreground }};{{ lighter_background }}
    helpbold = {{ accent }};;bold
    helpitalic = {{ magenta }};;italic
    helplink = {{ cyan }};;underline
    helpslink = {{ lighter_background }};{{ cyan }}

[editor]
    _default_ = {{ foreground }};{{ background }}
    editbold = {{ bright_yellow }};;bold
    editmarked = ;{{ selection }}
    editwhitespace = {{ dark_foreground }};{{ background }}
    editnonprintable = {{ dark_foreground }};{{ background }}
    editlinestate = {{ foreground }};{{ lighter_background }}
    bookmark = {{ background }};{{ yellow }}
    bookmarkfound = {{ background }};{{ orange }}
    editrightmargin = {{ muted }};{{ background }}
    editbg = ;{{ background }}
    editframe = {{ dark_foreground }}
    editframeactive = {{ accent }}
    editframedrag = {{ green }}

[viewer]
    _default_ = {{ foreground }};{{ background }}
    viewbold = {{ bright_foreground }};;bold
    viewunderline = {{ cyan }};;underline
    viewselected = {{ foreground }};{{ selection }}

[diffviewer]
    added = {{ background }};{{ green }}
    changedline = ;{{ selection }}
    changednew = {{ background }};{{ green }}
    changed = ;{{ muted }}
    removed = ;{{ muted }}
    error = {{ bright_foreground }};{{ red }}

[widget-panel]
    sort-up-char = ▴
    sort-down-char = ▾
    hiddenfiles-show-char = •
    hiddenfiles-hide-char = ○
    history-prev-item-char = ◂
    history-next-item-char = ▸
    history-show-list-char = ▾
    filename-scroll-left-char = ◂
    filename-scroll-right-char = ▸

[widget-scrollbar]
    first-vert-char = ▴
    last-vert-char = ▾
    first-horiz-char = ◂
    last-horiz-char = ▸
    current-char = ■
    background-char = ▒

[widget-editor]
    window-state-char = ↕
    window-close-char = ✕
