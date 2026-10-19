#ifndef AS2_PLATFORM_AERPAW__AERPAW_PLATFORM_HPP_
#define AS2_PLATFORM_AERPAW__AERPAW_PLATFORM_HPP_

#include <rclcpp/rclcpp.hpp>
#include <as2_core/aerial_platform.hpp>
#include <as2_msgs/msg/control_mode.hpp>

namespace as2_platform_aerpaw
{

class AerpawPlatform : public as2::AerialPlatform
{
public:
  explicit AerpawPlatform(const rclcpp::NodeOptions & options = rclcpp::NodeOptions());

  // ---- Required by as2::AerialPlatform ----
  void configureSensors() override;
  bool ownSetArmingState(bool state) override;
  bool ownSetOffboardControl(bool offboard) override;
  bool ownSetPlatformControlMode(const as2_msgs::msg::ControlMode & msg) override;
  bool ownSendCommand() override;
  void ownKillSwitch() override;
  void ownStopPlatform() override;

  // ---- Optional: ArduPilot's own takeoff and landing ----
  bool ownTakeoff() override;
  bool ownLand() override;
};

}  // namespace as2_platform_aerpaw

#endif  // AS2_PLATFORM_AERPAW__AERPAW_PLATFORM_HPP_
