// The net feature state of a map's feature-state commands, which the map thread
// sets again after each style load (design D249 of the
// port-ffi-gesture-recognizer change).
#pragma once

#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

#include "overlay.h"

namespace map_texture {

class FeatureStateStore {
 public:
  struct Feature {
    std::string source_id;
    // Empty for a source without layers.
    std::string source_layer_id;
    std::string feature_id;

    bool operator<(const Feature& other) const {
      return std::tie(source_id, source_layer_id, feature_id) <
             std::tie(other.source_id, other.source_layer_id,
                      other.feature_id);
    }
  };

  // Merges the members of the JSON object `state` into the feature's state.
  // Returns false and changes nothing when `state` isn't a JSON object.
  bool Set(const Feature& feature, std::string_view state) {
    auto members = Members(state);
    if (!members) return false;
    auto& stored = features_[feature];
    for (auto& [key, value] : *members) stored[key] = std::move(value);
    if (stored.empty()) features_.erase(feature);
    return true;
  }

  // Removes the member `key` of the feature's state, or without `key`, all of
  // its state. Without `feature_id`, removes the state of every feature of the
  // source layer, or without `source_layer_id`, of the source.
  void Remove(const std::string& source_id,
              const std::optional<std::string>& source_layer_id,
              const std::optional<std::string>& feature_id,
              const std::optional<std::string>& key) {
    if (!feature_id) {
      for (auto it = features_.begin(); it != features_.end();) {
        bool match = it->first.source_id == source_id &&
                     (!source_layer_id ||
                      it->first.source_layer_id == *source_layer_id);
        it = match ? features_.erase(it) : std::next(it);
      }
      return;
    }
    Feature feature{source_id, source_layer_id.value_or(""), *feature_id};
    auto it = features_.find(feature);
    if (it == features_.end()) return;
    if (!key) {
      features_.erase(it);
      return;
    }
    for (auto member = it->second.begin(); member != it->second.end();) {
      member = KeyText(member->first) == *key ? it->second.erase(member)
                                              : std::next(member);
    }
    if (it->second.empty()) features_.erase(it);
  }

  // Each feature that has state, with its state as a JSON object.
  std::vector<std::pair<Feature, std::string>> Entries() const {
    std::vector<std::pair<Feature, std::string>> entries;
    for (const auto& [feature, members] : features_) {
      std::string object = "{";
      for (const auto& [key, value] : members) {
        if (object.size() > 1) object += ',';
        object += key;
        object += ':';
        object += value;
      }
      object += '}';
      entries.emplace_back(feature, std::move(object));
    }
    return entries;
  }

 private:
  // The members of a JSON object, as the text of each key (a JSON string,
  // quotes included) and of its value, or nothing when `text` isn't an
  // object.
  static std::optional<std::vector<std::pair<std::string, std::string>>>
  Members(std::string_view text) {
    using json::SkipSpace;
    std::vector<std::pair<std::string, std::string>> members;
    size_t pos = SkipSpace(text, 0);
    if (pos >= text.size() || text[pos] != '{') return std::nullopt;
    pos = SkipSpace(text, pos + 1);
    if (pos < text.size() && text[pos] == '}') {
      if (SkipSpace(text, pos + 1) != text.size()) return std::nullopt;
      return members;
    }
    while (true) {
      size_t key_end = json::SkipString(text, pos);
      if (key_end == std::string_view::npos) return std::nullopt;
      std::string key(text.substr(pos, key_end - pos));
      pos = SkipSpace(text, key_end);
      if (pos >= text.size() || text[pos] != ':') return std::nullopt;
      pos = SkipSpace(text, pos + 1);
      size_t value_end = json::SkipValue(text, pos);
      if (value_end == std::string_view::npos || value_end == pos) {
        return std::nullopt;
      }
      members.emplace_back(std::move(key),
                           std::string(text.substr(pos, value_end - pos)));
      pos = SkipSpace(text, value_end);
      if (pos >= text.size()) return std::nullopt;
      if (text[pos] == '}') break;
      if (text[pos] != ',') return std::nullopt;
      pos = SkipSpace(text, pos + 1);
    }
    if (SkipSpace(text, pos + 1) != text.size()) return std::nullopt;
    return members;
  }

  // The text of a key without its quotes; escapes stay as written.
  static std::string_view KeyText(std::string_view quoted) {
    return quoted.substr(1, quoted.size() - 2);
  }

  std::map<Feature, std::map<std::string, std::string>> features_;
};

}  // namespace map_texture
