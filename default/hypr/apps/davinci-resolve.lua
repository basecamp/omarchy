-- Float secondary DaVinci Resolve windows without locking focus.
o.window({ class = "^[Rr]esolve([.]bin)?$", title = "^(?!DaVinci Resolve( Studio)? - )" }, { float = true, center = true })
