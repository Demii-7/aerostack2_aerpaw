#include "as2_platform_aerpaw/aerpaw_platform.hpp"
#include "as2_core/utils/tf_utils.hpp"

namespace as2_platform_aerpaw
{

AerpawPlatform::AerpawPlatform(const rclcpp::NodeOptions & options)
: as2::AerialPlatform(options)
{
  configureSensors();
  RCLCPP_INFO(this->get_logger(), "AERPAW platform started (skeleton: nothing implemented yet)");
}

// Stage 4: relay MAVROS sensor topics to Aerostack2's sensor_measurements topics
void AerpawPlatform::configureSensors()
{
  // 1. Aerostack2's frame names for this drone
  odom_frame_id_ = as2::tf::generateTfName(this, "odom");
  base_link_frame_id_ = as2::tf::generateTfName(this, "base_link");
  
  // 2. Aerostack2 sensor publishers
  odom_sensor_ = std::make_unique<as2::sensors::Odometry>("odom", this);
  imu_sensor_ = std::make_unique<as2::sensors::Imu>("imu", this);
  gps_sensor_ = std::make_unique<as2::sensors::GPS>("gps", this);
  battery_sensor_ = std::make_unique<as2::sensors::Battery>("battery", this);

  // 3. Subscriptions to MAVROS, each passing the data on to Aerostack2
  mavros_odom_sub_ = this->create_subscription<nav_msgs::msg::Odometry>(
    "mavros/local_position/odom", rclcpp::SensorDataQoS(),
    [this](const nav_msgs::msg::Odometry::SharedPtr msg) {
      msg->header.frame_id = odom_frame_id_;
      msg->child_frame_id = base_link_frame_id_;
      odom_sensor_->updateData(*msg);
    });

  mavros_imu_sub_ = this->create_subscription<sensor_msgs::msg::Imu>(
    "mavros/imu/data", rclcpp::SensorDataQoS(),
    [this](const sensor_msgs::msg::Imu::SharedPtr msg) {
      msg->header.frame_id = base_link_frame_id_;
      imu_sensor_->updateData(*msg);
    });

  mavros_gps_sub_ = this->create_subscription<sensor_msgs::msg::NavSatFix>(
    "mavros/global_position/global", rclcpp::SensorDataQoS(),
    [this](const sensor_msgs::msg::NavSatFix::SharedPtr msg) {
      gps_sensor_->updateData(*msg);
    });

  mavros_battery_sub_ = this->create_subscription<sensor_msgs::msg::BatteryState>(
    "mavros/battery", rclcpp::SensorDataQoS(),
    [this](const sensor_msgs::msg::BatteryState::SharedPtr msg) {
      battery_sensor_->updateData(*msg);
    });

  RCLCPP_INFO(
    this->get_logger(), "configureSensors: relaying MAVROS odom, imu, gps, battery");
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

