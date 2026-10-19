#include "as2_platform_aerpaw/aerpaw_platform.hpp"

namespace as2_platform_aerpaw
{

AerpawPlatform::AerpawPlatform(const rclcpp::NodeOptions & options)
: as2::AerialPlatform(options)
{
  configureSensors();
  RCLCPP_INFO(this->get_logger(), "AERPAW platform started (skeleton: nothing implemented yet)");
}

// Stage 4: create sensor publishers from MAVROS topics
void AerpawPlatform::configureSensors()
{
  RCLCPP_INFO(this->get_logger(), "configureSensors: not implemented yet");
}

// Stage 5: call /mavros/cmd/arming
bool AerpawPlatform::ownSetArmingState(bool state)
{
  RCLCPP_WARN(
    this->get_logger(), "ownSetArmingState(%s): not implemented yet",
    state ? "true" : "false");
  return false;
}

// Stage 5: call /mavros/set_mode with GUIDED
bool AerpawPlatform::ownSetOffboardControl(bool offboard)
{
  RCLCPP_WARN(
    this->get_logger(), "ownSetOffboardControl(%s): not implemented yet",
    offboard ? "true" : "false");
  return false;
}

// Stage 7: remember which kind of command will be sent
bool AerpawPlatform::ownSetPlatformControlMode(const as2_msgs::msg::ControlMode & msg)
{
  RCLCPP_WARN(
    this->get_logger(), "ownSetPlatformControlMode(mode=%d): not implemented yet",
    msg.control_mode);
  return false;
}

// Stage 7: publish setpoints to MAVROS.
// Called up to 100 times per second once flying, so it doesn't print anything.
bool AerpawPlatform::ownSendCommand()
{
  return false;
}

// Stage 8: emergency motor stop
void AerpawPlatform::ownKillSwitch()
{
  RCLCPP_WARN(this->get_logger(), "ownKillSwitch: not implemented yet");
}

// Stage 8: emergency hover
void AerpawPlatform::ownStopPlatform()
{
  RCLCPP_WARN(this->get_logger(), "ownStopPlatform: not implemented yet");
}

// Stage 6: call /mavros/cmd/takeoff and wait for the height
bool AerpawPlatform::ownTakeoff()
{
  RCLCPP_WARN(this->get_logger(), "ownTakeoff: not implemented yet");
  return false;
}

// Stage 6: set LAND mode and wait until disarmed
bool AerpawPlatform::ownLand()
{
  RCLCPP_WARN(this->get_logger(), "ownLand: not implemented yet");
  return false;
}

}  // namespace as2_platform_aerpaw

