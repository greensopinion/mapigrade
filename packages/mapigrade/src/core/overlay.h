// Overlays: runtime GeoJSON sources and style layers that Dart adds to the map
// (design D198 of the add-mapigrade-polyline-layer change), and the pure parts
// of installing them among the style's layers (D199): the anchor of a
// placement, the plan of the commands that make the style's layer list match
// the desired overlays, and the parsing of the layer JSON at the C ABI
// boundary.
//
// Nothing here calls MapLibre, so core_tests covers it.
#pragma once

#include <algorithm>
#include <compare>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace map_texture {

// IDs with this prefix belong to overlays, not to the style.
constexpr std::string_view kOverlayIdPrefix = "mapigrade-";

// The source options of map_texture_overlay_set_source(), a bit set;
// MAP_TEXTURE_SOURCE_LINE_METRICS in map_texture_api.h.
constexpr int32_t kSourceOptionLineMetrics = 1;
constexpr int32_t kSourceOptionsMask = kSourceOptionLineMetrics;

inline std::string OverlayIdPrefix(int64_t overlay_id) {
  return std::string(kOverlayIdPrefix) + "overlay-" + std::to_string(overlay_id);
}

inline std::string OverlaySourceId(int64_t overlay_id, int32_t index) {
  return OverlayIdPrefix(overlay_id) + "-source-" + std::to_string(index);
}

inline std::string OverlayLayerId(int64_t overlay_id, size_t index) {
  return OverlayIdPrefix(overlay_id) + "-" + std::to_string(index);
}

// The index of the source of the overlay `overlay_id` whose ID is `id`, or
// nothing when `id` isn't one of its source IDs.
inline std::optional<int32_t> OverlaySourceIndex(int64_t overlay_id,
                                                 std::string_view id) {
  std::string prefix = OverlayIdPrefix(overlay_id) + "-source-";
  if (!id.starts_with(prefix)) return std::nullopt;
  std::string_view digits = id.substr(prefix.size());
  if (digits.empty() || digits.size() > 9 ||
      (digits.size() > 1 && digits.front() == '0')) {
    return std::nullopt;
  }
  int32_t index = 0;
  for (char c : digits) {
    if (c < '0' || c > '9') return std::nullopt;
    index = index * 10 + (c - '0');
  }
  return index;
}

inline bool IsOverlayId(std::string_view id) {
  return id.starts_with(kOverlayIdPrefix);
}

// The values of `placement_kind` of map_texture_overlay_set_layers().
enum class PlacementKind : int32_t {
  kBelowLabels = 0,
  kBelowLayer = 1,
  kTop = 2,
};

struct Placement {
  PlacementKind kind = PlacementKind::kBelowLabels;
  // Set for kBelowLayer.
  std::string below_layer_id;

  bool operator==(const Placement&) const = default;
};

// Overlays at the same anchor are drawn in increasing order key: the child's
// index among the map layer's children, then the registration sequence
// (design D200).
struct OrderKey {
  int64_t child = 0;
  int64_t seq = 0;

  auto operator<=>(const OrderKey&) const = default;
};

// One entry of mln_map_list_style_layers().
struct StyleLayer {
  std::string id;
  std::string type;

  bool operator==(const StyleLayer&) const = default;
};

// Where an overlay's layers go: before the layer `before`, or on top when
// `before` is empty. `missing` is set when a kBelowLayer ID isn't in the
// style.
struct Anchor {
  std::string before;
  bool missing = false;

  bool operator==(const Anchor&) const = default;
};

// The anchor of `placement` in `layers`, the style's layers in style order
// (design D199). Overlay layers in the list are ignored.
inline Anchor ComputeAnchor(const std::vector<StyleLayer>& layers,
                            const Placement& placement) {
  switch (placement.kind) {
    case PlacementKind::kTop:
      return {};
    case PlacementKind::kBelowLayer:
      for (const StyleLayer& layer : layers) {
        if (!IsOverlayId(layer.id) && layer.id == placement.below_layer_id) {
          return {layer.id, false};
        }
      }
      return {"", true};
    case PlacementKind::kBelowLabels:
      break;
  }
  // The layer after the last layer that isn't a symbol layer, or the first
  // layer when every layer is one; a fill-extrusion layer before it is the
  // anchor instead, so that 3D buildings are drawn above the overlay.
  std::vector<const StyleLayer*> style;
  for (const StyleLayer& layer : layers) {
    if (!IsOverlayId(layer.id)) style.push_back(&layer);
  }
  if (style.empty()) return {};
  size_t next = 0;
  for (size_t i = 0; i < style.size(); ++i) {
    if (style[i]->type != "symbol") next = i + 1;
  }
  for (size_t i = 0; i < next; ++i) {
    if (style[i]->type == "fill-extrusion") return {style[i]->id, false};
  }
  if (next == style.size()) return {};
  return {style[next]->id, false};
}

