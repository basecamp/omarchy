{
    "name": "Omarchy",
    "$schema": "vscode://schemas/color-theme",
    "type": "{{ theme_type }}",
    "semanticHighlighting": true,
    "semanticTokenColors": {
        "parameter": "{{ cyan }}",
        "parameter.declaration": "{{ cyan }}",
        "variable": "{{ foreground }}",
        "variable.declaration": "{{ foreground }}",
        "variable.readonly": "{{ bright_yellow }}",
        "variable.defaultLibrary": "{{ foreground }}",
        "property": "{{ cyan }}",
        "property.declaration": "{{ cyan }}",
        "property.readonly": "{{ cyan }}",
        "function": "{{ blue }}",
        "function.declaration": "{{ blue }}",
        "function.defaultLibrary": "{{ cyan }}",
        "method": "{{ blue }}",
        "method.declaration": "{{ blue }}",
        "class": "{{ yellow }}",
        "class.declaration": "{{ yellow }}",
        "class.defaultLibrary": "{{ yellow }}",
        "interface": "{{ yellow }}",
        "interface.declaration": "{{ yellow }}",
        "enum": "{{ yellow }}",
        "enumMember": "{{ orange }}",
        "type": "{{ yellow }}",
        "type.declaration": "{{ yellow }}",
        "type.defaultLibrary": "{{ foreground }}",
        "typeParameter": "{{ yellow }}",
        "namespace": "{{ blue }}",
        "macro": "{{ cyan }}",
        "decorator": "{{ blue }}",
        "string": "{{ green }}",
        "number": "{{ orange }}",
        "boolean": "{{ orange }}",
        "regexp": "{{ bright_cyan }}",
        "operator": "{{ bright_blue }}",
        "keyword": "{{ bright_purple }}",
        "comment": {"foreground": "{{ green }}", "fontStyle": "italic"},
        "comment.documentation": {"foreground": "{{ green }}", "fontStyle": "italic"}
    },
    "colors": {
        "foreground": "{{ foreground }}",
        "disabledForeground": "{{ dark_fg }}",
        "focusBorder": "{{ accent }}80",
        "widget.shadow": "{{ bg }}80",
        "selection.background": "{{ selection_background }}80",
        "descriptionForeground": "{{ muted }}",
        "errorForeground": "{{ red }}",
        "icon.foreground": "{{ foreground }}",
        "sash.hoverBorder": "{{ accent }}",

        "textBlockQuote.background": "{{ bg }}",
        "textBlockQuote.border": "{{ accent }}",
        "textCodeBlock.background": "{{ bg }}",
        "textLink.activeForeground": "{{ bright_blue }}",
        "textLink.foreground": "{{ blue }}",
        "textPreformat.foreground": "{{ cyan }}",
        "textPreformat.background": "{{ bg }}",
        "textSeparator.foreground": "{{ muted }}",

        "toolbar.hoverBackground": "{{ bg }}",
        "toolbar.activeBackground": "{{ muted }}",

        "button.background": "{{ accent }}",
        "button.foreground": "{{ background }}",
        "button.hoverBackground": "{{ blue }}",
        "button.secondaryForeground": "{{ foreground }}",
        "button.secondaryBackground": "{{ muted }}",
        "button.secondaryHoverBackground": "{{ bg }}",
        "button.border": "{{ accent }}20",
        "checkbox.background": "{{ bg }}",
        "checkbox.foreground": "{{ foreground }}",
        "checkbox.border": "{{ muted }}",
        "checkbox.selectBackground": "{{ accent }}",
        "checkbox.selectBorder": "{{ accent }}",

        "dropdown.background": "{{ bg }}",
        "dropdown.listBackground": "{{ bg }}",
        "dropdown.border": "{{ muted }}",
        "dropdown.foreground": "{{ foreground }}",

        "input.background": "{{ bg }}",
        "input.border": "{{ muted }}",
        "input.foreground": "{{ foreground }}",
        "input.placeholderForeground": "{{ muted }}",
        "inputOption.activeBackground": "{{ accent }}40",
        "inputOption.activeBorder": "{{ accent }}",
        "inputOption.activeForeground": "{{ foreground }}",
        "inputOption.hoverBackground": "{{ muted }}",
        "inputValidation.errorBackground": "{{ red }}20",
        "inputValidation.errorForeground": "{{ red }}",
        "inputValidation.errorBorder": "{{ red }}",
        "inputValidation.infoBackground": "{{ blue }}20",
        "inputValidation.infoForeground": "{{ blue }}",
        "inputValidation.infoBorder": "{{ blue }}",
        "inputValidation.warningBackground": "{{ yellow }}20",
        "inputValidation.warningForeground": "{{ yellow }}",
        "inputValidation.warningBorder": "{{ yellow }}",

        "scrollbar.shadow": "{{ bg }}",
        "scrollbarSlider.activeBackground": "{{ accent }}80",
        "scrollbarSlider.background": "{{ muted }}40",
        "scrollbarSlider.hoverBackground": "{{ muted }}80",

        "badge.background": "{{ accent }}",
        "badge.foreground": "{{ background }}",

        "progressBar.background": "{{ accent }}",

        "list.activeSelectionBackground": "{{ accent }}30",
        "list.activeSelectionForeground": "{{ foreground }}",
        "list.activeSelectionIconForeground": "{{ foreground }}",
        "list.dropBackground": "{{ accent }}20",
        "list.focusBackground": "{{ accent }}20",
        "list.focusForeground": "{{ foreground }}",
        "list.focusOutline": "{{ accent }}60",
        "list.highlightForeground": "{{ accent }}",
        "list.hoverBackground": "{{ bg }}",
        "list.hoverForeground": "{{ foreground }}",
        "list.inactiveSelectionBackground": "{{ muted }}40",
        "list.inactiveSelectionForeground": "{{ foreground }}",
        "list.inactiveFocusBackground": "{{ muted }}40",
        "list.inactiveFocusOutline": "{{ muted }}",
        "list.invalidItemForeground": "{{ red }}",
        "list.errorForeground": "{{ red }}",
        "list.warningForeground": "{{ yellow }}",
        "listFilterWidget.background": "{{ bg }}",
        "listFilterWidget.outline": "{{ accent }}",
        "listFilterWidget.noMatchesOutline": "{{ red }}",
        "list.filterMatchBackground": "{{ accent }}30",
        "list.filterMatchBorder": "{{ accent }}",
        "tree.indentGuidesStroke": "{{ muted }}",
        "tree.inactiveIndentGuidesStroke": "{{ muted }}60",
        "tree.tableColumnsBorder": "{{ muted }}",
        "tree.tableOddRowsBackground": "{{ bg }}40",

        "activityBar.background": "{{ background }}",
        "activityBar.dropBorder": "{{ accent }}",
        "activityBar.foreground": "{{ foreground }}",
        "activityBar.inactiveForeground": "{{ muted }}",
        "activityBar.border": "{{ bg }}",
        "activityBarBadge.background": "{{ accent }}",
        "activityBarBadge.foreground": "{{ background }}",
        "activityBar.activeBorder": "{{ accent }}",
        "activityBar.activeBackground": "{{ bg }}40",

        "sideBar.background": "{{ bg }}",
        "sideBar.foreground": "{{ foreground }}",
        "sideBar.border": "{{ bg }}",
        "sideBar.dropBackground": "{{ accent }}20",
        "sideBarTitle.foreground": "{{ foreground }}",
        "sideBarSectionHeader.background": "{{ bg }}",
        "sideBarSectionHeader.foreground": "{{ foreground }}",
        "sideBarSectionHeader.border": "{{ muted }}40",

        "minimap.findMatchHighlight": "{{ accent }}80",
        "minimap.selectionHighlight": "{{ accent }}60",
        "minimap.errorHighlight": "{{ red }}",
        "minimap.warningHighlight": "{{ yellow }}",
        "minimap.background": "{{ background }}",
        "minimap.selectionOccurrenceHighlight": "{{ accent }}40",
        "minimap.foregroundOpacity": "#000000c0",
        "minimapSlider.background": "{{ muted }}20",
        "minimapSlider.hoverBackground": "{{ muted }}40",
        "minimapSlider.activeBackground": "{{ muted }}60",
        "minimapGutter.addedBackground": "{{ green }}",
        "minimapGutter.modifiedBackground": "{{ orange }}",
        "minimapGutter.deletedBackground": "{{ red }}",

        "editorGroup.border": "{{ muted }}40",
        "editorGroup.dropBackground": "{{ accent }}20",
        "editorGroup.dropIntoPromptForeground": "{{ foreground }}",
        "editorGroup.dropIntoPromptBackground": "{{ bg }}",
        "editorGroup.dropIntoPromptBorder": "{{ accent }}",
        "editorGroupHeader.noTabsBackground": "{{ bg }}",
        "editorGroupHeader.tabsBackground": "{{ bg }}",
        "editorGroupHeader.tabsBorder": "{{ bg }}",
        "editorGroupHeader.border": "{{ bg }}",
        "editorGroup.emptyBackground": "{{ background }}",
        "tab.activeBackground": "{{ background }}",
        "tab.unfocusedActiveBackground": "{{ background }}",
        "tab.activeForeground": "{{ foreground }}",
        "tab.activeBorder": "{{ accent }}",
        "tab.activeBorderTop": "{{ accent }}",
        "tab.unfocusedActiveBorder": "{{ muted }}",
        "tab.unfocusedActiveBorderTop": "{{ muted }}",
        "tab.border": "{{ bg }}",
        "tab.inactiveBackground": "{{ bg }}",
        "tab.inactiveForeground": "{{ muted }}",
        "tab.unfocusedActiveForeground": "{{ fg }}",
        "tab.unfocusedInactiveForeground": "{{ muted }}",
        "tab.hoverBackground": "{{ muted }}40",
        "tab.unfocusedHoverBackground": "{{ muted }}40",
        "tab.hoverForeground": "{{ foreground }}",
        "tab.hoverBorder": "{{ accent }}40",
        "tab.activeModifiedBorder": "{{ yellow }}",
        "tab.inactiveModifiedBorder": "{{ yellow }}80",
        "tab.unfocusedActiveModifiedBorder": "{{ yellow }}80",
        "tab.unfocusedInactiveModifiedBorder": "{{ yellow }}60",
        "tab.lastPinnedBorder": "{{ muted }}",
        "editorPane.background": "{{ background }}",

        "editor.background": "{{ background }}",
        "editor.foreground": "{{ foreground }}",
        "editorLineNumber.foreground": "{{ muted }}",
        "editorLineNumber.activeForeground": "{{ foreground }}",
        "editorLineNumber.dimmedForeground": "{{ muted }}80",
        "editorCursor.background": "{{ background }}",
        "editorCursor.foreground": "{{ cursor }}",
        "editor.selectionBackground": "{{ selection_background }}60",
        "editor.selectionForeground": "{{ selection_foreground }}",
        "editor.inactiveSelectionBackground": "{{ selection_background }}30",
        "editor.selectionHighlightBackground": "{{ accent }}20",
        "editor.selectionHighlightBorder": "{{ accent }}40",
        "editor.wordHighlightBackground": "{{ accent }}20",
        "editor.wordHighlightBorder": "{{ accent }}40",
        "editor.wordHighlightStrongBackground": "{{ accent }}30",
        "editor.wordHighlightStrongBorder": "{{ accent }}60",
        "editor.wordHighlightTextBackground": "{{ accent }}15",
        "editor.wordHighlightTextBorder": "{{ accent }}30",
        "editor.findMatchBackground": "{{ yellow }}40",
        "editor.findMatchBorder": "{{ yellow }}",
        "editor.findMatchHighlightBackground": "{{ yellow }}25",
        "editor.findMatchHighlightBorder": "{{ yellow }}60",
        "editor.findRangeHighlightBackground": "{{ accent }}15",
        "editor.findRangeHighlightBorder": "{{ accent }}30",
        "searchEditor.findMatchBackground": "{{ yellow }}40",
        "searchEditor.findMatchBorder": "{{ yellow }}",
        "editor.hoverHighlightBackground": "{{ accent }}20",
        "editor.lineHighlightBackground": "{{ bg }}60",
        "editor.lineHighlightBorder": "{{ bg }}00",
        "editorLink.activeForeground": "{{ blue }}",
        "editor.rangeHighlightBackground": "{{ accent }}10",
        "editor.rangeHighlightBorder": "{{ accent }}20",
        "editor.symbolHighlightBackground": "{{ accent }}20",
        "editor.symbolHighlightBorder": "{{ accent }}40",
        "editorWhitespace.foreground": "{{ muted }}60",
        "editorIndentGuide.background1": "{{ muted }}30",
        "editorIndentGuide.background2": "{{ muted }}30",
        "editorIndentGuide.background3": "{{ muted }}30",
        "editorIndentGuide.background4": "{{ muted }}30",
        "editorIndentGuide.background5": "{{ muted }}30",
        "editorIndentGuide.background6": "{{ muted }}30",
        "editorIndentGuide.activeBackground1": "{{ muted }}80",
        "editorIndentGuide.activeBackground2": "{{ muted }}80",
        "editorIndentGuide.activeBackground3": "{{ muted }}80",
        "editorIndentGuide.activeBackground4": "{{ muted }}80",
        "editorIndentGuide.activeBackground5": "{{ muted }}80",
        "editorIndentGuide.activeBackground6": "{{ muted }}80",
        "editorInlayHint.background": "{{ muted }}30",
        "editorInlayHint.foreground": "{{ muted }}",
        "editorInlayHint.typeBackground": "{{ yellow }}15",
        "editorInlayHint.typeForeground": "{{ yellow }}",
        "editorInlayHint.parameterBackground": "{{ bright_purple }}15",
        "editorInlayHint.parameterForeground": "{{ bright_purple }}",
        "editorRuler.foreground": "{{ muted }}40",
        "editorCodeLens.foreground": "{{ muted }}",
        "editorLightBulb.foreground": "{{ yellow }}",
        "editorLightBulbAutoFix.foreground": "{{ green }}",
        "editorLightBulbAi.foreground": "{{ purple }}",
        "editorBracketMatch.background": "{{ accent }}30",
        "editorBracketMatch.border": "{{ accent }}",
        "editorBracketHighlight.foreground1": "{{ blue }}",
        "editorBracketHighlight.foreground2": "{{ yellow }}",
        "editorBracketHighlight.foreground3": "{{ green }}",
        "editorBracketHighlight.foreground4": "{{ cyan }}",
        "editorBracketHighlight.foreground5": "{{ purple }}",
        "editorBracketHighlight.foreground6": "{{ orange }}",
        "editorBracketHighlight.unexpectedBracket.foreground": "{{ red }}",
        "editorBracketPairGuide.activeBackground1": "{{ blue }}60",
        "editorBracketPairGuide.activeBackground2": "{{ yellow }}60",
        "editorBracketPairGuide.activeBackground3": "{{ green }}60",
        "editorBracketPairGuide.activeBackground4": "{{ cyan }}60",
        "editorBracketPairGuide.activeBackground5": "{{ purple }}60",
        "editorBracketPairGuide.activeBackground6": "{{ orange }}60",
        "editorBracketPairGuide.background1": "{{ blue }}30",
        "editorBracketPairGuide.background2": "{{ yellow }}30",
        "editorBracketPairGuide.background3": "{{ green }}30",
        "editorBracketPairGuide.background4": "{{ cyan }}30",
        "editorBracketPairGuide.background5": "{{ purple }}30",
        "editorBracketPairGuide.background6": "{{ orange }}30",
        "editorOverviewRuler.background": "{{ background }}",
        "editorOverviewRuler.border": "{{ muted }}20",
        "editorOverviewRuler.findMatchForeground": "{{ yellow }}80",
        "editorOverviewRuler.rangeHighlightForeground": "{{ accent }}60",
        "editorOverviewRuler.selectionHighlightForeground": "{{ accent }}80",
        "editorOverviewRuler.wordHighlightForeground": "{{ accent }}60",
        "editorOverviewRuler.wordHighlightStrongForeground": "{{ accent }}80",
        "editorOverviewRuler.wordHighlightTextForeground": "{{ accent }}40",
        "editorOverviewRuler.modifiedForeground": "{{ orange }}80",
        "editorOverviewRuler.addedForeground": "{{ green }}80",
        "editorOverviewRuler.deletedForeground": "{{ red }}80",
        "editorOverviewRuler.errorForeground": "{{ red }}",
        "editorOverviewRuler.warningForeground": "{{ yellow }}",
        "editorOverviewRuler.infoForeground": "{{ blue }}",
        "editorOverviewRuler.bracketMatchForeground": "{{ accent }}",
        "editorError.foreground": "{{ red }}",
        "editorError.background": "{{ red }}15",
        "editorError.border": "{{ red }}00",
        "editorWarning.foreground": "{{ yellow }}",
        "editorWarning.background": "{{ yellow }}15",
        "editorWarning.border": "{{ yellow }}00",
        "editorInfo.foreground": "{{ blue }}",
        "editorInfo.background": "{{ blue }}15",
        "editorInfo.border": "{{ blue }}00",
        "editorHint.foreground": "{{ cyan }}",
        "editorHint.border": "{{ cyan }}00",
        "problemsErrorIcon.foreground": "{{ red }}",
        "problemsWarningIcon.foreground": "{{ yellow }}",
        "problemsInfoIcon.foreground": "{{ blue }}",
        "editorUnnecessaryCode.opacity": "#00000080",
        "editorUnnecessaryCode.border": "{{ muted }}",
        "editorGutter.background": "{{ background }}",
        "editorGutter.modifiedBackground": "{{ orange }}",
        "editorGutter.addedBackground": "{{ green }}",
        "editorGutter.deletedBackground": "{{ red }}",
        "editorGutter.commentRangeForeground": "{{ muted }}",
        "editorGutter.commentGlyphForeground": "{{ accent }}",
        "editorGutter.commentUnresolvedGlyphForeground": "{{ yellow }}",
        "editorGutter.foldingControlForeground": "{{ muted }}",
        "editorCommentsWidget.resolvedBorder": "{{ green }}",
        "editorCommentsWidget.unresolvedBorder": "{{ yellow }}",
        "editorCommentsWidget.rangeBackground": "{{ accent }}10",
        "editorCommentsWidget.rangeActiveBackground": "{{ accent }}20",

        "diffEditor.insertedTextBackground": "{{ green }}20",
        "diffEditor.insertedTextBorder": "{{ green }}00",
        "diffEditor.removedTextBackground": "{{ red }}20",
        "diffEditor.removedTextBorder": "{{ red }}00",
        "diffEditor.insertedLineBackground": "{{ green }}15",
        "diffEditor.removedLineBackground": "{{ red }}15",
        "diffEditorGutter.insertedLineBackground": "{{ green }}30",
        "diffEditorGutter.removedLineBackground": "{{ red }}30",
        "diffEditorOverview.insertedForeground": "{{ green }}80",
        "diffEditorOverview.removedForeground": "{{ red }}80",
        "diffEditor.diagonalFill": "{{ muted }}30",
        "diffEditor.unchangedRegionBackground": "{{ bg }}",
        "diffEditor.unchangedRegionForeground": "{{ muted }}",
        "diffEditor.unchangedCodeBackground": "{{ bg }}40",
        "diffEditor.move.border": "{{ cyan }}80",
        "diffEditor.moveActive.border": "{{ cyan }}",

        "editorWidget.foreground": "{{ foreground }}",
        "editorWidget.background": "{{ bg }}",
        "editorWidget.border": "{{ muted }}",
        "editorWidget.resizeBorder": "{{ accent }}",
        "editorSuggestWidget.background": "{{ bg }}",
        "editorSuggestWidget.border": "{{ muted }}",
        "editorSuggestWidget.foreground": "{{ foreground }}",
        "editorSuggestWidget.focusHighlightForeground": "{{ accent }}",
        "editorSuggestWidget.highlightForeground": "{{ accent }}",
        "editorSuggestWidget.selectedBackground": "{{ accent }}30",
        "editorSuggestWidget.selectedForeground": "{{ foreground }}",
        "editorSuggestWidget.selectedIconForeground": "{{ foreground }}",
        "editorSuggestWidgetStatus.foreground": "{{ muted }}",
        "editorHoverWidget.foreground": "{{ foreground }}",
        "editorHoverWidget.background": "{{ bg }}",
        "editorHoverWidget.border": "{{ muted }}",
        "editorHoverWidget.highlightForeground": "{{ accent }}",
        "editorHoverWidget.statusBarBackground": "{{ muted }}30",
        "editorGhostText.foreground": "{{ muted }}",
        "editorGhostText.background": "{{ muted }}10",
        "editorGhostText.border": "{{ muted }}00",
        "editorStickyScroll.background": "{{ bg }}",
        "editorStickyScrollHover.background": "{{ muted }}40",
        "debugExceptionWidget.background": "{{ red }}20",
        "debugExceptionWidget.border": "{{ red }}",
        "editorMarkerNavigation.background": "{{ bg }}",
        "editorMarkerNavigationError.background": "{{ red }}20",
        "editorMarkerNavigationError.headerBackground": "{{ red }}15",
        "editorMarkerNavigationWarning.background": "{{ yellow }}20",
        "editorMarkerNavigationWarning.headerBackground": "{{ yellow }}15",
        "editorMarkerNavigationInfo.background": "{{ blue }}20",
        "editorMarkerNavigationInfo.headerBackground": "{{ blue }}15",

        "peekView.border": "{{ accent }}",
        "peekViewEditor.background": "{{ bg }}",
        "peekViewEditorGutter.background": "{{ bg }}",
        "peekViewEditor.matchHighlightBackground": "{{ yellow }}30",
        "peekViewEditor.matchHighlightBorder": "{{ yellow }}",
        "peekViewResult.background": "{{ background }}",
        "peekViewResult.fileForeground": "{{ foreground }}",
        "peekViewResult.lineForeground": "{{ muted }}",
        "peekViewResult.matchHighlightBackground": "{{ yellow }}30",
        "peekViewResult.selectionBackground": "{{ accent }}30",
        "peekViewResult.selectionForeground": "{{ foreground }}",
        "peekViewTitle.background": "{{ bg }}",
        "peekViewTitleDescription.foreground": "{{ muted }}",
        "peekViewTitleLabel.foreground": "{{ foreground }}",

        "merge.currentContentBackground": "{{ cyan }}20",
        "merge.currentHeaderBackground": "{{ cyan }}40",
        "merge.incomingContentBackground": "{{ green }}20",
        "merge.incomingHeaderBackground": "{{ green }}40",
        "merge.commonContentBackground": "{{ muted }}20",
        "merge.commonHeaderBackground": "{{ muted }}40",
        "merge.border": "{{ muted }}",
        "editorOverviewRuler.currentContentForeground": "{{ cyan }}",
        "editorOverviewRuler.incomingContentForeground": "{{ green }}",
        "editorOverviewRuler.commonContentForeground": "{{ muted }}",
        "mergeEditor.change.background": "{{ accent }}15",
        "mergeEditor.change.word.background": "{{ accent }}30",
        "mergeEditor.conflict.handledUnfocused.border": "{{ green }}80",
        "mergeEditor.conflict.handled.minimapOverViewRuler": "{{ green }}",
        "mergeEditor.conflict.unhandledUnfocused.border": "{{ yellow }}80",
        "mergeEditor.conflict.unhandled.minimapOverViewRuler": "{{ yellow }}",
        "mergeEditor.conflictingLines.background": "{{ yellow }}15",
        "mergeEditor.changeBase.background": "{{ muted }}20",
        "mergeEditor.changeBase.word.background": "{{ muted }}40",

        "panel.background": "{{ background }}",
        "panel.border": "{{ muted }}40",
        "panel.dropBorder": "{{ accent }}",
        "panelTitle.activeBorder": "{{ accent }}",
        "panelTitle.activeForeground": "{{ foreground }}",
        "panelTitle.inactiveForeground": "{{ muted }}",
        "panelInput.border": "{{ muted }}",
        "panelSection.border": "{{ muted }}40",
        "panelSection.dropBackground": "{{ accent }}20",
        "panelSectionHeader.background": "{{ bg }}",
        "panelSectionHeader.foreground": "{{ foreground }}",
        "panelSectionHeader.border": "{{ muted }}40",

        "outputView.background": "{{ background }}",
        "outputViewStickyScroll.background": "{{ bg }}",

        "statusBar.background": "{{ bg }}",
        "statusBar.foreground": "{{ foreground }}",
        "statusBar.border": "{{ bg }}",
        "statusBar.debuggingBackground": "{{ yellow }}",
        "statusBar.debuggingForeground": "{{ background }}",
        "statusBar.debuggingBorder": "{{ yellow }}",
        "statusBar.noFolderBackground": "{{ bg }}",
        "statusBar.noFolderForeground": "{{ foreground }}",
        "statusBar.noFolderBorder": "{{ bg }}",
        "statusBar.focusBorder": "{{ accent }}",
        "statusBarItem.activeBackground": "{{ muted }}",
        "statusBarItem.hoverBackground": "{{ muted }}60",
        "statusBarItem.hoverForeground": "{{ foreground }}",
        "statusBarItem.prominentForeground": "{{ foreground }}",
        "statusBarItem.prominentBackground": "{{ accent }}",
        "statusBarItem.prominentHoverBackground": "{{ accent }}80",
        "statusBarItem.remoteBackground": "{{ accent }}",
        "statusBarItem.remoteForeground": "{{ background }}",
        "statusBarItem.remoteHoverBackground": "{{ accent }}80",
        "statusBarItem.errorBackground": "{{ red }}",
        "statusBarItem.errorForeground": "{{ background }}",
        "statusBarItem.errorHoverBackground": "{{ red }}80",
        "statusBarItem.warningBackground": "{{ yellow }}",
        "statusBarItem.warningForeground": "{{ background }}",
        "statusBarItem.warningHoverBackground": "{{ yellow }}80",
        "statusBarItem.compactHoverBackground": "{{ muted }}",
        "statusBarItem.focusBorder": "{{ accent }}",

        "titleBar.activeBackground": "{{ bg }}",
        "titleBar.activeForeground": "{{ foreground }}",
        "titleBar.inactiveBackground": "{{ bg }}",
        "titleBar.inactiveForeground": "{{ muted }}",
        "titleBar.border": "{{ bg }}",

        "menubar.selectionForeground": "{{ foreground }}",
        "menubar.selectionBackground": "{{ accent }}30",
        "menubar.selectionBorder": "{{ accent }}00",
        "menu.foreground": "{{ foreground }}",
        "menu.background": "{{ bg }}",
        "menu.selectionForeground": "{{ foreground }}",
        "menu.selectionBackground": "{{ accent }}30",
        "menu.selectionBorder": "{{ accent }}00",
        "menu.separatorBackground": "{{ muted }}",
        "menu.border": "{{ muted }}",

        "commandCenter.foreground": "{{ foreground }}",
        "commandCenter.activeForeground": "{{ foreground }}",
        "commandCenter.background": "{{ bg }}",
        "commandCenter.activeBackground": "{{ muted }}",
        "commandCenter.border": "{{ muted }}",
        "commandCenter.inactiveForeground": "{{ muted }}",
        "commandCenter.inactiveBorder": "{{ muted }}",
        "commandCenter.activeBorder": "{{ accent }}",
        "commandCenter.debuggingBackground": "{{ yellow }}20",

        "notificationCenter.border": "{{ muted }}",
        "notificationCenterHeader.foreground": "{{ foreground }}",
        "notificationCenterHeader.background": "{{ bg }}",
        "notificationToast.border": "{{ muted }}",
        "notifications.foreground": "{{ foreground }}",
        "notifications.background": "{{ bg }}",
        "notifications.border": "{{ muted }}",
        "notificationLink.foreground": "{{ accent }}",
        "notificationsErrorIcon.foreground": "{{ red }}",
        "notificationsWarningIcon.foreground": "{{ yellow }}",
        "notificationsInfoIcon.foreground": "{{ blue }}",

        "banner.background": "{{ accent }}20",
        "banner.foreground": "{{ foreground }}",
        "banner.iconForeground": "{{ accent }}",

        "extensionButton.prominentBackground": "{{ accent }}",
        "extensionButton.prominentForeground": "{{ background }}",
        "extensionButton.prominentHoverBackground": "{{ accent }}80",
        "extensionButton.background": "{{ muted }}",
        "extensionButton.foreground": "{{ foreground }}",
        "extensionButton.hoverBackground": "{{ muted }}80",
        "extensionButton.separator": "{{ background }}",
        "extensionBadge.remoteBackground": "{{ accent }}",
        "extensionBadge.remoteForeground": "{{ background }}",
        "extensionIcon.starForeground": "{{ yellow }}",
        "extensionIcon.verifiedForeground": "{{ cyan }}",
        "extensionIcon.preReleaseForeground": "{{ yellow }}",
        "extensionIcon.sponsorForeground": "{{ purple }}",

        "pickerGroup.border": "{{ muted }}",
        "pickerGroup.foreground": "{{ accent }}",
        "quickInput.background": "{{ bg }}",
        "quickInput.foreground": "{{ foreground }}",
        "quickInputList.focusBackground": "{{ accent }}30",
        "quickInputList.focusForeground": "{{ foreground }}",
        "quickInputList.focusIconForeground": "{{ foreground }}",
        "quickInputTitle.background": "{{ bg }}",

        "keybindingLabel.background": "{{ muted }}40",
        "keybindingLabel.foreground": "{{ foreground }}",
        "keybindingLabel.border": "{{ muted }}",
        "keybindingLabel.bottomBorder": "{{ muted }}",
        "keybindingTable.headerBackground": "{{ bg }}",
        "keybindingTable.rowsBackground": "{{ bg }}40",

        "terminal.background": "{{ background }}",
        "terminal.foreground": "{{ foreground }}",
        "terminal.border": "{{ muted }}40",
        "terminal.selectionBackground": "{{ selection_background }}60",
        "terminal.selectionForeground": "{{ selection_foreground }}",
        "terminal.inactiveSelectionBackground": "{{ selection_background }}30",
        "terminal.findMatchBackground": "{{ yellow }}40",
        "terminal.findMatchBorder": "{{ yellow }}",
        "terminal.findMatchHighlightBackground": "{{ yellow }}25",
        "terminal.findMatchHighlightBorder": "{{ yellow }}60",
        "terminal.hoverHighlightBackground": "{{ accent }}20",
        "terminalCursor.background": "{{ background }}",
        "terminalCursor.foreground": "{{ cursor }}",
        "terminal.ansiBlack": "{{ bg }}",
        "terminal.ansiRed": "{{ red }}",
        "terminal.ansiGreen": "{{ green }}",
        "terminal.ansiYellow": "{{ yellow }}",
        "terminal.ansiBlue": "{{ blue }}",
        "terminal.ansiMagenta": "{{ purple }}",
        "terminal.ansiCyan": "{{ cyan }}",
        "terminal.ansiWhite": "{{ fg }}",
        "terminal.ansiBrightBlack": "{{ muted }}",
        "terminal.ansiBrightRed": "{{ bright_red }}",
        "terminal.ansiBrightGreen": "{{ bright_green }}",
        "terminal.ansiBrightYellow": "{{ bright_yellow }}",
        "terminal.ansiBrightBlue": "{{ bright_blue }}",
        "terminal.ansiBrightMagenta": "{{ bright_purple }}",
        "terminal.ansiBrightCyan": "{{ bright_cyan }}",
        "terminal.ansiBrightWhite": "{{ bright_fg }}",
        "terminal.tab.activeBorder": "{{ accent }}",
        "terminalCommandDecoration.defaultBackground": "{{ muted }}",
        "terminalCommandDecoration.successBackground": "{{ green }}",
        "terminalCommandDecoration.errorBackground": "{{ red }}",
        "terminalOverviewRuler.cursorForeground": "{{ cursor }}",
        "terminalOverviewRuler.findMatchForeground": "{{ yellow }}",
        "terminalStickyScroll.background": "{{ bg }}",
        "terminalStickyScrollHover.background": "{{ muted }}40",

        "debugToolBar.background": "{{ bg }}",
        "debugToolBar.border": "{{ muted }}",
        "debugView.stateLabelForeground": "{{ foreground }}",
        "debugView.stateLabelBackground": "{{ accent }}30",
        "debugView.valueChangedHighlight": "{{ cyan }}40",
        "debugView.exceptionLabelForeground": "{{ background }}",
        "debugView.exceptionLabelBackground": "{{ red }}",
        "debugTokenExpression.name": "{{ purple }}",
        "debugTokenExpression.value": "{{ foreground }}",
        "debugTokenExpression.string": "{{ green }}",
        "debugTokenExpression.boolean": "{{ orange }}",
        "debugTokenExpression.number": "{{ orange }}",
        "debugTokenExpression.error": "{{ red }}",

        "testing.iconFailed": "{{ red }}",
        "testing.iconErrored": "{{ red }}",
        "testing.iconPassed": "{{ green }}",
        "testing.runAction": "{{ green }}",
        "testing.iconQueued": "{{ yellow }}",
        "testing.iconUnset": "{{ muted }}",
        "testing.iconSkipped": "{{ yellow }}",
        "testing.peekBorder": "{{ accent }}",
        "testing.peekHeaderBackground": "{{ bg }}",
        "testing.message.error.decorationForeground": "{{ red }}",
        "testing.message.error.lineBackground": "{{ red }}15",
        "testing.message.info.decorationForeground": "{{ blue }}",
        "testing.message.info.lineBackground": "{{ blue }}15",

        "welcomePage.background": "{{ background }}",
        "welcomePage.tileBackground": "{{ bg }}",
        "welcomePage.tileHoverBackground": "{{ muted }}40",
        "welcomePage.tileBorder": "{{ muted }}",
        "welcomePage.progress.background": "{{ muted }}",
        "welcomePage.progress.foreground": "{{ accent }}",
        "walkThrough.embeddedEditorBackground": "{{ bg }}",
        "walkthrough.stepTitle.foreground": "{{ foreground }}",

        "gitDecoration.addedResourceForeground": "{{ green }}",
        "gitDecoration.modifiedResourceForeground": "{{ orange }}",
        "gitDecoration.deletedResourceForeground": "{{ red }}",
        "gitDecoration.renamedResourceForeground": "{{ cyan }}",
        "gitDecoration.stageModifiedResourceForeground": "{{ orange }}",
        "gitDecoration.stageDeletedResourceForeground": "{{ red }}",
        "gitDecoration.untrackedResourceForeground": "{{ green }}",
        "gitDecoration.ignoredResourceForeground": "{{ muted }}",
        "gitDecoration.conflictingResourceForeground": "{{ yellow }}",
        "gitDecoration.submoduleResourceForeground": "{{ purple }}",

        "settings.headerForeground": "{{ foreground }}",
        "settings.modifiedItemIndicator": "{{ accent }}",
        "settings.dropdownBackground": "{{ bg }}",
        "settings.dropdownForeground": "{{ foreground }}",
        "settings.dropdownBorder": "{{ muted }}",
        "settings.dropdownListBorder": "{{ muted }}",
        "settings.checkboxBackground": "{{ bg }}",
        "settings.checkboxForeground": "{{ foreground }}",
        "settings.checkboxBorder": "{{ muted }}",
        "settings.rowHoverBackground": "{{ bg }}",
        "settings.textInputBackground": "{{ bg }}",
        "settings.textInputForeground": "{{ foreground }}",
        "settings.textInputBorder": "{{ muted }}",
        "settings.numberInputBackground": "{{ bg }}",
        "settings.numberInputForeground": "{{ foreground }}",
        "settings.numberInputBorder": "{{ muted }}",
        "settings.focusedRowBackground": "{{ accent }}10",
        "settings.focusedRowBorder": "{{ accent }}40",
        "settings.headerBorder": "{{ muted }}",
        "settings.sashBorder": "{{ muted }}",
        "settings.settingsHeaderHoverForeground": "{{ accent }}",

        "breadcrumb.foreground": "{{ muted }}",
        "breadcrumb.background": "{{ background }}",
        "breadcrumb.focusForeground": "{{ foreground }}",
        "breadcrumb.activeSelectionForeground": "{{ foreground }}",
        "breadcrumbPicker.background": "{{ bg }}",

        "editor.snippetTabstopHighlightBackground": "{{ accent }}20",
        "editor.snippetTabstopHighlightBorder": "{{ accent }}40",
        "editor.snippetFinalTabstopHighlightBackground": "{{ green }}20",
        "editor.snippetFinalTabstopHighlightBorder": "{{ green }}40",

        "symbolIcon.arrayForeground": "{{ orange }}",
        "symbolIcon.booleanForeground": "{{ orange }}",
        "symbolIcon.classForeground": "{{ yellow }}",
        "symbolIcon.colorForeground": "{{ cyan }}",
        "symbolIcon.constantForeground": "{{ bright_yellow }}",
        "symbolIcon.constructorForeground": "{{ blue }}",
        "symbolIcon.enumeratorForeground": "{{ yellow }}",
        "symbolIcon.enumeratorMemberForeground": "{{ orange }}",
        "symbolIcon.eventForeground": "{{ yellow }}",
        "symbolIcon.fieldForeground": "{{ foreground }}",
        "symbolIcon.fileForeground": "{{ foreground }}",
        "symbolIcon.folderForeground": "{{ foreground }}",
        "symbolIcon.functionForeground": "{{ blue }}",
        "symbolIcon.interfaceForeground": "{{ yellow }}",
        "symbolIcon.keyForeground": "{{ bright_purple }}",
        "symbolIcon.keywordForeground": "{{ bright_purple }}",
        "symbolIcon.methodForeground": "{{ blue }}",
        "symbolIcon.moduleForeground": "{{ yellow }}",
        "symbolIcon.namespaceForeground": "{{ blue }}",
        "symbolIcon.nullForeground": "{{ orange }}",
        "symbolIcon.numberForeground": "{{ orange }}",
        "symbolIcon.objectForeground": "{{ yellow }}",
        "symbolIcon.operatorForeground": "{{ bright_blue }}",
        "symbolIcon.packageForeground": "{{ yellow }}",
        "symbolIcon.propertyForeground": "{{ foreground }}",
        "symbolIcon.referenceForeground": "{{ bright_purple }}",
        "symbolIcon.snippetForeground": "{{ green }}",
        "symbolIcon.stringForeground": "{{ green }}",
        "symbolIcon.structForeground": "{{ yellow }}",
        "symbolIcon.textForeground": "{{ foreground }}",
        "symbolIcon.typeParameterForeground": "{{ yellow }}",
        "symbolIcon.unitForeground": "{{ orange }}",
        "symbolIcon.variableForeground": "{{ bright_purple }}",

        "debugIcon.breakpointForeground": "{{ red }}",
        "debugIcon.breakpointDisabledForeground": "{{ muted }}",
        "debugIcon.breakpointUnverifiedForeground": "{{ yellow }}",
        "debugIcon.breakpointCurrentStackframeForeground": "{{ yellow }}",
        "debugIcon.breakpointStackframeForeground": "{{ green }}",
        "debugIcon.startForeground": "{{ green }}",
        "debugIcon.pauseForeground": "{{ yellow }}",
        "debugIcon.stopForeground": "{{ red }}",
        "debugIcon.disconnectForeground": "{{ red }}",
        "debugIcon.restartForeground": "{{ green }}",
        "debugIcon.stepOverForeground": "{{ blue }}",
        "debugIcon.stepIntoForeground": "{{ cyan }}",
        "debugIcon.stepOutForeground": "{{ purple }}",
        "debugIcon.continueForeground": "{{ green }}",
        "debugIcon.stepBackForeground": "{{ yellow }}",
        "debugConsole.infoForeground": "{{ blue }}",
        "debugConsole.warningForeground": "{{ yellow }}",
        "debugConsole.errorForeground": "{{ red }}",
        "debugConsole.sourceForeground": "{{ foreground }}",
        "debugConsoleInputIcon.foreground": "{{ accent }}",

        "notebook.editorBackground": "{{ background }}",
        "notebook.cellBorderColor": "{{ muted }}40",
        "notebook.cellHoverBackground": "{{ bg }}40",
        "notebook.cellInsertionIndicator": "{{ accent }}",
        "notebook.cellStatusBarItemHoverBackground": "{{ muted }}",
        "notebook.cellToolbarSeparator": "{{ muted }}",
        "notebook.cellEditorBackground": "{{ bg }}",
        "notebook.focusedCellBackground": "{{ bg }}60",
        "notebook.focusedCellBorder": "{{ accent }}",
        "notebook.focusedEditorBorder": "{{ accent }}",
        "notebook.inactiveFocusedCellBorder": "{{ muted }}",
        "notebook.inactiveSelectedCellBorder": "{{ muted }}",
        "notebook.outputContainerBackgroundColor": "{{ bg }}",
        "notebook.outputContainerBorderColor": "{{ muted }}40",
        "notebook.selectedCellBackground": "{{ accent }}15",
        "notebook.selectedCellBorder": "{{ accent }}40",
        "notebook.symbolHighlightBackground": "{{ accent }}20",
        "notebookStatusErrorIcon.foreground": "{{ red }}",
        "notebookStatusRunningIcon.foreground": "{{ accent }}",
        "notebookStatusSuccessIcon.foreground": "{{ green }}",
        "notebookEditorOverviewRuler.runningCellForeground": "{{ accent }}",

        "charts.foreground": "{{ foreground }}",
        "charts.lines": "{{ muted }}",
        "charts.red": "{{ red }}",
        "charts.blue": "{{ blue }}",
        "charts.yellow": "{{ yellow }}",
        "charts.orange": "{{ orange }}",
        "charts.green": "{{ green }}",
        "charts.purple": "{{ purple }}",

        "ports.iconRunningProcessForeground": "{{ accent }}",

        "commentsView.resolvedIcon": "{{ green }}",
        "commentsView.unresolvedIcon": "{{ yellow }}",

        "editorWatermark.foreground": "{{ muted }}",

        "inlineChat.background": "{{ bg }}",
        "inlineChat.border": "{{ muted }}",
        "inlineChat.shadow": "{{ bg }}80",
        "inlineChatInput.border": "{{ muted }}",
        "inlineChatInput.focusBorder": "{{ accent }}",
        "inlineChatInput.placeholderForeground": "{{ muted }}",
        "inlineChatInput.background": "{{ background }}",
        "inlineChatDiff.inserted": "{{ green }}20",
        "inlineChatDiff.removed": "{{ red }}20",

        "chat.requestBackground": "{{ bg }}",
        "chat.requestBorder": "{{ muted }}"
    },
    "tokenColors": [
        {
            "name": "Comment",
            "scope": ["comment", "punctuation.definition.comment"],
            "settings": {
                "fontStyle": "italic",
                "foreground": "{{ green }}"
            }
        },
        {
            "name": "Variable",
            "scope": ["variable", "string constant.other.placeholder"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "Variable Parameter",
            "scope": ["variable.parameter", "entity.name.variable.parameter", "meta.function.parameter"],
            "settings": {
                "foreground": "{{ cyan }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Variable Property",
            "scope": ["variable.other.property", "variable.other.object.property"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "Variable Constant",
            "scope": ["variable.other.constant"],
            "settings": {
                "foreground": "{{ bright_yellow }}"
            }
        },
        {
            "name": "Enum Member",
            "scope": ["variable.other.enummember"],
            "settings": {
                "foreground": "{{ orange }}"
            }
        },
        {
            "name": "Invalid",
            "scope": ["invalid", "invalid.illegal"],
            "settings": {
                "foreground": "{{ red }}",
                "fontStyle": "strikethrough"
            }
        },
        {
            "name": "Invalid Deprecated",
            "scope": ["invalid.deprecated"],
            "settings": {
                "foreground": "{{ yellow }}",
                "fontStyle": "strikethrough"
            }
        },
        {
            "name": "Keyword",
            "scope": ["keyword", "storage.type.class", "storage.type.function"],
            "settings": {
                "foreground": "{{ bright_purple }}"
            }
        },
        {
            "name": "Storage Modifier",
            "scope": ["storage.modifier"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "Keyword Control",
            "scope": ["keyword.control", "keyword.control.flow"],
            "settings": {
                "foreground": "{{ bright_purple }}"
            }
        },
        {
            "name": "Keyword Import",
            "scope": ["keyword.control.import", "keyword.control.export", "keyword.control.from", "keyword.control.as"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Keyword Operator",
            "scope": ["keyword.operator", "keyword.operator.new", "keyword.operator.expression", "keyword.operator.logical", "keyword.operator.comparison"],
            "settings": {
                "foreground": "{{ bright_blue }}"
            }
        },
        {
            "name": "Operator",
            "scope": ["punctuation.accessor", "punctuation.separator.key-value"],
            "settings": {
                "foreground": "{{ bright_blue }}"
            }
        },
        {
            "name": "Type",
            "scope": ["storage.type", "entity.name.type"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "Type Builtin",
            "scope": ["storage.type.primitive", "support.type"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "Type Class",
            "scope": ["entity.name.type.class", "support.class", "entity.other.inherited-class"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "Type Interface",
            "scope": ["entity.name.type.interface"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "Type Enum",
            "scope": ["entity.name.type.enum"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "Type Parameter",
            "scope": ["entity.name.type.parameter"],
            "settings": {
                "foreground": "{{ yellow }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Namespace",
            "scope": ["entity.name.namespace", "entity.name.type.module"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Function",
            "scope": ["entity.name.function", "meta.function-call.generic"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Function Builtin",
            "scope": ["support.function"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "Function Method",
            "scope": ["entity.name.function.method", "meta.method.declaration"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Function Decorator",
            "scope": ["entity.name.function.decorator", "meta.decorator", "punctuation.decorator"],
            "settings": {
                "foreground": "{{ cyan }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Punctuation",
            "scope": ["punctuation", "meta.brace", "meta.bracket"],
            "settings": {
                "foreground": "{{ dark_fg }}"
            }
        },
        {
            "name": "Constant Numeric",
            "scope": ["constant.numeric", "constant.numeric.integer", "constant.numeric.float", "constant.numeric.hex", "constant.numeric.octal", "constant.numeric.binary"],
            "settings": {
                "foreground": "{{ orange }}"
            }
        },
        {
            "name": "Constant Boolean",
            "scope": ["constant.language.boolean"],
            "settings": {
                "foreground": "{{ orange }}"
            }
        },
        {
            "name": "Constant Builtin",
            "scope": ["constant.language", "constant.language.null", "constant.language.undefined"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "Constant Character",
            "scope": ["constant.character"],
            "settings": {
                "foreground": "{{ green }}"
            }
        },
        {
            "name": "Constant Character Escape",
            "scope": ["constant.character.escape"],
            "settings": {
                "foreground": "{{ bright_purple }}"
            }
        },
        {
            "name": "String",
            "scope": ["string", "string.quoted", "string.template"],
            "settings": {
                "foreground": "{{ green }}"
            }
        },
        {
            "name": "String Interpolation",
            "scope": ["punctuation.definition.template-expression", "punctuation.section.embedded", "meta.embedded.line"],
            "settings": {
                "foreground": "{{ bright_blue }}"
            }
        },
        {
            "name": "String Regexp",
            "scope": ["string.regexp", "constant.other.character-class.regexp", "constant.character.escape.regexp"],
            "settings": {
                "foreground": "{{ bright_cyan }}"
            }
        },
        {
            "name": "Support",
            "scope": ["support.type.property-name", "support.constant"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "Tag",
            "scope": ["entity.name.tag", "meta.tag"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "Tag Attribute",
            "scope": ["entity.other.attribute-name"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "CSS Property",
            "scope": ["support.type.property-name.css", "support.type.vendored.property-name.css", "meta.property-name.css"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "CSS Value",
            "scope": ["support.constant.property-value.css", "meta.property-value.css"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "CSS Selector",
            "scope": ["entity.other.attribute-name.class.css", "entity.other.attribute-name.id.css"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "CSS Pseudo",
            "scope": ["entity.other.attribute-name.pseudo-class.css", "entity.other.attribute-name.pseudo-element.css"],
            "settings": {
                "foreground": "{{ cyan }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "CSS Units",
            "scope": ["keyword.other.unit.css"],
            "settings": {
                "foreground": "{{ orange }}"
            }
        },
        {
            "name": "JSON Key Level 0",
            "scope": ["source.json meta.structure.dictionary.json support.type.property-name.json"],
            "settings": {
                "foreground": "{{ orange }}"
            }
        },
        {
            "name": "JSON Key Level 1",
            "scope": ["source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "JSON Key Level 2",
            "scope": ["source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "JSON Key Level 3",
            "scope": ["source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json"],
            "settings": {
                "foreground": "{{ bright_purple }}"
            }
        },
        {
            "name": "JSON Key Level 4",
            "scope": ["source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "JSON Key Level 5+",
            "scope": ["source.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json meta.structure.dictionary.value.json meta.structure.dictionary.json support.type.property-name.json"],
            "settings": {
                "foreground": "{{ green }}"
            }
        },
        {
            "name": "Markdown Heading",
            "scope": ["markup.heading", "entity.name.section.markdown", "punctuation.definition.heading.markdown"],
            "settings": {
                "foreground": "{{ blue }}",
                "fontStyle": "bold"
            }
        },
        {
            "name": "Markdown Bold",
            "scope": ["markup.bold", "punctuation.definition.bold.markdown"],
            "settings": {
                "foreground": "{{ foreground }}",
                "fontStyle": "bold"
            }
        },
        {
            "name": "Markdown Italic",
            "scope": ["markup.italic", "punctuation.definition.italic.markdown"],
            "settings": {
                "foreground": "{{ foreground }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Markdown Link",
            "scope": ["markup.underline.link", "string.other.link.title.markdown", "string.other.link.description.markdown"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Markdown Code",
            "scope": ["markup.inline.raw", "markup.fenced_code.block", "markup.raw.block"],
            "settings": {
                "foreground": "{{ green }}"
            }
        },
        {
            "name": "Markdown Quote",
            "scope": ["markup.quote", "punctuation.definition.quote.begin.markdown"],
            "settings": {
                "foreground": "{{ muted }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Markdown List",
            "scope": ["punctuation.definition.list.begin.markdown", "markup.list.numbered", "markup.list.unnumbered"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "Diff Inserted",
            "scope": ["markup.inserted", "punctuation.definition.inserted"],
            "settings": {
                "foreground": "{{ green }}"
            }
        },
        {
            "name": "Diff Deleted",
            "scope": ["markup.deleted", "punctuation.definition.deleted"],
            "settings": {
                "foreground": "{{ red }}"
            }
        },
        {
            "name": "Diff Changed",
            "scope": ["markup.changed", "punctuation.definition.changed"],
            "settings": {
                "foreground": "{{ orange }}"
            }
        },
        {
            "name": "This/Self",
            "scope": ["variable.language.this", "variable.language.self", "variable.language.special.self"],
            "settings": {
                "foreground": "{{ foreground }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Object Keys",
            "scope": ["meta.object-literal.key", "string.unquoted.label.js"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "Rust Lifetime",
            "scope": ["entity.name.type.lifetime.rust", "punctuation.definition.lifetime.rust"],
            "settings": {
                "foreground": "{{ cyan }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Rust Macro",
            "scope": ["entity.name.function.macro.rust", "support.function.macro.rust"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "Shell Variable",
            "scope": ["variable.other.normal.shell", "variable.other.positional.shell", "variable.other.bracket.shell"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "Shell Command",
            "scope": ["entity.name.command.shell"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Shell Builtin",
            "scope": ["support.function.builtin.shell"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "YAML Key",
            "scope": ["entity.name.tag.yaml"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "TOML Key",
            "scope": ["keyword.key.toml", "support.type.property-name.toml"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "TOML Table",
            "scope": ["entity.other.attribute-name.table.toml", "support.type.property-name.table.toml"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "INI Section",
            "scope": ["entity.name.section.group-title.ini", "punctuation.definition.entity.ini"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "INI Key",
            "scope": ["keyword.other.definition.ini"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "Make Target",
            "scope": ["entity.name.function.target.makefile"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Make Variable",
            "scope": ["variable.other.makefile"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "Go Package",
            "scope": ["entity.name.package.go"],
            "settings": {
                "foreground": "{{ blue }}"
            }
        },
        {
            "name": "Python Self",
            "scope": ["variable.parameter.function.language.special.self.python"],
            "settings": {
                "foreground": "{{ foreground }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "Python Magic",
            "scope": ["support.function.magic.python", "support.variable.magic.python"],
            "settings": {
                "foreground": "{{ cyan }}",
                "fontStyle": "italic"
            }
        },
        {
            "name": "PHP Variable",
            "scope": ["variable.other.php", "punctuation.definition.variable.php"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        },
        {
            "name": "C Preprocessor",
            "scope": ["meta.preprocessor.c", "meta.preprocessor.include.c", "keyword.control.directive.include.c"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "C# Attribute",
            "scope": ["meta.attribute.csharp", "entity.name.type.attribute.csharp"],
            "settings": {
                "foreground": "{{ cyan }}"
            }
        },
        {
            "name": "SQL Keyword",
            "scope": ["keyword.other.DML.sql", "keyword.other.DDL.sql"],
            "settings": {
                "foreground": "{{ bright_purple }}"
            }
        },
        {
            "name": "GraphQL Type",
            "scope": ["support.type.graphql", "entity.name.type.graphql"],
            "settings": {
                "foreground": "{{ yellow }}"
            }
        },
        {
            "name": "GraphQL Field",
            "scope": ["variable.graphql", "variable.other.graphql"],
            "settings": {
                "foreground": "{{ foreground }}"
            }
        }
    ]
}
