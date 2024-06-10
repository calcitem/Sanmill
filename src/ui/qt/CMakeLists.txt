cmake_minimum_required(VERSION 3.10)
project(mill-pro)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)

# Set CMAKE_PREFIX_PATH if Qt_DIR is set
if(DEFINED ENV{Qt_DIR})
  set(CMAKE_PREFIX_PATH $ENV{Qt_DIR})
endif()

# Try to find Qt6 first, if not found then try Qt5
find_package(Qt6 COMPONENTS Core Gui Multimedia Widgets)
if(NOT Qt6_FOUND)
  find_package(Qt5 REQUIRED COMPONENTS Core Gui Multimedia Widgets)
  set(QT_VERSION 5)
else()
  set(QT_VERSION 6)
endif()

# Include directories
include_directories(${CMAKE_SOURCE_DIR} ../../../include ../.. ../../test)
include_directories(../../perfect)

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

set(all_sources
  ${SOURCES_CORE}
  ${SOURCES_QT}
  ${SOURCES_TEST}
  ${FORMS}
  ${RESOURCE_FILES}
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
