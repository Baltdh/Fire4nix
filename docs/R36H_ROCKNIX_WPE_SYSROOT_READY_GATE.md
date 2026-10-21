# Fire4Nix — Critério de prontidão do sysroot ROCKNIX RK3326

## Situação de 20/10/2026

- **JavaScriptCore compilado de verdade** em Ubuntu AArch64: 207 objetos, executável `jsc`, execução JS com arrays/JSON/BigInt, requisito de símbolo GLIBC_2.38; GitHub Actions [39514905438](https://github.com/Baltdh/Fire4nix/actions/runs/39514905438) SUCCESS.
- **54 objetos WPEPlatform/Wayland/headless** compilados. Na porta WPE 2.54.1 este alvo é `OBJECT`, não uma `libWPEPlatform.so` independente.
- **Toolchain ROCKNIX 20260801 RK3326 real**: primeira falha de fetch 7-Zip corrigida por mirror com SHA256 idêntico; segunda falha `configtools` corrigida da mesma forma, cópia de checkout somente; nova tentativa [39520551993](https://github.com/Baltdh/Fire4nix/actions/runs/39520551993) executando. Os resultados Ubuntu AArch64 **não** podem ser instalados no R36H.
- O backup recuperado do aparelho contém WebKit ELF AArch64 válido mas vincula 9 bibliotecas GStreamer; `libgstvideo` possui `GST_CAT_DEFAULT` indefinido, não resolvido pelas bibliotecas do sistema pesquisadas. **Não usar como motor funcional.**

## Como executar o novo auditor em host de desenvolvimento

```sh
FIRE4NIX_ROCKNIX_SYSROOT=/caminho/para/rocknix-source/build.ROCKNIX-RK3326.aarch64/toolchain/aarch64-rocknix-linux-gnu/sysroot \
  sh rocknix-integration/audit-wpe-sysroot-pkgconfig.sh --inspect
```

O modo `--inspect` retorna `TARGET_PC_MISSING_OR_OLD` para componentes ausentes/antigos, sem modificar os arquivos. `--pc-ready` falha com código 6 se faltar metadado, adequado a futuros bloqueios no CI. O script **zera `PKG_CONFIG_PATH` do host** e pesquisa exclusivamente `.pc` de dentro do sysroot.

Os 22 componentes representam bibliotecas e dados esperados no perfil WPE mínimo (GStreamer desativado). A origem e os requisitos estão em `Source/cmake/OptionsWPE.cmake` da tag `wpewebkit-2.54.1`. Alguns Find*.cmake conseguem identificar bibliotecas por outras vias mesmo sem `.pc`; portanto uma ausência no auditor pode exigir checagem manual e não é necessariamente falha definitiva do CMake. **Presença e versão de `.pc` não provam que o objeto ELF, headers ou ABI estejam válidos.**

## Portões posteriores indispensáveis

1. `check-rocknix-sdk.sh --check`: `libc.so.6` ELF AArch64 e versão máxima **GLIBC 2.41**, symlink dentro do sysroot.
2. `check-rocknix-compiler.sh --check`: compila/linka C e C++ pequenos com o toolchain efetivo, lê ELF AArch64 e confirma o `CMAKE_SYSROOT`.
3. Compilar as quatro receitas faltantes (`libsoup3`, `libpsl`, `glib-networking`, `libtasn1`) **com o toolchain ROCKNIX**, não reaproveitar as libs Ubuntu.
4. WPE WebKit 2.54.1 `USE_GSTREAMER=OFF`: configurar, validar `CMakeCache.txt`, compilar CMake no SDK, auditar `DT_NEEDED`, todos os subprocessos e módulos GIO/TLS, recursos e certificados CA.
5. Criar pacote fechado no **ext4 interno** do R36H, primeiro abrir `www/primeiro-teste-r36h.html` offline no Wayland. Confirmar visualmente quatro cores, `JS_OK`, `FRAME_OK`, botão A/Enter e ausência de encerramento 139. Depois testar HTTPS, controles e memória.

**Nada deste novo auditor compila ou instala o navegador.** Não substituir `/usr/lib`, não tocar no firmware e não usar o cartão externo exFAT problemático como área de build.
