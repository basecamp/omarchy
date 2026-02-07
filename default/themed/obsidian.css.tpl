/* Omarchy Theme for Obsidian */

.theme-dark, .theme-light {
  /* Core colors */
  --background-primary: {{ background }};
  --background-primary-alt: {{ background }};
  --background-secondary: {{ background }};
  --background-secondary-alt: {{ background }};
  --text-normal: {{ foreground }};

  /* Selection colors */
  --text-selection: {{ selection_background }};

  /* Border color */
  --background-modifier-border: {{ muted }};

  /* Semantic heading colors */
  --text-title-h1: {{ red }};
  --text-title-h2: {{ green }};
  --text-title-h3: {{ yellow }};
  --text-title-h4: {{ blue }};
  --text-title-h5: {{ purple }};
  --text-title-h6: {{ purple }};

  /* Links and accents */
  --text-link: {{ blue }};
  --text-accent: {{ accent }};
  --text-accent-hover: {{ accent }};
  --interactive-accent: {{ accent }};
  --interactive-accent-hover: {{ accent }};

  /* Muted text */
  --text-muted: {{ muted }};
  --text-faint: {{ muted }};

  /* Code */
  --code-normal: {{ cyan }};

  /* Errors and success */
  --text-error: {{ red }};
  --text-error-hover: {{ red }};
  --text-success: {{ green }};

  /* Tags */
  --tag-color: {{ cyan }};
  --tag-background: {{ muted }};

  /* Graph */
  --graph-line: {{ muted }};
  --graph-node: {{ accent }};
  --graph-node-focused: {{ blue }};
  --graph-node-tag: {{ cyan }};
  --graph-node-attachment: {{ green }};
}

/* Headers */
.cm-header-1, .markdown-rendered h1 { color: var(--text-title-h1); }
.cm-header-2, .markdown-rendered h2 { color: var(--text-title-h2); }
.cm-header-3, .markdown-rendered h3 { color: var(--text-title-h3); }
.cm-header-4, .markdown-rendered h4 { color: var(--text-title-h4); }
.cm-header-5, .markdown-rendered h5 { color: var(--text-title-h5); }
.cm-header-6, .markdown-rendered h6 { color: var(--text-title-h6); }

/* Code blocks */
.markdown-rendered code {
  color: {{ cyan }};
}

/* Syntax highlighting */
.cm-s-obsidian span.cm-keyword { color: {{ red }}; }
.cm-s-obsidian span.cm-string { color: {{ green }}; }
.cm-s-obsidian span.cm-number { color: {{ yellow }}; }
.cm-s-obsidian span.cm-comment { color: {{ muted }}; }
.cm-s-obsidian span.cm-operator { color: {{ blue }}; }
.cm-s-obsidian span.cm-def { color: {{ blue }}; }

/* Links */
.markdown-rendered a {
  color: var(--text-link);
}

/* Blockquotes */
.markdown-rendered blockquote {
  border-left-color: {{ accent }};
}

/* Active elements */
.workspace-leaf.mod-active .workspace-leaf-header-title {
  color: var(--interactive-accent);
}

.nav-file-title.is-active {
  color: var(--interactive-accent);
}

/* Search results */
.search-result-file-title {
  color: var(--interactive-accent);
}
