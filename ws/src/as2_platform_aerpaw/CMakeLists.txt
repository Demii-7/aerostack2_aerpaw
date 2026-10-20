cmake_minimum_required(VERSION 3.5)
project(as2_platform_aerpaw)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 17)
endif()

# Packages we need
find_package(ament_cmake REQUIRED)
set(PROJECT_DEPENDENCIES
  rclcpp
  as2_core
  as2_msgs
  nav_msgs
  sensor_msgs
)
foreach(DEPENDENCY ${PROJECT_DEPENDENCIES})
  find_package(${DEPENDENCY} REQUIRED)
endforeach()

# Where our header files are
include_directories(include)

# Build one program from our two .cpp files
add_executable(${PROJECT_NAME}_node
  src/aerpaw_platform_node.cpp
  src/aerpaw_platform.cpp
)
ament_target_dependencies(${PROJECT_NAME}_node ${PROJECT_DEPENDENCIES})

# Install the program, the launch files, and the config files
install(TARGETS ${PROJECT_NAME}_node
  DESTINATION lib/${PROJECT_NAME}
)
install(DIRECTORY launch config
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
