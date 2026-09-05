file(REMOVE_RECURSE "${OUTPUT}")
file(REMOVE_RECURSE "${OUTPUT}-second")
execute_process(COMMAND "${GENERATOR}" "${OUTPUT}" RESULT_VARIABLE status)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "catalog generator failed with status ${status}")
endif()
execute_process(COMMAND "${GENERATOR}" "${OUTPUT}-second" RESULT_VARIABLE status)
if(NOT status EQUAL 0)
  message(FATAL_ERROR "second catalog generation failed with status ${status}")
endif()
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E compare_files
    "${GOLDEN_INDEX}" "${OUTPUT}/capability-catalog-v1.json"
  RESULT_VARIABLE golden_comparison)
if(NOT golden_comparison EQUAL 0)
  message(FATAL_ERROR
    "catalog semantics changed; regenerate and review capability_catalog_golden.json")
endif()
file(GLOB golden_files RELATIVE "${OUTPUT}-second"
  "${OUTPUT}-second/*" "${OUTPUT}-second/*/*")
file(GLOB output_files RELATIVE "${OUTPUT}" "${OUTPUT}/*" "${OUTPUT}/*/*")
if(NOT golden_files STREQUAL output_files)
  message(FATAL_ERROR "catalog generator emitted a different file set")
endif()
foreach(file IN LISTS golden_files)
  if(NOT IS_DIRECTORY "${OUTPUT}-second/${file}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E compare_files
        "${OUTPUT}-second/${file}" "${OUTPUT}/${file}"
      RESULT_VARIABLE comparison)
    if(NOT comparison EQUAL 0)
      message(FATAL_ERROR "catalog output changed between runs: ${file}")
    endif()
  endif()
endforeach()
