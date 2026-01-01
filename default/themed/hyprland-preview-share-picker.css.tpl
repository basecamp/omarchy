@define-color foreground {{ foreground }};
@define-color background {{ background }};
@define-color accent {{ accent }};
@define-color muted {{ color8 }};
@define-color card_bg {{ color0 }};
@define-color text_dark {{ background }};
@define-color accent_hover {{ color12 }};
@define-color selected_tab {{ accent }};
@define-color text {{ foreground }};

* {
  all: unset;
  font-family: JetBrains Mono NF;
  color: @foreground;
  font-weight: bold;
  font-size: 16px;
}

.window {
  background: alpha(@background, 0.95);
  border: solid 2px @accent;
  margin: 4px;
  padding: 18px;
}

tabs {
    padding: 0.5rem 1rem;
}

tabs > tab {
    margin-right: 1rem;
}

.tab-label {
    color: @text;
    transition: all 0.2s ease;
}

tabs > tab:checked > .tab-label, tabs > tab:active > .tab-label {
    text-decoration: underline currentColor;
    color: @selected_tab;
}

tabs > tab:focus > .tab-label {
    color: @foreground;
}

.page {
    padding: 1rem;
}

.image-label {
    font-size: 12px;
    padding: 0.25rem;
}

flowboxchild > .card, button > .card {
    transition: all 0.2s ease;
    border: solid 2px transparent;
    border-color: @background;
    border-radius: 5px;
    background-color: @card_bg;
    padding: 5px;
}

flowboxchild:hover > .card, button:hover > .card, flowboxchild:active > .card, flowboxchild:selected > .card, button:active > .card, button:selected > .card, button:focus > .card {
    border: solid 2px @accent;
}

.image {
    border-radius: 5px;
}

.region-button {
    padding: 0.5rem 1rem;
    border-radius: 5px;
    background-color: @accent;
    color: @text_dark;
    transition: all 0.2s ease;
}

.region-button > label {
    color: @text_dark;
}

.region-button:not(:disabled):hover, .region-button:not(:disabled):focus {
    background-color: @accent_hover;
    color: @text_dark;
}

.region-button:disabled {
    background-color: @muted;
    color: @background;
}
