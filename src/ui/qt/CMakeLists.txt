cmake_minimum_required(VERSION 3.10)
project(mill-pro)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)

# Set CMAKE_PREFIX_PATH if Qt_DIR is set
if(DEFINED ENV{Qt_DIR})
  set(CMAKE_PREFIX_PATH $ENV{Qt_DIR})
endif()

# Try to find Qt6 first, if not found then try Qt5
find_package(Qt6 COMPONENTS Core Gui Multimedia Widgets LinguistTools)
if(Qt6_FOUND)
  set(QT_VERSION 6)
  message(STATUS "Found Qt6: ${Qt6_VERSION}")
else()
  find_package(Qt5 REQUIRED COMPONENTS Core Gui Multimedia Widgets LinguistTools)
  set(QT_VERSION 5)
  message(STATUS "Found Qt5: ${Qt5_VERSION}")
endif()

# Include directories
include_directories(${CMAKE_SOURCE_DIR} ../../../include ../.. ../../test)
include_directories(../../perfect)

# Translation files
set(TS_FILES
    translations/mill-pro_en.ts
    translations/mill-pro_de.ts
    translations/mill-pro_hu.ts
    translations/mill-pro_zh_CN.ts
)

# Generate .qm files from .ts files
if(${QT_VERSION} EQUAL 6)
    qt6_add_translation(QM_FILES ${TS_FILES})
elseif(${QT_VERSION} EQUAL 5)
    qt5_add_translation(QM_FILES ${TS_FILES})
endif()

# Add resource files
if(${QT_VERSION} EQUAL 6)
  qt6_add_resources(RESOURCES_RCC ${RESOURCES})
elseif(${QT_VERSION} EQUAL 5)
  qt5_add_resources(RESOURCES_RCC ${RESOURCES})
endif()

# Source grouping
file(GLOB SOURCES_CORE ../../*.cpp ../../*.h ../../../include/*.h)
source_group("Source Files\\Core" FILES ${SOURCES_CORE})

file(GLOB SOURCES_QT *.cpp *.h)
source_group("Source Files\\Qt" FILES ${SOURCES_QT})

# Add translation directory sources
file(GLOB SOURCES_TRANSLATIONS translations/*.cpp translations/*.h)
source_group("Source Files\\Translations" FILES ${SOURCES_TRANSLATIONS})

file(GLOB SOURCES_TEST ../../test/*.cpp ../../test/*.h)
source_group("Source Files\\Test" FILES ${SOURCES_TEST})

file(GLOB SOURCES_PERFECT ../../perfect/*.cpp ../../perfect/*.h)
source_group("Source Files\\Perfect" FILES ${SOURCES_PERFECT})

file(GLOB FORMS *.ui)
file(GLOB RESOURCE_FILES *.rc *.qrc)

# Compiler flags
if(MSVC)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /MP /W4")
  if(CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
    # Add ARM64-specific flags or settings
  endif()
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -pedantic -Wno-long-long -Wno-variadic-macros -Wno-overlength-strings -fdiagnostics-color=auto -Wno-deprecated -Wno-unused-parameter")
else()
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -pedantic -Wno-long-long -Wno-variadic-macros -Wno-overlength-strings -fdiagnostics-color=auto -Wno-deprecated -Wno-unused-parameter -Wno-class-memaccess")
endif()

source_group("Forms" FILES ${FORMS})
source_group("Resource Files" FILES ${RESOURCE_FILES})
source_group("Translation Files" FILES ${TS_FILES} ${QM_FILES})

set(all_sources
  ${SOURCES_CORE}
  ${SOURCES_QT}
  ${SOURCES_TRANSLATIONS}
  ${SOURCES_TEST}
  ${FORMS}
  ${RESOURCE_FILES}
  ${QM_FILES}
)

list(APPEND all_sources ${SOURCES_PERFECT})

# Link libraries and set properties for automatic Qt handling
add_executable(${PROJECT_NAME} ${all_sources})

if(MSVC)
  target_link_libraries(${PROJECT_NAME} shlwapi)
endif()

if(${QT_VERSION} EQUAL 6)
  target_link_libraries(${PROJECT_NAME} Qt6::Core Qt6::Gui Qt6::Multimedia Qt6::Widgets)
elseif(${QT_VERSION} EQUAL 5)
  target_link_libraries(${PROJECT_NAME} Qt5::Core Qt5::Gui Qt5::Multimedia Qt5::Widgets)
endif()

set_target_properties(${PROJECT_NAME} PROPERTIES AUTOMOC ON AUTOUIC ON AUTORCC ON)

# Add a custom target to update translation files (optional)
# This target can be used to extract translatable strings from source files
add_custom_target(update_translations
    COMMAND ${CMAKE_COMMAND} -E echo "To update translations, run lupdate manually:"
    COMMAND ${CMAKE_COMMAND} -E echo "lupdate *.cpp *.h *.ui -ts translations/mill-pro_en.ts"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

# Note: qt_add_lupdate is not commonly used in standard builds
# Translation updates are typically done manually or through separate scripts
# The build_translations.* scripts handle the .ts to .qm compilation
