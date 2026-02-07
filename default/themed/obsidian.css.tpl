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
  --background-modifier-border: {{ base03 }};

  /* Semantic heading colors */
  --text-title-h1: {{ base08 }};
  --text-title-h2: {{ base0B }};
  --text-title-h3: {{ base0A }};
  --text-title-h4: {{ base0D }};
  --text-title-h5: {{ base0E }};
  --text-title-h6: {{ base0E }};

  /* Links and accents */
  --text-link: {{ base0D }};
  --text-accent: {{ accent }};
  --text-accent-hover: {{ accent }};
  --interactive-accent: {{ accent }};
  --interactive-accent-hover: {{ accent }};

  /* Muted text */
  --text-muted: {{ base03 }};
  --text-faint: {{ base03 }};

  /* Code */
  --code-normal: {{ base0C }};

  /* Errors and success */
  --text-error: {{ base08 }};
  --text-error-hover: {{ base08 }};
  --text-success: {{ base0B }};

  /* Tags */
  --tag-color: {{ base0C }};
  --tag-background: {{ base03 }};

  /* Graph */
  --graph-line: {{ base03 }};
  --graph-node: {{ accent }};
  --graph-node-focused: {{ base0D }};
  --graph-node-tag: {{ base0C }};
  --graph-node-attachment: {{ base0B }};
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
  color: {{ base0C }};
}

/* Syntax highlighting */
.cm-s-obsidian span.cm-keyword { color: {{ base08 }}; }
.cm-s-obsidian span.cm-string { color: {{ base0B }}; }
.cm-s-obsidian span.cm-number { color: {{ base0A }}; }
.cm-s-obsidian span.cm-comment { color: {{ base03 }}; }
.cm-s-obsidian span.cm-operator { color: {{ base0D }}; }
.cm-s-obsidian span.cm-def { color: {{ base0D }}; }

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
