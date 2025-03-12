# evmone: Fast Ethereum Virtual Machine implementation
# Copyright 2019 The evmone Authors.
# SPDX-License-Identifier: Apache-2.0

# For given target of a static library creates a custom target with -standalone suffix
# that merges the given target and all its static library dependencies
# into a single static library.
#
# It silently ignores non-static library target and unsupported platforms.
function(add_standalone_library TARGET)
    get_target_property(type ${TARGET} TYPE)
    if(NOT type STREQUAL STATIC_LIBRARY)
        return()
    endif()

    set(name ${TARGET}-standalone)
    # Create a valid C identifier from the name by replacing hyphens with underscores
    string(REPLACE "-" "_" valid_c_name ${name})

    if(CMAKE_AR)
        # Create a dummy source file for the target with a proper function declaration
        set(dummy_file "${CMAKE_CURRENT_BINARY_DIR}/${name}_dummy.c")
        file(WRITE ${dummy_file} "/* Dummy source file for CMake target */\n\
/* This function is never called, it exists just to create a valid object file */\n\
void ${valid_c_name}_dummy_function(void) {}\n")
        
        # Add -standalone static library.
        add_library(${name} STATIC ${dummy_file})
        
        # Create a shell script to handle the library creation process
        set(script_file "${CMAKE_CURRENT_BINARY_DIR}/${name}_build.sh")
        file(WRITE ${script_file} "#!/bin/sh\n\
# Script to build ${name} by combining object files from multiple libraries\n\
set -e\n\
echo \"Building ${name} from libraries...\"\n\
\n\
# Clean up any previous build artifacts\n\
rm -f \"$1\"\n\
\n\
# Create temp directory\n\
TEMP_DIR=\"${CMAKE_CURRENT_BINARY_DIR}/temp_obj_dir\"\n\
mkdir -p \"$TEMP_DIR\"\n\
\n\
# Create initial archive with dummy object\n\
\"${CMAKE_AR}\" crs \"$1\" \"$2\"\n\
\n\
# Function to extract and add library contents\n\
process_library() {\n\
  echo \"Adding $1 to ${name}\"\n\
  cd \"$TEMP_DIR\" && rm -f *.o\n\
  \"${CMAKE_AR}\" x \"$1\"\n\
  if [ \"$(ls -A \"$TEMP_DIR\")\" ]; then\n\
    # Only add files if directory is not empty\n\
    \"${CMAKE_AR}\" rs \"$2\" \"$TEMP_DIR\"/*.o\n\
  fi\n\
}\n\
\n\
# Process target library\n\
process_library \"$3\" \"$1\"\n\
\n\
# Process dependency libraries\n\
")

        # Add each dependency to the script
        get_target_property(link_libraries ${TARGET} LINK_LIBRARIES)
        set(index 4)  # Start parameter index at 4
        foreach(lib ${link_libraries})
            get_target_property(type ${lib} TYPE)
            if(NOT type STREQUAL INTERFACE_LIBRARY)
                file(APPEND ${script_file} "process_library \"$${index}\" \"$1\"\n")
                math(EXPR index "${index} + 1")
            endif()
        endforeach()
        
        # Add cleanup
        file(APPEND ${script_file} "\n# Clean up\nrm -rf \"$TEMP_DIR\"\necho \"${name} built successfully\"\n")
        
        # Make script executable
        file(CHMOD ${script_file} PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
        
        # Build command that calls our script with all libraries as arguments
        set(cmd_args)
        list(APPEND cmd_args 
            COMMAND ${script_file} 
            $<TARGET_FILE:${name}> 
            ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${name}.dir/${name}_dummy.c.o
            $<TARGET_FILE:${TARGET}>
        )
        
        # Add dependency library paths
        foreach(lib ${link_libraries})
            get_target_property(type ${lib} TYPE)
            if(NOT type STREQUAL INTERFACE_LIBRARY)
                list(APPEND cmd_args $<TARGET_FILE:${lib}>)
            endif()
        endforeach()
        
        add_custom_command(
            TARGET ${name}
            POST_BUILD
            ${cmd_args}
        )
        
        add_dependencies(${name} ${TARGET})

        get_property(enabled_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
        list(GET enabled_languages -1 lang)
        set_target_properties(${name} PROPERTIES LINKER_LANGUAGE ${lang})
    endif()
endfunction()
