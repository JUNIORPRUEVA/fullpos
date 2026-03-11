# Install script for directory: C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "$<TARGET_FILE_DIR:fullpos>")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/flutter/cmake_install.cmake")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/cmake_install.cmake")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/printing/cmake_install.cmake")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/screen_retriever_windows/cmake_install.cmake")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/share_plus/cmake_install.cmake")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/url_launcher_windows/cmake_install.cmake")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/window_manager/cmake_install.cmake")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/fullpos.exe")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug" TYPE EXECUTABLE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/fullpos.exe")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/fullpos.exe")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile" TYPE EXECUTABLE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/fullpos.exe")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/fullpos.exe")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release" TYPE EXECUTABLE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/fullpos.exe")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/data/icudtl.dat")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/data" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/flutter/ephemeral/icudtl.dat")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/data/icudtl.dat")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/data" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/flutter/ephemeral/icudtl.dat")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/data/icudtl.dat")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/data" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/flutter/ephemeral/icudtl.dat")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/flutter_windows.dll")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/flutter/ephemeral/flutter_windows.dll")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/flutter_windows.dll")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/flutter/ephemeral/flutter_windows.dll")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/flutter_windows.dll")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/flutter/ephemeral/flutter_windows.dll")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/printing_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/pdfium.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/screen_retriever_windows_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/share_plus_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/url_launcher_windows_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/window_manager_plugin.dll")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug" TYPE FILE FILES
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/printing/Debug/printing_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/pdfium-src/bin/pdfium.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/screen_retriever_windows/Debug/screen_retriever_windows_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/share_plus/Debug/share_plus_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/url_launcher_windows/Debug/url_launcher_windows_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/window_manager/Debug/window_manager_plugin.dll"
      )
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/printing_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/pdfium.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/screen_retriever_windows_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/share_plus_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/url_launcher_windows_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/window_manager_plugin.dll")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile" TYPE FILE FILES
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/printing/Profile/printing_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/pdfium-src/bin/pdfium.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/screen_retriever_windows/Profile/screen_retriever_windows_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/share_plus/Profile/share_plus_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/url_launcher_windows/Profile/url_launcher_windows_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/window_manager/Profile/window_manager_plugin.dll"
      )
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/printing_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/pdfium.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/screen_retriever_windows_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/share_plus_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/url_launcher_windows_plugin.dll;C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/window_manager_plugin.dll")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release" TYPE FILE FILES
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/printing/Release/printing_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/pdfium-src/bin/pdfium.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/screen_retriever_windows/Release/screen_retriever_windows_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/share_plus/Release/share_plus_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/url_launcher_windows/Release/url_launcher_windows_plugin.dll"
      "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/plugins/window_manager/Release/window_manager_plugin.dll"
      )
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug" TYPE DIRECTORY FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build/native_assets/windows/")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile" TYPE DIRECTORY FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build/native_assets/windows/")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release" TYPE DIRECTORY FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build/native_assets/windows/")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    
  file(REMOVE_RECURSE "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/data/flutter_assets")
  
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    
  file(REMOVE_RECURSE "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/data/flutter_assets")
  
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    
  file(REMOVE_RECURSE "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/data/flutter_assets")
  
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/data/flutter_assets")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Debug/data" TYPE DIRECTORY FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build//flutter_assets")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/data/flutter_assets")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/data" TYPE DIRECTORY FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build//flutter_assets")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/data/flutter_assets")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/data" TYPE DIRECTORY FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build//flutter_assets")
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Runtime" OR NOT CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Pp][Rr][Oo][Ff][Ii][Ll][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/data/app.so")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Profile/data" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build/windows/app.so")
  elseif(CMAKE_INSTALL_CONFIG_NAME MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
    list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
     "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/data/app.so")
    if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
      message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
    endif()
    file(INSTALL DESTINATION "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/runner/Release/data" TYPE FILE FILES "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/build/windows/app.so")
  endif()
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
if(CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/install_local_manifest.txt"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
if(CMAKE_INSTALL_COMPONENT)
  if(CMAKE_INSTALL_COMPONENT MATCHES "^[a-zA-Z0-9_.+-]+$")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INSTALL_COMPONENT}.txt")
  else()
    string(MD5 CMAKE_INST_COMP_HASH "${CMAKE_INSTALL_COMPONENT}")
    set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INST_COMP_HASH}.txt")
    unset(CMAKE_INST_COMP_HASH)
  endif()
else()
  set(CMAKE_INSTALL_MANIFEST "install_manifest.txt")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  file(WRITE "C:/Users/PC/Desktop/CARPETA FULLPOS/FULLPOS_PROYECTO/FULLPOS/windows/${CMAKE_INSTALL_MANIFEST}"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
endif()
