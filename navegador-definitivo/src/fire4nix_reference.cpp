#include "fire4nix_reference.hpp"

#include <cstdlib>
#include <filesystem>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

namespace fire4nix {
namespace {

std::filesystem::path normalizeCandidate(const std::filesystem::path& candidate)
{
    std::error_code ec;
    const auto canonical = std::filesystem::weakly_canonical(candidate, ec);
    if (!ec && !canonical.empty()) {
        return canonical;
    }
    return candidate.lexically_normal();
}

std::vector<std::filesystem::path> candidateRoots()
{
    std::vector<std::filesystem::path> roots;

    if (const char* env = std::getenv("FIRE4NIX_REFERENCE_ROOT"); env != nullptr && *env != '\0') {
        roots.emplace_back(env);
    }
    if (const char* cfg = std::getenv("FIRE4NIX_CONFIG_DIR"); cfg != nullptr && *cfg != '\0') {
        roots.emplace_back(std::filesystem::path(cfg) / "reference");
    }

    roots.emplace_back("rocknix_reference");
    roots.emplace_back(std::filesystem::current_path() / "rocknix_reference");
    return roots;
}

std::filesystem::path chooseReferenceRoot()
{
    for (const auto& root : candidateRoots()) {
        std::error_code ec;
        if (std::filesystem::exists(root, ec) && std::filesystem::is_directory(root, ec)) {
            return normalizeCandidate(root);
        }
    }
    return {};
}

std::size_t countRegularFiles(const std::filesystem::path& root)
{
    std::error_code ec;
    if (!std::filesystem::exists(root, ec) || !std::filesystem::is_directory(root, ec)) {
        return 0;
    }

    std::size_t count = 0;
    for (std::filesystem::recursive_directory_iterator it(root, ec), end; !ec && it != end; it.increment(ec)) {
        if (ec) {
            break;
        }
        std::error_code entryEc;
        if (it->is_regular_file(entryEc) && !entryEc) {
            ++count;
        }
    }
    return count;
}

bool existsFile(const std::filesystem::path& p)
{
    std::error_code ec;
    return std::filesystem::exists(p, ec) && std::filesystem::is_regular_file(p, ec);
}

std::string groupSummary(const std::filesystem::path& root)
{
    std::vector<std::string> groups;

    const auto profileHooks = countRegularFiles(root / "etc/profile.d");
    const auto systemdPolicies = countRegularFiles(root / "etc/systemd");
    const auto dbusPolicies = countRegularFiles(root / "etc/dbus-1/system.d");
    const auto tmpfilesCount = countRegularFiles(root / "etc/tmpfiles.d");
    const auto pkgconfigCount = countRegularFiles(root / "devkit/armhf/pkgconfig");
    const auto lib32SnapshotCount = countRegularFiles(root / "runtime-libs/armhf/lib32-snapshot");
    const auto python313Count = countRegularFiles(root / "devkit/python313");

    if (existsFile(root / "etc/dbus-1/session.conf")) groups.emplace_back("dbus-session");
    if (existsFile(root / "etc/dbus-1/system.conf")) groups.emplace_back("dbus-system");
    if (dbusPolicies > 0) groups.emplace_back("dbus-policies");
    if (existsFile(root / "etc/dbus-1/system.d/nm-priv-helper.conf") ||
        existsFile(root / "etc/dbus-1/system.d/nm-dispatcher.conf") ||
        existsFile(root / "etc/dbus-1/system.d/org.freedesktop.NetworkManager.conf")) {
        groups.emplace_back("networkmanager");
    }
    if (existsFile(root / "etc/dbus-1/system.d/avahi-dbus.conf")) groups.emplace_back("avahi");
    if (existsFile(root / "etc/fonts/fonts.conf")) groups.emplace_back("fonts");
    if (existsFile(root / "etc/ssl/certs/cacert.pem.system")) groups.emplace_back("ssl");
    if (existsFile(root / "etc/systemd/system.conf")) groups.emplace_back("systemd");
    if (existsFile(root / "etc/systemd/logind.conf")) groups.emplace_back("logind");
    if (existsFile(root / "etc/systemd/journald.conf")) groups.emplace_back("journald");
    if (existsFile(root / "etc/systemd/iocost.conf")) groups.emplace_back("iocost");
    if (existsFile(root / "etc/systemd/user.conf")) groups.emplace_back("systemd-user");
    if (existsFile(root / "etc/systemd/resolved.conf")) groups.emplace_back("resolved");
    if (existsFile(root / "etc/systemd/oomd.conf")) groups.emplace_back("oomd");
    if (existsFile(root / "etc/systemd/sleep.conf")) groups.emplace_back("sleep");
    if (existsFile(root / "etc/systemd/timesyncd.conf")) groups.emplace_back("timesyncd");
    if (existsFile(root / "etc/udev/udev.conf")) groups.emplace_back("udev");
    if (existsFile(root / "etc/gtk-3.0/im-multipress.conf")) groups.emplace_back("gtk-im");
    if (existsFile(root / "etc/xdg/autostart/at-spi-dbus-bus.desktop")) groups.emplace_back("at-spi");
    if (existsFile(root / "etc/foot.ini")) groups.emplace_back("foot");
    if (tmpfilesCount > 0) groups.emplace_back("tmpfiles");
    if (tmpfilesCount > 0) groups.emplace_back("tmpfiles.d:" + std::to_string(tmpfilesCount));
    if (pkgconfigCount > 0) groups.emplace_back("pkgconfig-armhf:" + std::to_string(pkgconfigCount));
    if (lib32SnapshotCount > 0) groups.emplace_back("lib32-snapshot:" + std::to_string(lib32SnapshotCount));
    if (python313Count > 0) groups.emplace_back("python313:" + std::to_string(python313Count));
    if (existsFile(root / "swayimgrc")) groups.emplace_back("swayimg");
    if (existsFile(root / "MangoHud.aarch64.json")) groups.emplace_back("mangohud");
    if (existsFile(root / "etc/profile.d/001-functions")) groups.emplace_back("profile-001");
    if (existsFile(root / "etc/profile.d/002-autostart")) groups.emplace_back("profile-002");
    if (existsFile(root / "etc/profile.d/010-wlr-randr")) groups.emplace_back("profile-010");
    if (existsFile(root / "etc/profile.d/045-xorg-server.conf")) groups.emplace_back("profile-045");
    if (existsFile(root / "etc/profile.d/050-sway.conf")) groups.emplace_back("wayland");
    if (existsFile(root / "etc/profile.d/090-systemd.conf")) groups.emplace_back("systemd-profile");
    if (existsFile(root / "etc/profile.d/095-zerotier.conf")) groups.emplace_back("zerotier");
    if (existsFile(root / "etc/profile.d/098-box64.conf")) groups.emplace_back("box64");
    if (existsFile(root / "etc/profile.d/101-gpu-functions")) groups.emplace_back("gpu");
    if (profileHooks > 0) groups.emplace_back("profile.d:" + std::to_string(profileHooks));
    if (systemdPolicies > 0) groups.emplace_back("systemd:" + std::to_string(systemdPolicies));

    std::ostringstream out;
    for (std::size_t i = 0; i < groups.size(); ++i) {
        if (i != 0) {
            out << " • ";
        }
        out << groups[i];
    }
    return out.str();
}

} // namespace

ReferencePackReport detectReferencePack()
{
    ReferencePackReport report;
    const auto root = chooseReferenceRoot();
    if (root.empty()) {
        report.summary = "reference pack unavailable";
        return report;
    }

    report.available = true;
    report.root = root.string();
    report.fileCount = countRegularFiles(root);

    static const std::vector<std::string> anchors = {
        "etc/dbus-1/session.conf",
        "etc/dbus-1/system.conf",
        "etc/dbus-1/system.d/nm-priv-helper.conf",
        "etc/dbus-1/system.d/nm-dispatcher.conf",
        "etc/dbus-1/system.d/avahi-dbus.conf",
        "etc/dbus-1/system.d/org.freedesktop.NetworkManager.conf",
        "etc/fonts/fonts.conf",
        "etc/ssl/certs/cacert.pem.system",
        "etc/systemd/system.conf",
        "etc/systemd/logind.conf",
        "etc/systemd/journald.conf",
        "etc/systemd/iocost.conf",
        "etc/systemd/oomd.conf",
        "etc/systemd/resolved.conf",
        "etc/systemd/sleep.conf",
        "etc/systemd/timesyncd.conf",
        "etc/systemd/user.conf",
        "etc/udev/udev.conf",
        "etc/gtk-3.0/im-multipress.conf",
        "etc/xdg/autostart/at-spi-dbus-bus.desktop",
        "etc/profile.d/00-at-spi",
        "etc/profile.d/001-functions",
        "etc/profile.d/002-autostart",
        "etc/profile.d/010-wlr-randr",
        "etc/profile.d/045-xorg-server.conf",
        "etc/profile.d/050-sway.conf",
        "etc/profile.d/090-systemd.conf",
        "etc/profile.d/095-zerotier.conf",
        "etc/profile.d/098-box64.conf",
        "etc/profile.d/101-gpu-functions",
        "etc/foot.ini",
        "etc/tmpfiles.d/systemd-tmp.conf",
        "etc/tmpfiles.d/z_01_rocknix.conf",
        "devkit/armhf/pkgconfig/gio-2.0.pc",
        "devkit/armhf/pkgconfig/girepository-2.0.pc",
        "devkit/armhf/pkgconfig/cairo-xlib-xcb.pc",
        "devkit/armhf/pkgconfig/xwayland.pc",
        "devkit/armhf/pkgconfig/glib-2.0.pc",
        "devkit/armhf/pkgconfig/gmodule-2.0.pc",
        "devkit/python313/Setup.stdlib",
        "devkit/python313/config.c",
        "runtime-libs/armhf/lib32-snapshot/README.md",
        "runtime-libs/armhf/lib32-snapshot/INVENTORY.md",
        "foot.ini",
        "swayimgrc",
        "MangoHud.aarch64.json",
    };

    report.anchorCount = anchors.size();
    for (const auto& rel : anchors) {
        std::error_code ec;
        if (std::filesystem::exists(root / rel, ec) && std::filesystem::is_regular_file(root / rel, ec)) {
            ++report.presentCount;
        }
    }

    std::ostringstream summary;
    summary << "root=" << report.root << " • anchors " << report.presentCount << "/" << report.anchorCount;
    const auto groups = groupSummary(root);
    if (!groups.empty()) {
        summary << " • " << groups;
    }
    if (report.anchorCount > 0) {
        const auto coverage = static_cast<unsigned int>((report.presentCount * 100) / report.anchorCount);
        summary << " • coverage " << coverage << "%";
    }
    summary << " • files " << report.fileCount;
    report.summary = summary.str();
    return report;
}

std::string referencePackSummary()
{
    return detectReferencePack().summary;
}

std::string referencePackManifestPath()
{
    if (const char* env = std::getenv("FIRE4NIX_REFERENCE_MANIFEST"); env != nullptr && *env != '\0') {
        return std::string(env);
    }

    const auto report = detectReferencePack();
    if (!report.available || report.root.empty()) {
        return {};
    }

    const std::filesystem::path root(report.root);
    const auto candidate = (root.parent_path() / "reference-manifest.txt").lexically_normal();
    std::error_code ec;
    if (std::filesystem::exists(candidate, ec) && std::filesystem::is_regular_file(candidate, ec)) {
        return candidate.string();
    }

    if (const char* cfg = std::getenv("FIRE4NIX_CONFIG_DIR"); cfg != nullptr && *cfg != '\0') {
        const auto staged = (std::filesystem::path(cfg) / "reference-manifest.txt").lexically_normal();
        if (std::filesystem::exists(staged, ec) && std::filesystem::is_regular_file(staged, ec)) {
            return staged.string();
        }
        return staged.string();
    }

    return candidate.string();
}

} // namespace fire4nix
