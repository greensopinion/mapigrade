// Web Mercator projection of the map camera, the C++ counterpart of
// lib/src/layer/camera_projection.dart. The camera has no pitch.
#pragma once

#include <algorithm>
#include <cmath>
#include <numbers>

#include "command_queue.h"

namespace map_texture {

// Normalized Web Mercator coordinates: the world is [0, 1) in both
// directions, with y increasing southwards.
struct WorldPoint {
  double x = 0;
  double y = 0;
};

// A logical position in a viewport.
struct ScreenPoint {
  double x = 0;
  double y = 0;
};

struct ScreenBox {
  ScreenPoint min;
  ScreenPoint max;
};

// The camera and logical viewport size that a frame was rendered with.
struct RenderedView {
  Camera camera;
  double width = 0;
  double height = 0;
};

// The largest latitude Web Mercator shows, as in MapLibre.
inline constexpr double kMaxMercatorLatitude = 85.051128779806604;

inline WorldPoint Mercator(double latitude, double longitude) {
  double lat = std::clamp(latitude, -kMaxMercatorLatitude, kMaxMercatorLatitude);
  double phi = lat * std::numbers::pi / 180;
  return {(longitude + 180) / 360,
          (1 - std::log(std::tan(std::numbers::pi / 4 + phi / 2)) /
                   std::numbers::pi) /
              2};
}

// The width of the world in logical pixels at MapLibre zoom `zoom`.
inline double WorldSize(double zoom) { return 512 * std::exp2(zoom); }

// The logical position at which a map at `camera` in a viewport of logical
// size `width` x `height` draws `world`. Of the copies of `world` one world
// width apart, the one nearest the camera's center is used, so that a point
// across the antimeridian from the center stays near it.
inline ScreenPoint ScreenPosition(const Camera& camera, double width,
                                  double height, WorldPoint world) {
  WorldPoint center = Mercator(camera.latitude, camera.longitude);
  double dx = world.x - center.x;
  dx -= std::round(dx);
  double scale = WorldSize(camera.zoom);
  double px = dx * scale;
  double py = (world.y - center.y) * scale;
  double angle = -camera.bearing * std::numbers::pi / 180;
  double c = std::cos(angle);
  double s = std::sin(angle);
  return {c * px - s * py + width / 2, s * px + c * py + height / 2};
}

// The smallest box aligned with the screen axes that contains the positions
// of `corners` in the viewport of `camera`.
inline ScreenBox ScreenBounds(const Camera& camera, double width,
                              double height, const WorldPoint (&corners)[4]) {
  ScreenPoint first = ScreenPosition(camera, width, height, corners[0]);
  ScreenBox box{first, first};
  for (const WorldPoint& corner : corners) {
    ScreenPoint p = ScreenPosition(camera, width, height, corner);
    box.min = {std::min(box.min.x, p.x), std::min(box.min.y, p.y)};
    box.max = {std::max(box.max.x, p.x), std::max(box.max.y, p.y)};
  }
  return box;
}

}  // namespace map_texture
