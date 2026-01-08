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
  --background-modifier-border: {{ color8 }};

  /* Semantic heading colors */
  --text-title-h1: {{ color1 }};
  --text-title-h2: {{ color2 }};
  --text-title-h3: {{ color3 }};
  --text-title-h4: {{ color4 }};
  --text-title-h5: {{ color5 }};
  --text-title-h6: {{ color5 }};

  /* Links and accents */
  --text-link: {{ color4 }};
  --text-accent: {{ accent }};
  --text-accent-hover: {{ accent }};
  --interactive-accent: {{ accent }};
  --interactive-accent-hover: {{ accent }};

  /* Muted text */
  --text-muted: {{ color8 }};
  --text-faint: {{ color8 }};

  /* Code */
  --code-normal: {{ color6 }};

  /* Errors and success */
  --text-error: {{ color1 }};
  --text-error-hover: {{ color1 }};
  --text-success: {{ color2 }};

  /* Tags */
  --tag-color: {{ color6 }};
  --tag-background: {{ color8 }};

  /* Graph */
  --graph-line: {{ color8 }};
  --graph-node: {{ accent }};
  --graph-node-focused: {{ color4 }};
  --graph-node-tag: {{ color6 }};
  --graph-node-attachment: {{ color2 }};
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
  color: {{ color6 }};
}

/* Syntax highlighting */
.cm-s-obsidian span.cm-keyword { color: {{ color1 }}; }
.cm-s-obsidian span.cm-string { color: {{ color2 }}; }
.cm-s-obsidian span.cm-number { color: {{ color3 }}; }
.cm-s-obsidian span.cm-comment { color: {{ color8 }}; }
.cm-s-obsidian span.cm-operator { color: {{ color4 }}; }
.cm-s-obsidian span.cm-def { color: {{ color4 }}; }

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