// An overlay that the map should install: its layer IDs in order, and whether
// its layers changed since they were last added, so that they are added again
// even where they already are.
struct OverlayLayout {
  int64_t id = 0;
  OrderKey order;
  Placement placement;
  std::vector<std::string> layer_ids;
  bool replace = false;
};

// What the map thread does for one overlay to make the style match the
// desired overlays.
enum class OverlayAction {
  // Add the source and then every layer before `before`.
  kInstall,
  // Remove the layers in `remove_first`, then add every layer before `before`.
  kReplaceLayers,
  // Move every layer before `before`.
  kMove,
};

struct OverlayStep {
  int64_t id = 0;
  OverlayAction action = OverlayAction::kInstall;
  // Empty for the top.
  std::string before;
  // The overlay's layers that the style has, for kReplaceLayers.
  std::vector<std::string> remove_first;

  bool operator==(const OverlayStep&) const = default;
};

struct LayerPlan {
  // Overlay layers in the style that belong to no desired overlay, to remove
  // first.
  std::vector<std::string> remove_stale;
  // In execution order. Each step's `before` names a style layer or a layer
  // that an earlier step adds or moves.
  std::vector<OverlayStep> steps;
  // Distinct kBelowLayer IDs that the style lacks, in the order of `overlays`.
  std::vector<std::string> missing_layer_ids;
};

// Plans the layer commands that install the overlays of `overlays` in
// `current`, the style's layer list, at their anchors in order of their order
// keys, with a later key above an earlier one (design D199). Overlays whose
// layers are where they belong get no step. The plan is idempotent: planned
// against the list it produces, it is empty.
inline LayerPlan PlanLayers(const std::vector<StyleLayer>& current,
                            const std::vector<OverlayLayout>& overlays) {
  LayerPlan plan;
  std::vector<StyleLayer> style;
  std::set<std::string> present;
  for (const StyleLayer& layer : current) {
    present.insert(layer.id);
    if (!IsOverlayId(layer.id)) style.push_back(layer);
  }

  std::set<std::string> desired;
  for (const OverlayLayout& overlay : overlays) {
    desired.insert(overlay.layer_ids.begin(), overlay.layer_ids.end());
  }
  for (const StyleLayer& layer : current) {
    if (IsOverlayId(layer.id) && desired.count(layer.id) == 0) {
      plan.remove_stale.push_back(layer.id);
    }
  }

  // The overlays of each anchor, in increasing order key.
  std::map<std::string, std::vector<const OverlayLayout*>> groups;
  std::set<std::string> missing;
  for (const OverlayLayout& overlay : overlays) {
    Anchor anchor = ComputeAnchor(style, overlay.placement);
    if (anchor.missing && missing.insert(overlay.placement.below_layer_id).second) {
      plan.missing_layer_ids.push_back(overlay.placement.below_layer_id);
    }
    groups[anchor.before].push_back(&overlay);
  }
  for (auto& [anchor, group] : groups) {
    std::stable_sort(group.begin(), group.end(),
                     [](const OverlayLayout* a, const OverlayLayout* b) {
                       return a->order < b->order;
                     });
  }

  std::vector<std::string> current_ids;
  for (const StyleLayer& layer : current) current_ids.push_back(layer.id);

  for (auto& [anchor, group] : groups) {
    // The group is in place when its layers, in order, directly precede the
    // anchor (or end the list) and none of them is to be replaced.
    std::vector<std::string> expected;
    bool replace = false;
    for (const OverlayLayout* overlay : group) {
      expected.insert(expected.end(), overlay->layer_ids.begin(),
                      overlay->layer_ids.end());
      replace = replace || overlay->replace;
    }
    size_t end = anchor.empty()
                     ? current_ids.size()
                     : static_cast<size_t>(
                           std::find(current_ids.begin(), current_ids.end(),
                                     anchor) -
                           current_ids.begin());
    bool in_place = !replace && end >= expected.size() &&
                    std::equal(expected.begin(), expected.end(),
                               current_ids.begin() + (end - expected.size()));
    if (in_place) continue;

    // From the top of the group down, each overlay goes before the one above
    // it, whose first layer exists once the earlier step has run.
    std::string before = anchor;
    for (auto it = group.rbegin(); it != group.rend(); ++it) {
      const OverlayLayout& overlay = **it;
      if (overlay.layer_ids.empty()) continue;
      OverlayStep step;
      step.id = overlay.id;
      step.before = before;
      for (const std::string& id : overlay.layer_ids) {
        if (present.count(id) > 0) step.remove_first.push_back(id);
      }
      if (step.remove_first.empty()) {
        step.action = OverlayAction::kInstall;
      } else if (overlay.replace ||
                 step.remove_first.size() != overlay.layer_ids.size()) {
        step.action = OverlayAction::kReplaceLayers;
      } else {
        step.action = OverlayAction::kMove;
        step.remove_first.clear();
      }
      plan.steps.push_back(std::move(step));
      before = overlay.layer_ids.front();
    }
  }
  return plan;
}

