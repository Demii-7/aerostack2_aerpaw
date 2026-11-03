// AERPAW mode for the MAVLink platform.
//
// On the real AERPAW testbed the E-VM talks to the autopilot through a MAVLink
// filter that only allows: GUIDED and LAND mode changes, takeoff to 20-110 m
// AGL, global waypoints (lat, lon, alt), yaw changes. The safety pilot arms the
// vehicle, landing must happen within 5 m of the takeoff point, and any other
// mode change or command aborts the experiment.
// (AERPAW User Manual, 5.1.3 MAVLink Filter.)
//
// aerpawlib, AERPAW's own vehicle library, follows the same rules: it waits for
// the pilot to arm, switches to GUIDED, uses MAV_CMD_NAV_TAKEOFF, sends one
// global waypoint per move and lands with LAND mode.
//
// With aerpaw.enabled the platform does the same:
//  - arm(true) does not send an arm command, it waits for the safety pilot;
//  - only HOVER and POSITION control modes are accepted;
//  - positions are sent as SET_POSITION_TARGET_GLOBAL_INT (mavros
//    setpoint_raw/global), once per new target plus a slow resend, instead of
//    a 50 Hz SET_POSITION_TARGET_LOCAL_NED stream;
//  - targets outside [min_alt, max_alt] are not sent;
//  - land uses LAND mode and is refused farther than land_radius from home;
//  - emergency hover holds position in GUIDED, the kill switch lands
//    (no BRAKE / LOITER mode changes, no forced disarm).

#include <cmath>
#include <string>

#include "as2_platform_mavlink/mavlink_platform.hpp"

