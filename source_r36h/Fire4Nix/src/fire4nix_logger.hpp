#pragma once
#include <string>
namespace fire4nix {
bool initLogging(const std::string& path="");
void logInfo(const std::string&);
void logWarn(const std::string&);
void logError(const std::string&);
}
