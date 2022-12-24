cmake_minimum_required(VERSION 3.10)
project(MillGame)

set(CMAKE_CXX_STANDARD 17)

find_package(Qt5 REQUIRED COMPONENTS Core Gui Multimedia Widgets)

include_directories(${CMAKE_SOURCE_DIR} ../../../include ../.. ../../test ../../perfect)

qt5_add_resources(RESOURCES_RCC ${RESOURCES})

file(GLOB SOURCES ../../*.cpp ../../test/*.cpp ../../perfect/*.cpp *.cpp)
file(GLOB HEADERS ../../../include/*.h ../../*.h ../../test/*.h ../../perfect/*.h *.h)
file(GLOB FORMS *.ui)
file(GLOB RESOURCES *.qrc)
file(GLOB RESOURCE_FILES *.rc)

if(MSVC)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /MP /W4")
else()
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -pedantic -Wno-long-long -Wno-variadic-macros -Wno-overlength-strings -fdiagnostics-color=auto -Wno-deprecated -Wno-unused-parameter")
endif()

add_executable(${PROJECT_NAME} ${SOURCES} ${HEADERS} ${FORMS} ${RESOURCES} ${RESOURCE_FILES})

if(MSVC)
  target_link_libraries(${PROJECT_NAME} shlwapi)
endif()
target_link_libraries(${PROJECT_NAME} Qt5::Core Qt5::Gui Qt5::Multimedia Qt5::Widgets)

set_target_properties(${PROJECT_NAME} PROPERTIES AUTOMOC ON AUTOUIC ON AUTORCC ON)

