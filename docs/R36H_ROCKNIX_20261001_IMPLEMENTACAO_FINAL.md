# Fire4Nix — instalação única no ROCKNIX 20261001 (R36H/RK3326)

## Confirmado por pesquisa do código oficial

O ROCKNIX estável `20261001` usa no RK3326:

- `TARGET_ARCH=aarch64`, `TARGET_CPU=cortex-a35`;
- `DISPLAYSERVER=wl`, `WINDOWMANAGER=swaywm-env`;
- `WAYLAND_DISPLAY=wayland-1`, `XDG_RUNTIME_DIR=/var/run/0-runtime-dir` (profile do Sway);
- GPU Mali-G31, `GRAPHIC_DRIVERS="mali panfrost"`, configuração ZRAM/swap de tamanho zero;
- sem pacote WPE WebKit identificado no catálogo de pacotes desse release.

Fontes: https://github.com/ROCKNIX/distribution/blob/20261001/projects/ROCKNIX/devices/RK3326/options e https://github.com/ROCKNIX/distribution/blob/20261001/packages/wayland/compositor/sway/profile.d/04-sway.conf .

## WPE / WebKit

A partir do WPE WebKit 2.54, **WPEPlatform** é a API padrão, com plataformas Wayland, DRM e headless. Para o R36H, a primeira tentativa correta é `WPE_PLATFORM=wayland` em uma sessão Sway viva. Evitar forçar `WPE_DISPLAY=wpe-display-wayland` em conjunto: foi documentado um bug de compatibilidade no lançamento 2.54 que podia abortar processos.

- https://wpewebkit.org/blog/2026-10-06-wpe-platform.html
- https://bugs.webkit.org/show_bug.cgi?id=324726

A biblioteca atual no cartão não tem versão de compilação comprovada: os logs mostram o nome e os 174.006.016 bytes, não os metadados de API. Não assumir que seja WPEPlatform habilitado.

## Por que o ZIP anterior NÃO é autossuficiente

O conjunto original do GitHub contém scripts com nomes `bin/browser.arm64` e `bin/fire4nix-wpe-platform`, **não os binários ARM64 reais**. O ZIP 0.87 contém executável nativo compilado, mas não contém a biblioteca `libWPEWebKit-2.0.so.1` de 174 MB nem `WPEWebProcess`, `WPENetworkProcess` e `WPEGPUProcess` que foram apenas observados no aparelho.

**Não** empacotar WPE 2.54 do Debian forky e afirmar compatibilidade: o pacote publicado exige `libc6 >= 2.43`, enquanto os logs do R36H mostram `glibc 2.41`. Fonte: https://packages.debian.org/forky/arm64/libwpewebkit-2.0-1 .

## Instalador de uma única etapa para o cartão atual

O pacote de distribuição `Fire4Nix-R36H-Instalacao-Unica-20261015.zip` incorpora o binário WPEPlatform ARM64 compilado em Ubuntu 24.04 arm64, um launcher controlado para Wayland e homepage offline. O script `Instalar-Fire4Nix-Uma-Vez.sh`:

1. Detecta `roms/tools/Fire4Nix/runtime` da instalação original, com todos os três subprocessos;
2. Faz uma cópia **local** da biblioteca e dos subprocessos para `roms/ports/fire4nix-completo/runtime` sem modificar a origem;
3. Confirma com `--check-library` que o ELF candidato abre a biblioteca antes de ativar o menu;
4. Instala somente depois da verificação e preserva a versão anterior caso falhe;
5. Cria `roms/ports/Fire4Nix.sh`, menu compatível com a lista de extensões de Ports.

Esse processo instala os arquivos numa só execução **se eles já estiverem no cartão**. Ele **não faz** do ZIP um pacote completamente offline para cartão novo. Isso exigiria o envio/extração dos arquivos binários do runtime real ou a compilação cruzada independente de um WPE e de toda a cadeia gráfica compatíveis.

Não desabilita sandbox, não copia drivers Mali, não altera /usr, não altera EmulationStation e não exige recompilar no R36H. Os logs do Terminal R36 Tools continuam independentes.

## Critérios ainda pendentes

- A biblioteca WebKit disponível precisa aceitar `WPE_PLATFORM=wayland` e construção WPEPlatform;
- Dependências transitivas ELF precisam estar presentes e compatíveis;
- Renderização efetiva na tela de 640×480 precisa ser observada;
- Controles nativos/teclado e navegação precisam ser verificados; o executável WPEPlatform atual é um **candidato mínimo**, sem Chrome/abas/teclado virtual completo;
- Sandbox precisa continuar habilitado, inclusive se `bwrap` estiver indisponível.

Sem testes no aparelho, **não alegar que o navegador final está concluído**.