// JSON scanning for the layer array of map_texture_overlay_set_layers(). The
// array and the `id` members are read; nothing else is validated, MapLibre
// parses each layer when it is added.
namespace json {

inline size_t SkipSpace(std::string_view text, size_t pos) {
  while (pos < text.size() &&
         (text[pos] == ' ' || text[pos] == '\t' || text[pos] == '\n' ||
          text[pos] == '\r')) {
    ++pos;
  }
  return pos;
}

// The position after the string that starts at `pos` (a quote), or npos.
inline size_t SkipString(std::string_view text, size_t pos) {
  if (pos >= text.size() || text[pos] != '"') return std::string_view::npos;
  for (++pos; pos < text.size(); ++pos) {
    if (text[pos] == '\\') {
      ++pos;
    } else if (text[pos] == '"') {
      return pos + 1;
    }
  }
  return std::string_view::npos;
}

// The position after the value that starts at `pos`, or npos. A value is an
// object, an array, a string, or a sequence of other non-structural
// characters.
inline size_t SkipValue(std::string_view text, size_t pos) {
  if (pos >= text.size()) return std::string_view::npos;
  if (text[pos] == '"') return SkipString(text, pos);
  if (text[pos] != '{' && text[pos] != '[') {
    while (pos < text.size() && text[pos] != ',' && text[pos] != '}' &&
           text[pos] != ']' && text[pos] != ' ' && text[pos] != '\n' &&
           text[pos] != '\r' && text[pos] != '\t') {
      ++pos;
    }
    return pos;
  }
  int depth = 0;
  for (; pos < text.size(); ++pos) {
    char c = text[pos];
    if (c == '"') {
      pos = SkipString(text, pos);
      if (pos == std::string_view::npos) return pos;
      --pos;
    } else if (c == '{' || c == '[') {
      ++depth;
    } else if (c == '}' || c == ']') {
      if (--depth == 0) return pos + 1;
    }
  }
  return std::string_view::npos;
}

}  // namespace json

// Splits a JSON array of objects into the text of each object. Returns
// nothing when `text` isn't an array of objects.
inline std::optional<std::vector<std::string>> SplitJsonObjectArray(
    std::string_view text) {
  using json::SkipSpace;
  std::vector<std::string> objects;
  size_t pos = SkipSpace(text, 0);
  if (pos >= text.size() || text[pos] != '[') return std::nullopt;
  pos = SkipSpace(text, pos + 1);
  if (pos < text.size() && text[pos] == ']') {
    if (SkipSpace(text, pos + 1) != text.size()) return std::nullopt;
    return objects;
  }
  while (true) {
    if (pos >= text.size() || text[pos] != '{') return std::nullopt;
    size_t end = json::SkipValue(text, pos);
    if (end == std::string_view::npos) return std::nullopt;
    objects.emplace_back(text.substr(pos, end - pos));
    pos = SkipSpace(text, end);
    if (pos >= text.size()) return std::nullopt;
    if (text[pos] == ']') break;
    if (text[pos] != ',') return std::nullopt;
    pos = SkipSpace(text, pos + 1);
  }
  if (SkipSpace(text, pos + 1) != text.size()) return std::nullopt;
  return objects;
}

// The string value of the member `key` of the JSON object `object`, or
// nothing when the object has no such member or its value isn't a string
// without escapes.
inline std::optional<std::string> JsonStringMember(std::string_view object,
                                                   std::string_view key) {
  using json::SkipSpace;
  size_t pos = SkipSpace(object, 0);
  if (pos >= object.size() || object[pos] != '{') return std::nullopt;
  pos = SkipSpace(object, pos + 1);
  while (pos < object.size() && object[pos] != '}') {
    size_t key_end = json::SkipString(object, pos);
    if (key_end == std::string_view::npos) return std::nullopt;
    std::string_view name = object.substr(pos + 1, key_end - pos - 2);
    pos = SkipSpace(object, key_end);
    if (pos >= object.size() || object[pos] != ':') return std::nullopt;
    pos = SkipSpace(object, pos + 1);
    size_t value_end = json::SkipValue(object, pos);
    if (value_end == std::string_view::npos) return std::nullopt;
    if (name == key) {
      std::string_view value = object.substr(pos, value_end - pos);
      if (value.size() < 2 || value.front() != '"' ||
          value.find('\\') != std::string_view::npos) {
        return std::nullopt;
      }
      return std::string(value.substr(1, value.size() - 2));
    }
    pos = SkipSpace(object, value_end);
    if (pos < object.size() && object[pos] == ',') pos = SkipSpace(object, pos + 1);
  }
  return std::nullopt;
}

}  // namespace map_texture
