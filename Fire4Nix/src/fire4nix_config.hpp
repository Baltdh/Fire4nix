#pragma once
#include <string>
namespace fire4nix {
struct Config {
 std::string configDir;
 std::string logDir;
 std::string cacheDir;
};
Config loadDefaultConfig();
}
