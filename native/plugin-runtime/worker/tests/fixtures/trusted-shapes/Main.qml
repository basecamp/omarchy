import QtQuick 6.0
import QtQuick.Shapes 6.0 as Shapes // certified native module alias

Shapes.Shape {
    width: 32
    height: 32

    Shapes.ShapePath {
        fillColor: "#ff3366"
        strokeWidth: -1
        PathSvg { path: "M 2 2 L 30 2 L 16 30 Z" }
    }
}
