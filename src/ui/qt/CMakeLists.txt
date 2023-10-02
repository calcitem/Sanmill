cmake_minimum_required(VERSION 3.10)
project(mill-pro)

set(CMAKE_CXX_STANDARD 17)

find_package(Qt5 REQUIRED COMPONENTS Core Gui Multimedia Widgets)

include_directories(${CMAKE_SOURCE_DIR} ../../../include ../.. ../../test)
include_directories(../../perfect)

qt5_add_resources(RESOURCES_RCC ${RESOURCES})

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

if(MSVC)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /MP /W4")
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

add_executable(${PROJECT_NAME} ${all_sources})

if(MSVC)
  target_link_libraries(${PROJECT_NAME} shlwapi)
endif()
target_link_libraries(${PROJECT_NAME} Qt5::Core Qt5::Gui Qt5::Multimedia Qt5::Widgets)

set_target_properties(${PROJECT_NAME} PROPERTIES AUTOMOC ON AUTOUIC ON AUTORCC ON)

