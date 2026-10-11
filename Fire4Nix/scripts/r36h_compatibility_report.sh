#!/bin/bash
# Read-only device report: no installs, network access or system changes.
set -u
DEST="${FIRE4NIX_REPORT_DIR:-$(cd -- "$(dirname -- "$0")" && pwd)}"
REPORT="$DEST/Fire4Nix-R36H-relatorio.txt"
mkdir -p "$DEST" || exit 1
{
  printf 'Fire4Nix — diagnóstico de compatibilidade R36H\n'
  date -u
  printf '\n=== Sistema ===\n'
  uname -a
  [ ! -r /etc/os-release ] || cat /etc/os-release
  printf '\n=== ABI ===\n'
  command -v getconf >/dev/null && getconf GNU_LIBC_VERSION
  command -v ldd >/dev/null && ldd --version 2>&1 | head -n 3
  printf '\n=== Bibliotecas disponíveis ===\n'
  for base in /lib /lib64 /usr/lib /usr/lib64; do
    [ -d "$base" ] || continue
    find "$base" -maxdepth 3 \( -name 'libc.so*' -o -name 'libstdc++.so*' -o -name 'libEGL.so*' -o -name 'libGLESv2.so*' -o -name 'libwayland-client.so*' -o -name 'libwpe*.so*' -o -name 'libWPE*.so*' \) -print 2>/dev/null
  done
  printf '\n=== Versões exportadas ===\n'
  if command -v strings >/dev/null; then
    for base in /lib /lib64 /usr/lib /usr/lib64; do
      [ -d "$base" ] || continue
      find "$base" -maxdepth 3 \( -name 'libc.so.6' -o -name 'libstdc++.so.6' \) 2>/dev/null | while IFS= read -r lib; do
        case "$lib" in */libc.so.6|*/libstdc++.so.6)
          printf '\n%s\n' "$lib"
          strings "$lib" 2>/dev/null | sed -n '/^GLIBC_[0-9][0-9.]*$/p; /^GLIBCXX_[0-9][0-9.]*$/p' | sort -Vu
          ;; esac
      done
    done
  else
    printf 'strings indisponível; versões exportadas não coletadas.\n'
  fi
  printf '\n=== Sessão gráfica ===\n'
  printf 'WAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nDISPLAY=%s\n' "${WAYLAND_DISPLAY:-}" "${XDG_RUNTIME_DIR:-}" "${DISPLAY:-}"
  [ ! -d /dev/dri ] || ls -l /dev/dri
  printf '\n=== Memória ===\n'
  sed -n '/^MemTotal:/p; /^MemAvailable:/p' /proc/meminfo
  printf '\n=== Ferramentas ===\n'
  for tool in bash timeout file readelf strings bwrap weston cog; do command -v "$tool" || true; done
  printf '\nFim. Este relatório não comprova funcionamento do navegador.\n'
} > "$REPORT" 2>&1
printf 'Relatório salvo em %s\n' "$REPORT"
if command -v dialog >/dev/null && [ -t 1 ]; then
  dialog --title 'Fire4Nix: diagnóstico concluído' --msgbox "Relatório salvo em:\n$REPORT\n\nEnvie esse arquivo para conferir a compatibilidade." 12 65
fi
exit 0
