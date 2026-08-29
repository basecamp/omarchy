execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    --unset=OMARCHY_PLUGIN_SCHEMA_V2_ENABLED
    QT_QPA_PLATFORM=offscreen
    QT_QPA_PLATFORMTHEME=none
    "${HOST}" --preview-plugin ignored ignored ignored ignored ignored
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error)
if(NOT result EQUAL 77)
  message(FATAL_ERROR "disabled preview returned ${result}: ${output}${error}")
endif()
