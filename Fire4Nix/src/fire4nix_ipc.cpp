#include "fire4nix_ipc.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <system_error>

namespace {
std::filesystem::path commandPath(const std::string& baseName)
{
    if (const char* runtime = std::getenv("FIRE4NIX_RUNTIME_DIR"); runtime && *runtime)
        return std::filesystem::path(runtime) / (baseName + ".cmd");
    return std::filesystem::path(".fire4nix") / "runtime" / (baseName + ".cmd");
}
}

bool CommandPipe::create(const std::string& baseName)
{
    if (baseName.empty() || baseName.find_first_of("/\\\r\n") != std::string::npos)
        return false;
    path_ = commandPath(baseName);
    std::error_code ec;
    std::filesystem::create_directories(path_.parent_path(), ec);
    if (ec) return false;
    std::ofstream out(path_, std::ios::app);
    return out.good();
}

bool CommandPipe::sendCommand(const std::string& cmd)
{
    if (path_.empty() || cmd.empty() || cmd.size() > 8192 ||
        cmd.find_first_of("\r\n") != std::string::npos || cmd.find('\0') != std::string::npos)
        return false;
    std::error_code ec;
    constexpr std::uintmax_t kMaxCommandJournalBytes = 256 * 1024;
    const auto currentSize = std::filesystem::file_size(path_, ec);
    if (!ec && currentSize > kMaxCommandJournalBytes)
        return false;
    std::ofstream out(path_, std::ios::app);
    if (!out.is_open()) return false;
    out << cmd << '\n';
    out.flush();
    return out.good();
}