namespace as2_platform_mavlink
{

namespace
{
constexpr double kEarthRadius = 6378137.0;  // m, WGS84 equatorial
constexpr double kDegToRad = M_PI / 180.0;
}  // namespace

void MavlinkPlatform::declareAerpawParameters()
{
  aerpaw_.enabled = this->declare_parameter<bool>("aerpaw.enabled", false);
  aerpaw_.arm_wait_timeout =
    this->declare_parameter<double>("aerpaw.arm_wait_timeout", aerpaw_.arm_wait_timeout);
  aerpaw_.min_alt = this->declare_parameter<double>("aerpaw.min_alt", aerpaw_.min_alt);
  aerpaw_.max_alt = this->declare_parameter<double>("aerpaw.max_alt", aerpaw_.max_alt);
  aerpaw_.land_radius = this->declare_parameter<double>("aerpaw.land_radius", aerpaw_.land_radius);
  aerpaw_.resend_period =
    this->declare_parameter<double>("aerpaw.resend_period", aerpaw_.resend_period);
  aerpaw_.min_target_change =
    this->declare_parameter<double>("aerpaw.min_target_change", aerpaw_.min_target_change);

  if (!aerpaw_.enabled) {
    return;
  }
  // The pilot arms in their own mode; GUIDED is entered afterwards (as aerpawlib does).
  autopilot_.set_mode_before_arming = false;
  RCLCPP_WARN(
    this->get_logger(),
    "AERPAW mode: pilot arms, GUIDED/LAND only, global waypoints, altitude %.0f-%.0f m, "
    "land within %.0f m of takeoff", aerpaw_.min_alt, aerpaw_.max_alt, aerpaw_.land_radius);
  if (takeoff_height_ < aerpaw_.min_alt) {
    RCLCPP_ERROR(
      this->get_logger(),
      "AERPAW mode: takeoff.height %.1f m is below the filter minimum %.1f m, takeoff will be "
      "refused", takeoff_height_, aerpaw_.min_alt);
  }
}

void MavlinkPlatform::setupAerpawCommunications(
  const rclcpp::SubscriptionOptions & feedback_options)
{
  if (!aerpaw_.enabled) {
    return;
  }
  // mavros_launch.py is meant to remap global_position/global to
  // sensor_measurements/gps, but the remap does not match the MAVROS plugin
  // sub-node topics with namespace <ns> (T6 run 1), so listen to both names.
  auto gps_cb = [this](const sensor_msgs::msg::NavSatFix::SharedPtr msg) {
      aerpaw_fix_ = *msg;
      aerpaw_fix_received_ = true;
    };
  aerpaw_gps_sub_ = this->create_subscription<sensor_msgs::msg::NavSatFix>(
    "sensor_measurements/gps", rclcpp::SensorDataQoS(), gps_cb, feedback_options);
  aerpaw_gps_raw_sub_ = this->create_subscription<sensor_msgs::msg::NavSatFix>(
    "mavros/global_position/global", rclcpp::SensorDataQoS(), gps_cb, feedback_options);
  aerpaw_rel_alt_sub_ = this->create_subscription<std_msgs::msg::Float64>(
    "mavros/global_position/rel_alt", rclcpp::SensorDataQoS(),
    [this](const std_msgs::msg::Float64::SharedPtr msg) {aerpaw_rel_alt_ = msg->data;},
    feedback_options);
  aerpaw_global_pub_ = this->create_publisher<mavros_msgs::msg::GlobalPositionTarget>(
    "mavros/setpoint_raw/global", rclcpp::SensorDataQoS());
}

bool MavlinkPlatform::aerpawSetArmingState(bool state)
{
  if (!state) {
    if (!this->getArmingState()) {
      return true;
    }
    RCLCPP_ERROR(
      this->get_logger(),
      "AERPAW mode: disarm commands are not allowed. Land (LAND mode disarms on touchdown) or "
      "let the safety pilot disarm.");
    return false;
  }

  if (this->getArmingState()) {
    return true;
  }
  RCLCPP_WARN(
    this->get_logger(), "AERPAW mode: waiting up to %.0f s for the safety pilot to arm",
    aerpaw_.arm_wait_timeout);
  const bool armed = waitFor(
    [this]() {return this->getArmingState();}, aerpaw_.arm_wait_timeout,
    "the safety pilot to arm");
  if (armed) {
    RCLCPP_INFO(this->get_logger(), "AERPAW mode: vehicle armed by the safety pilot");
  }
  return armed;
}

double MavlinkPlatform::aerpawDistanceToHome() const
{
  if (!aerpaw_home_set_ || !aerpaw_fix_received_) {
    return 0.0;
  }
  const double dlat = (aerpaw_fix_.latitude - aerpaw_home_lat_) * kDegToRad;
  const double dlon = (aerpaw_fix_.longitude - aerpaw_home_lon_) * kDegToRad;
  const double north = dlat * kEarthRadius;
  const double east = dlon * kEarthRadius * std::cos(aerpaw_home_lat_ * kDegToRad);
  return std::hypot(north, east);
}

bool MavlinkPlatform::aerpawLand()
{
  const double distance = aerpawDistanceToHome();
  if (distance > aerpaw_.land_radius) {
    RCLCPP_ERROR(
      this->get_logger(),
      "AERPAW mode: refusing to land %.1f m from the takeoff point (limit %.1f m). Fly back "
      "over the takeoff point first.", distance, aerpaw_.land_radius);
    return false;
  }
  RCLCPP_INFO(this->get_logger(), "AERPAW mode: landing with LAND mode (%.1f m from home)", distance);
  if (!setFlightMode("LAND", true)) {
    return false;
  }
  this->platform_info_msg_.set__offboard(false);
  aerpaw_target_sent_ = false;
  if (!blocking_takeoff_and_land_) {
    return true;
  }
  return waitFor(
    [this]() {return !this->getArmingState();}, land_timeout_, "the landing (disarm)");
}

bool MavlinkPlatform::aerpawSendWaypoint(const geometry_msgs::msg::Point & target)
{
  auto & clk = *this->get_clock();
  if (!aerpaw_fix_received_ || !odometry_received_) {
    RCLCPP_WARN_THROTTLE(this->get_logger(), clk, 2000, "AERPAW mode: no GPS fix / odometry yet");
    return false;
  }

  const rclcpp::Time now = this->now();
  const bool changed = !aerpaw_target_sent_ ||
    std::hypot(
    target.x - aerpaw_last_target_.x, target.y - aerpaw_last_target_.y,
    target.z - aerpaw_last_target_.z) > aerpaw_.min_target_change;
  const bool resend_due = aerpaw_target_sent_ &&
    (now - aerpaw_last_send_time_).seconds() > aerpaw_.resend_period;
  if (!changed && !resend_due) {
    return true;
  }
  if (changed) {
    aerpaw_last_target_ = target;
  }

  // Offset from the current position, in the local ENU frame, applied to the
  // current GPS fix and relative altitude (flat earth, fine for < 1 km moves).
  const auto & p = last_odom_pose_.pose.position;
  const double east = aerpaw_last_target_.x - p.x;
  const double north = aerpaw_last_target_.y - p.y;
  const double up = aerpaw_last_target_.z - p.z;
  const double lat0 = aerpaw_fix_.latitude * kDegToRad;

  mavros_msgs::msg::GlobalPositionTarget msg;
  msg.header.stamp = now;
  msg.coordinate_frame = mavros_msgs::msg::GlobalPositionTarget::FRAME_GLOBAL_REL_ALT;
  msg.type_mask = mavros_msgs::msg::GlobalPositionTarget::IGNORE_VX |
    mavros_msgs::msg::GlobalPositionTarget::IGNORE_VY |
    mavros_msgs::msg::GlobalPositionTarget::IGNORE_VZ |
    mavros_msgs::msg::GlobalPositionTarget::IGNORE_AFX |
    mavros_msgs::msg::GlobalPositionTarget::IGNORE_AFY |
    mavros_msgs::msg::GlobalPositionTarget::IGNORE_AFZ |
    mavros_msgs::msg::GlobalPositionTarget::IGNORE_YAW |
    mavros_msgs::msg::GlobalPositionTarget::IGNORE_YAW_RATE;
  msg.latitude = aerpaw_fix_.latitude + (north / kEarthRadius) / kDegToRad;
  msg.longitude = aerpaw_fix_.longitude + (east / (kEarthRadius * std::cos(lat0))) / kDegToRad;
  msg.altitude = static_cast<float>(aerpaw_rel_alt_ + up);

  if (msg.altitude < aerpaw_.min_alt || msg.altitude > aerpaw_.max_alt) {
    RCLCPP_ERROR_THROTTLE(
      this->get_logger(), clk, 2000,
      "AERPAW mode: target altitude %.1f m is outside %.0f-%.0f m, not sent", msg.altitude,
      aerpaw_.min_alt, aerpaw_.max_alt);
    return false;
  }

  aerpaw_global_pub_->publish(msg);
  aerpaw_target_sent_ = true;
  aerpaw_last_send_time_ = now;
  if (changed) {
    RCLCPP_INFO(
      this->get_logger(), "AERPAW mode: waypoint lat %.7f lon %.7f rel_alt %.1f m", msg.latitude,
      msg.longitude, msg.altitude);
  }
  return true;
}

bool MavlinkPlatform::aerpawSendCommand(const as2_msgs::msg::ControlMode & mode)
{
  switch (mode.control_mode) {
    case as2_msgs::msg::ControlMode::HOVER:
      return hover_setpoint_latched_ && aerpawSendWaypoint(hover_pose_.pose.position);
    case as2_msgs::msg::ControlMode::POSITION: {
        if (!isReferenceFresh(this->command_pose_msg_.header.stamp, "position")) {
          // A stale reference must not move the vehicle; ArduPilot keeps
          // holding the last global waypoint on its own.
          return false;
        }
        geometry_msgs::msg::PoseStamped pose = this->command_pose_msg_;
        if (pose.header.frame_id != odom_frame_id_ &&
          !tf_handler_->tryConvert(pose, odom_frame_id_))
        {
          auto & clk = *this->get_clock();
          RCLCPP_ERROR_THROTTLE(
            this->get_logger(), clk, 1000, "Cannot convert the position reference from '%s'",
            pose.header.frame_id.c_str());
          return false;
        }
        return aerpawSendWaypoint(pose.pose.position);
      }
    default:
      return false;
  }
}

}  // namespace as2_platform_mavlink
