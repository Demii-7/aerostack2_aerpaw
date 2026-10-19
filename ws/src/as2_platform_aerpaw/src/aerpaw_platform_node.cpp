#include "as2_core/core_functions.hpp"
#include "as2_platform_aerpaw/aerpaw_platform.hpp"

int main(int argc, char * argv[])
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<as2_platform_aerpaw::AerpawPlatform>();
  as2::spinLoop(node);
  rclcpp::shutdown();
  return 0;
}
