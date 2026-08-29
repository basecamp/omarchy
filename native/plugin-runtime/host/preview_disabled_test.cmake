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

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    --unset=OMARCHY_PLUGIN_SCHEMA_V2_ENABLED
    --unset=OMARCHY_PLUGIN_LIVE_LAB_ENABLED
    QT_QPA_PLATFORM=offscreen
    QT_QPA_PLATFORMTHEME=none
    "${HOST}" --preview-plugin-live-lab ignored ignored ignored ignored ignored
  RESULT_VARIABLE live_result
  OUTPUT_VARIABLE live_output
  ERROR_VARIABLE live_error)
if(NOT live_result EQUAL 77)
  message(FATAL_ERROR
    "disabled live lab returned ${live_result}: ${live_output}${live_error}")
endif()
