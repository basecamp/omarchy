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
  --background-modifier-border: {{ base10 }};

  /* Semantic heading colors */
  --text-title-h1: {{ base09 }};
  --text-title-h2: {{ base0A }};
  --text-title-h3: {{ base0B }};
  --text-title-h4: {{ base0C }};
  --text-title-h5: {{ base0D }};
  --text-title-h6: {{ base0D }};

  /* Links and accents */
  --text-link: {{ base0C }};
  --text-accent: {{ accent }};
  --text-accent-hover: {{ accent }};
  --interactive-accent: {{ accent }};
  --interactive-accent-hover: {{ accent }};

  /* Muted text */
  --text-muted: {{ base10 }};
  --text-faint: {{ base10 }};

  /* Code */
  --code-normal: {{ base0E }};

  /* Errors and success */
  --text-error: {{ base09 }};
  --text-error-hover: {{ base09 }};
  --text-success: {{ base0A }};

  /* Tags */
  --tag-color: {{ base0E }};
  --tag-background: {{ base10 }};

  /* Graph */
  --graph-line: {{ base10 }};
  --graph-node: {{ accent }};
  --graph-node-focused: {{ base0C }};
  --graph-node-tag: {{ base0E }};
  --graph-node-attachment: {{ base0A }};
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
  color: {{ base0E }};
}

/* Syntax highlighting */
.cm-s-obsidian span.cm-keyword { color: {{ base09 }}; }
.cm-s-obsidian span.cm-string { color: {{ base0A }}; }
.cm-s-obsidian span.cm-number { color: {{ base0B }}; }
.cm-s-obsidian span.cm-comment { color: {{ base10 }}; }
.cm-s-obsidian span.cm-operator { color: {{ base0C }}; }
.cm-s-obsidian span.cm-def { color: {{ base0C }}; }

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
