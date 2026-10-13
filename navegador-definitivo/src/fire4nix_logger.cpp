#include "fire4nix_logger.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <system_error>

namespace fire4nix {
namespace {
std::mutex g_logMutex;
std::ofstream g_logFile;

std::uintmax_t maxLogBytes()
{
    constexpr std::uintmax_t kDefaultMaxBytes = 1024 * 1024;
    if (const char* env = std::getenv("FIRE4NIX_LOG_MAX_BYTES"); env != nullptr && *env != '\0') {
        try {
            const auto parsed = std::stoull(env);
            return parsed > 0 ? static_cast<std::uintmax_t>(parsed) : kDefaultMaxBytes;
        } catch (...) {
            return kDefaultMaxBytes;
        }
    }
    return kDefaultMaxBytes;
}

std::filesystem::path rotatePath(const std::filesystem::path& path)
{
    return std::filesystem::path(path.string() + ".1");
}

std::string resolveLogPath(const std::string& path)
{
    if (!path.empty()) {
        return path;
    }
    if (const char* env = std::getenv("FIRE4NIX_LOG_FILE"); env != nullptr && *env != '\0') {
        return std::string(env);
    }
    if (const char* env = std::getenv("FIRE4NIX_LOG"); env != nullptr && *env != '\0') {
        return std::string(env);
    }
    if (const char* dir = std::getenv("FIRE4NIX_LOG_DIR"); dir != nullptr && *dir != '\0') {
        return (std::filesystem::path(dir) / "fire4nix.log").string();
    }
    if (const char* dir = std::getenv("FIRE4NIX_CONFIG_DIR"); dir != nullptr && *dir != '\0') {
        return (std::filesystem::path(dir) / "logs" / "fire4nix.log").string();
    }
    return "/tmp/fire4nix.log";
}

void maybeRotateLog(const std::filesystem::path& logPath)
{
    std::error_code ec;
    if (!std::filesystem::exists(logPath, ec)) {
        return;
    }

    const auto size = std::filesystem::file_size(logPath, ec);
    if (ec || size <= maxLogBytes()) {
        return;
    }

    const auto rotated = rotatePath(logPath);
    std::filesystem::remove(rotated, ec);
    std::filesystem::rename(logPath, rotated, ec);
}

void openLogFile(const std::string& path)
{
    std::error_code ec;
    const std::filesystem::path logPath(path);
    if (logPath.has_parent_path()) {
        std::filesystem::create_directories(logPath.parent_path(), ec);
    }
    maybeRotateLog(logPath);
    g_logFile.open(logPath, std::ios::app);
    if (!g_logFile) {
        g_logFile.clear();
        g_logFile.open("/tmp/fire4nix.log", std::ios::app);
    }
}
} // namespace

bool initLogging(const std::string& path)
{
    std::lock_guard<std::mutex> lock(g_logMutex);
    if (g_logFile.is_open()) {
        return true;
    }
    openLogFile(resolveLogPath(path));
    return static_cast<bool>(g_logFile);
}

static void writeLine(const char* level, const std::string& s)
{
    std::lock_guard<std::mutex> lock(g_logMutex);
    const std::string line = std::string("[") + level + "] " + s;
    if (g_logFile.is_open()) {
        g_logFile << line << '\n';
        g_logFile.flush();
    }
    std::cerr << line << '\n';
}

void logInfo(const std::string& s){ writeLine("I", s); }
void logWarn(const std::string& s){ writeLine("W", s); }
void logError(const std::string& s){ writeLine("E", s); }
}