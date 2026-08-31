/* Omarchy Production-Grade Theme & Snippet for Obsidian (v1.0+) */

.theme-dark, .theme-light {
  /* =========================================
     CORE BACKGROUND & TEXT
     ========================================= */
  --background-primary: {{ background }};
  --background-primary-alt: {{ mix background foreground 4% }};
  --background-secondary: {{ mix background foreground 8% }};
  --background-secondary-alt: {{ mix background foreground 12% }};
  
  --text-normal: {{ foreground }};
  --text-muted: {{ mix background foreground 70% }};
  --text-faint: {{ mix background foreground 45% }};
  
  /* =========================================
     ACCENT, INTERACTIVE & SELECTION
     ========================================= */
  --text-accent: {{ accent }};
  --text-accent-hover: {{ mix accent foreground 20% }};
  --text-on-accent: {{ background }};
  --interactive-accent: {{ accent }};
  --interactive-accent-hover: {{ mix accent foreground 20% }};
  --interactive-hover: {{ mix background foreground 12% }};
  --text-selection: {{ selection }};
  
  /* =========================================
     BORDERS
     ========================================= */
  --background-modifier-border: {{ mix background foreground 15% }};
  --background-modifier-border-hover: {{ mix background foreground 30% }};
  --background-modifier-border-focus: {{ accent }};
  
  /* =========================================
     NAVIGATION & FILE EXPLORER (V1.0+)
     ========================================= */
  --nav-item-color: {{ mix background foreground 75% }};
  --nav-item-color-hover: {{ foreground }};
  --nav-item-color-active: {{ background }};
  --nav-item-background-active: {{ accent }};
  --nav-item-background-hover: {{ mix background foreground 10% }};

  /* =========================================
     MARKDOWN RENDERED HEADINGS
     ========================================= */
  --h1-color: {{ red }};
  --h2-color: {{ green }};
  --h3-color: {{ yellow }};
  --h4-color: {{ blue }};
  --h5-color: {{ magenta }};
  --h6-color: {{ cyan }};
  
  --text-title-h1: var(--h1-color);
  --text-title-h2: var(--h2-color);
  --text-title-h3: var(--h3-color);
  --text-title-h4: var(--h4-color);
  --text-title-h5: var(--h5-color);
  --text-title-h6: var(--h6-color);

  /* =========================================
     INLINE STYLES & LINKS
     ========================================= */
  --text-link: {{ blue }};
  --text-link-hover: {{ cyan }};
  --text-highlight-bg: {{ mix accent background 30% }};
  --bold-color: {{ foreground }};
  --italic-color: {{ mix background foreground 80% }};

  /* =========================================
     CODE BLOCKS & SYNTAX
     ========================================= */
  --code-normal: {{ foreground }};
  --code-background: {{ mix background foreground 6% }};
  --code-comment: {{ mix background foreground 50% }};
  --code-function: {{ blue }};
  --code-important: {{ red }};
  --code-keyword: {{ magenta }};
  --code-property: {{ cyan }};
  --code-string: {{ green }};
  --code-value: {{ yellow }};

  /* =========================================
     CALLOUTS
     ========================================= */
  --callout-info: {{ mix blue background 40% }};
  --callout-note: {{ mix blue background 40% }};
  --callout-success: {{ mix green background 40% }};
  --callout-warning: {{ mix yellow background 40% }};
  --callout-error: {{ mix red background 40% }};

  /* =========================================
     GRAPHS
     ========================================= */
  --graph-node: {{ accent }};
  --graph-node-unresolved: {{ mix background foreground 40% }};
  --graph-node-focused: {{ magenta }};
  --graph-node-tag: {{ cyan }};
  --graph-node-attachment: {{ green }};
  --graph-line: {{ mix background foreground 20% }};
}

/* =========================================
   UI COMPONENTS (OBSIDIAN V1.0+)
   ========================================= */
   
/* Workspace Tabs */
.workspace-tab-header.is-active {
  background-color: var(--background-primary);
  color: var(--text-normal);
  border-top: 2px solid var(--interactive-accent);
}

.workspace-tab-header {
  background-color: var(--background-secondary);
  color: var(--text-muted);
}

/* File Explorer */
.tree-item-self.is-active,
.nav-file-title.is-active,
.nav-folder-title.is-active {
  background-color: var(--nav-item-background-active);
  color: var(--nav-item-color-active) !important;
  font-weight: 600;
}

.tree-item-self.is-active .tree-item-inner,
.nav-file-title.is-active .nav-file-title-content,
.nav-folder-title.is-active .nav-folder-title-content {
  color: var(--nav-item-color-active) !important;
}

.tree-item-self:hover,
.nav-file-title:hover,
.nav-folder-title:hover {
  background-color: var(--nav-item-background-hover);
  color: var(--nav-item-color-hover);
}

/* Sidebar ribbon & action icons */
.side-dock-ribbon-action,
.nav-action-button,
.clickable-icon {
  color: var(--text-muted);
}

.side-dock-ribbon-action:hover,
.nav-action-button:hover,
.clickable-icon:hover {
  color: var(--text-normal);
}

.side-dock-ribbon-action.is-active,
.clickable-icon.is-active {
  color: var(--text-accent);
}

/* Status Bar */
.status-bar {
  background-color: var(--background-secondary-alt);
  border-top: 1px solid var(--background-modifier-border);
  color: var(--text-muted);
}

/* Modals */
.modal {
  background-color: var(--background-primary);
  border: 1px solid var(--background-modifier-border);
}

/* =========================================
   MARKDOWN CONTENT OVERRIDES
   ========================================= */

/* Code block backgrounds */
.markdown-rendered pre {
  background-color: var(--code-background);
  border: 1px solid var(--background-modifier-border);
}

/* Inline code */
.markdown-rendered code {
  color: var(--code-normal);
  background-color: var(--code-background);
}

/* Links */
.markdown-rendered a {
  color: var(--text-link);
  text-decoration: none;
}
.markdown-rendered a:hover {
  color: var(--text-link-hover);
  text-decoration: underline;
}

/* Checkbox */
.task-list-item-checkbox:checked {
  background-color: var(--interactive-accent);
  border-color: var(--interactive-accent);
}

/* Syntax Highlighting */
.cm-s-obsidian span.cm-keyword { color: var(--code-keyword); }
.cm-s-obsidian span.cm-string { color: var(--code-string); }
.cm-s-obsidian span.cm-number { color: var(--code-value); }
.cm-s-obsidian span.cm-comment { color: var(--code-comment); }
.cm-s-obsidian span.cm-operator { color: var(--code-property); }
.cm-s-obsidian span.cm-def { color: var(--code-function); }
