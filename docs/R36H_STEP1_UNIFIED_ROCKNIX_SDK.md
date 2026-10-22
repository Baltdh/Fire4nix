# Fire4Nix — Etapa 1: SDK de dependências ROCKNIX RK3326 consolidado

## Resultado comprovado (21/10/2026, GitHub Actions em UTC 22/10)

**STATUS: ETAPA 1 CONCLUÍDA PARA OS METADADOS DE COMPILAÇÃO E O ESTÁGIO ARM64.**
A workflow `.github/workflows/r36h-step1-unified-rocknix-sdk.yml` combinou
**15 artefatos independentes** construídos com o toolchain ROCKNIX RK3326 (base
`3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`, GLIBC 2.41).

Execução confirmada [39705580079](https://github.com/Baltdh/Fire4nix/actions/runs/39705580079):
```
TARGET_SHARED_ELF_CHECKED=157
STAGE1_ROCKNIX_COMBINED=PASS_REAL_ELF64_AARCH64_COLLISION_SAFE
TARGET_PC_TOTAL=22
TARGET_PC_MISSING_COUNT=0
SYSROOT_PC_AUDIT=PASS_TARGET_PKGCONFIG_METADATA_ONLY
STAGE_INSTALLABLE=no
WPE_WEBKIT_BUILT=no
```

### Fontes dos 15 artefatos (runs GitHub Actions)

| Conjunto | Run |
|---|---|
| JPEG + oito grupos de dependência | 39683307528 |
| Fontconfig + FreeType + suporte Cairo | 39687860420 |
| Cairo 1.17.8 | 39688962028 |
| ICU 74.1 | 39688837904 |
| HarfBuzz + HarfBuzz-ICU | 39692709765 |
| libglvnd EGL/GLES2 | 39692039643 |
| libepoxy EGL 1.5.10 | 39692741218 |
| libgcrypt 1.11.1 + libgpg-error 1.55 | 39694338119 |
| Wayland 1.23.1 | 39693569119 |
| libwebp 1.6.0 | 39683707451 |
| nghttp2 + libpsl | 39695182915 |
| libxkbcommon 1.6.0 | 39697406436 |
| libsoup3 3.6.5 | 39695603819 |
| libxslt 1.1.43 | 39683799673 |
| Wayland Protocols 1.44 (XML sem ELF de host) | 39705416651 |

Todos os inputs acima foram produzidos por workflows específicos; o
consolidador usa nomes e run IDs explícitos. Não há fallback para pacotes
de desenvolvimento Ubuntu nem download oculto de bibliotecas na integração.

## Correção do último requisito ausente

A auditoria real identificou inicialmente apenas
`TARGET_PC_MISSING_OR_OLD=wayland-protocols min=1.24` (21/22).

ROCKNIX 20260801 utiliza o override efetivo **Wayland Protocols 1.44**,
não a versão genérica 1.45. `scripts/stage-rocknix-wayland-protocols-144.sh`
confere o tarball original pelo SHA256
`3df1107ecf8bfd6ee878aeca5d3b7afd81248a48031e14caf6ae01f14eebb50e`,
confirmado pelo distinfo do FreeBSD para a mesma versão. O script executa
Meson em CI apenas para XML e `wayland-protocols.pc` independentes da
arquitetura; não instala ELF do Ubuntu e não grava no console.
Depois da incorporação, **22/22** passaram.

## Garantias e limites

- Merge recusa arquivos distintos com mesmo caminho, links externos e
  bibliotecas ELF estrangeiras. Confere `ELF64 AArch64`, endianness e
  requisitos diretos GLIBC até 2.41.
- Os arquivos ficam em uma árvore privada `stage1-combined/usr/`.
  Não alteram `/usr/lib` nem cartões do R36H.
- O pacote no GitHub Actions é **SDK/teste**, não um navegador instalável.
- **Ainda não foi demonstrado** o fechamento transitivo de todos os
  `DT_NEEDED` contra a imagem completa do R36H, compatibilidade do
  carregador em produção, sandbox, GIO/GnuTLS, certificados HTTPS,
  renderização Mali/Wayland ou execução física.
- Os artefatos GitHub Actions possuem **retenção limitada**. A
  repetibilidade depois de expirarem requer reconstruir os componentes
  originais e atualizar os run IDs verificados. Não usar esse estágio como
  entrega permanente.

## Próxima etapa

Usar o estágio unificado e o toolchain ROCKNIX 20260801 na configuração
real do WPE WebKit 2.54.1 (perfil sem GStreamer). Verificar o
`CMakeCache.txt`, `DT_NEEDED`, recursos e subprocessos antes de criar
um ZIP de teste físico. Um CMake `configure` concluído ainda não equivale
a compilar o WebKit inteiro.
