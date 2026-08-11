if o.cmd_present("voxtype") then
  o.bind(omarchy_bindings.toggle_dictation, "Toggle dictation", "voxtype record toggle")
  o.bind(omarchy_bindings.start_dictation_push_to_talk, "Start dictation (push-to-talk)", "voxtype record start")
  o.bind(omarchy_bindings.stop_dictation_push_to_talk, "Stop dictation (push-to-talk)", "voxtype record stop",  { release = true })
end
