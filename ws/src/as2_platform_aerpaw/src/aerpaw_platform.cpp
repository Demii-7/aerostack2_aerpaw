#include "as2_platform_aerpaw/aerpaw_platform.hpp"
#include "as2_core/utils/tf_utils.hpp"

namespace as2_platform_aerpaw
{

AerpawPlatform::AerpawPlatform(const rclcpp::NodeOptions & options)
: as2::AerialPlatform(options)
{
  configureSensors();

  // Stage 5: MAVROS state and command services
  mavros_state_sub_ = this->create_subscription<mavros_msgs::msg::State>(
    "mavros/state", rclcpp::SensorDataQoS(),
    [this](const mavros_msgs::msg::State::SharedPtr msg) {
      mavros_state_ = *msg;
    });

  mavros_arming_client_ =
    std::make_shared<as2::SynchronousServiceClient<mavros_msgs::srv::CommandBool>>(
    "mavros/cmd/arming", this);
  mavros_set_mode_client_ =
    std::make_shared<as2::SynchronousServiceClient<mavros_msgs::srv::SetMode>>(
    "mavros/set_mode", this);

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

// Stage 5: arm (in STABILIZE, as AERPAW's safety pilot does) or disarm
bool AerpawPlatform::ownSetArmingState(bool state)
{
  if (!mavros_state_.connected) {
    RCLCPP_ERROR(this->get_logger(), "Cannot change arming state: MAVROS not connected");
    return false;
  }
  if (mavros_state_.armed == state) {
    RCLCPP_INFO(this->get_logger(), "Already %s", state ? "armed" : "disarmed");
    return true;
  }
  if (state && !setMavrosMode("STABILIZE")) {
    return false;
  }

  mavros_msgs::srv::CommandBool::Request request;
  mavros_msgs::srv::CommandBool::Response response;
  request.value = state;
  if (!mavros_arming_client_->sendRequest(request, response, 5)) {
    RCLCPP_ERROR(this->get_logger(), "Arming service not available");
    return false;
  }
  if (!response.success) {
    RCLCPP_ERROR(
      this->get_logger(), "%s rejected by ArduPilot (result %d)",
      state ? "Arming" : "Disarming", response.result);
    return false;
  }
  RCLCPP_INFO(this->get_logger(), "%s", state ? "Armed" : "Disarmed");
  return true;
}

// Stage 5: computer control on = GUIDED; off = hand control back
bool AerpawPlatform::ownSetOffboardControl(bool offboard)
{
  if (!mavros_state_.connected) {
    RCLCPP_ERROR(this->get_logger(), "Cannot change control mode: MAVROS not connected");
    return false;
  }
  if (offboard) {
    if (mavros_state_.mode == "GUIDED") {
      RCLCPP_INFO(this->get_logger(), "Already in GUIDED");
      return true;
    }
    return setMavrosMode("GUIDED");
  }
  if (!mavros_state_.armed) {
    RCLCPP_INFO(this->get_logger(), "Offboard off while disarmed: flight mode unchanged");
    return true;
  }
  // Armed: hand over to a position-holding mode (revisited in stage 8)
  return setMavrosMode("LOITER");
}

bool AerpawPlatform::setMavrosMode(const std::string & mode)
{
  mavros_msgs::srv::SetMode::Request request;
  mavros_msgs::srv::SetMode::Response response;
  
  request.custom_mode = mode;
  if (!mavros_set_mode_client_->sendRequest(request, response, 5)) {
    RCLCPP_ERROR(this->get_logger(), "Set mode %s: MAVROS service not available", mode.c_str());
    return false;
  }
  if (!response.mode_sent) {
    RCLCPP_ERROR(this->get_logger(), "Set mode %s: rejected", mode.c_str());
    return false;
  }
  RCLCPP_INFO(this->get_logger(), "Flight mode set to %s", mode.c_str());
  return true;
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

