#pragma once
#include <filesystem>
#include <string>

class CommandPipe {
public:
    bool create(const std::string& baseName);
    bool sendCommand(const std::string& cmd);

private:
    std::filesystem::path path_;
};
