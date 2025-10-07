echo "Configure VSCode and Cursor to use gnome-libsecret password store"

# Only configure if the editor is installed
[[ -d ~/.vscode ]] && bash $OMARCHY_PATH/install/config/editor-argv.sh vscode
[[ -d ~/.cursor ]] && bash $OMARCHY_PATH/install/config/editor-argv.sh cursor
