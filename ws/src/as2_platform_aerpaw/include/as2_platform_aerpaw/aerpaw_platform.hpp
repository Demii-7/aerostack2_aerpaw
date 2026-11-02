#ifndef AS2_PLATFORM_AERPAW__AERPAW_PLATFORM_HPP_
#define AS2_PLATFORM_AERPAW__AERPAW_PLATFORM_HPP_

#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>

#include <as2_core/aerial_platform.hpp>
#include <as2_core/sensor.hpp>
#include <as2_core/synchronous_service_client.hpp>
#include <as2_msgs/msg/control_mode.hpp>
#include <mavros_msgs/msg/state.hpp>
#include <mavros_msgs/srv/command_bool.hpp>
#include <mavros_msgs/srv/set_mode.hpp>
#include <nav_msgs/msg/odometry.hpp>
#include <sensor_msgs/msg/imu.hpp>
#include <sensor_msgs/msg/nav_sat_fix.hpp>
#include <sensor_msgs/msg/battery_state.hpp>
 

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

private:
  // Ask MAVROS to change ArduPilot's flight mode (e.g. "GUIDED")
  bool setMavrosMode(const std::string & mode);
  // Latest MAVROS state: connected, armed, current mode
  mavros_msgs::msg::State mavros_state_;
  rclcpp::Subscription<mavros_msgs::msg::State>::SharedPtr mavros_state_sub_;
  
  // Clients for MAVROS services
  as2::SynchronousServiceClient<mavros_msgs::srv::CommandBool>::SharedPtr mavros_arming_client_;
  as2::SynchronousServiceClient<mavros_msgs::srv::SetMode>::SharedPtr mavros_set_mode_client_;

  // Frame names used by Aerostack2, e.g. "drone0/odom" and "drone0/base_link"
  std::string odom_frame_id_;
  std::string base_link_frame_id_;

  // Aerostack2 sensor publishers (publish on sensor_measurements/...)
  std::unique_ptr<as2::sensors::Odometry> odom_sensor_;
  std::unique_ptr<as2::sensors::Imu> imu_sensor_;
  std::unique_ptr<as2::sensors::GPS> gps_sensor_;
  std::unique_ptr<as2::sensors::Battery> battery_sensor_;

  // Subscriptions to MAVROS topics (mavros/...)
  rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr mavros_odom_sub_;
  rclcpp::Subscription<sensor_msgs::msg::Imu>::SharedPtr mavros_imu_sub_;
  rclcpp::Subscription<sensor_msgs::msg::NavSatFix>::SharedPtr mavros_gps_sub_;
  rclcpp::Subscription<sensor_msgs::msg::BatteryState>::SharedPtr mavros_battery_sub_;
};

}  // namespace as2_platform_aerpaw

#endif  // AS2_PLATFORM_AERPAW__AERPAW_PLATFORM_HPP_
