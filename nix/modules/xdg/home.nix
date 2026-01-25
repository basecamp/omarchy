{ lib, ... }:
with builtins;
let
  inherit (lib) splitString hasPrefix foldl';

  mimetypesFile = readFile (path {
    path = ../../../install/config/mimetypes.sh;
  });
  lines = filter (line: hasPrefix "xdg-mime default " line) (splitString "\n" mimetypesFile);

  parseLine =
    line:
    let
      # "xdg-mime default foo.desktop mime/type" -> ["xdg-mime" "default" "foo.desktop" "mime/type"]
      parts = splitString " " line;
      desktop = elemAt parts 2;
      mimetype = elemAt parts 3;
    in
    {
      ${mimetype} = desktop;
    };

  mimeApps = foldl' (acc: line: acc // parseLine line) { } lines;
in
{
  xdg = {
    enable = true;
    mime.enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = mimeApps;
    };
  };
}
