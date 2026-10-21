# Fire4Nix — Fontconfig 2.17.1 com bibliotecas ARM64 reais para Cairo

## Objetivo técnico

O [diagnóstico WPE WebKit 2.54.1 com SDK real 39684582460](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460) falhou na descoberta de HarfBuzz. A receita original HarfBuzz requer Cairo, FreeType e GLib. A receita **efetiva** de Cairo no ROCKNIX 20260801 exige também Fontconfig e Pixman.

A [PR #74](https://github.com/Baltdh/Fire4nix/pull/74) compilou Pixman 0.46.2 para AArch64; a [PR #73](https://github.com/Baltdh/Fire4nix/pull/73) compilou FreeType 2.13.3; a [PR #68](https://github.com/Baltdh/Fire4nix/pull/68) compilou libxml2 2.14.4. Esta etapa acrescenta **Fontconfig 2.17.1**, com Expat 2.7.1, a uma árvore alvo privada, sem instalar pacotes no console.

## Fontes e artefatos fixados

| Pacote | Fonte do SDK ROCKNIX | Versão |
|---|---|---|
| Fontconfig | `packages/x11/other/fontconfig/package.mk` | 2.17.1 |
| Expat | `packages/textproc/expat/package.mk` | 2.7.1 |
| Pixman | [Actions 39686365026](https://github.com/Baltdh/Fire4nix/actions/runs/39686365026) | 0.46.2 |
| FreeType | [Actions 39685435460](https://github.com/Baltdh/Fire4nix/actions/runs/39685435460) | 2.13.3 |
| libxml2 | [Actions 39683023507](https://github.com/Baltdh/Fire4nix/actions/runs/39683023507) | 2.14.4 |
| Compilador | [Actions 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979) | aarch64-rocknix-linux-gnu |

Commit ROCKNIX `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.

Fontconfig SHA256 `9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541`, conforme receita upstream. Expat SHA256 `354552544b8f99012e5062f7d570ec77f14b412a3ff5c7d8d0dae62c0d217c30`.

Os artefatos são baixados **com identificadores exatos de execução**; o script `scripts/assemble-rocknix-fontconfig-stages.py` impede links simbólicos que escapem, colisões de conteúdo divergente e bibliotecas compartilhadas incompatíveis com AArch64. Os links de desenvolvimento perdidos por ZIP são reconstruídos apenas a partir de um ELF AArch64 genuíno e seu `DT_SONAME`.

## Critérios de conclusão e limitações

- Executar o workflow `.github/workflows/r36h-rocknix-fontconfig-cairo-prereq.yml` em Ubuntu apenas como **host de compilação**.
- Validar fontes oficiais por SHA256, binários alvo ELF64 AArch64 e versões GLIBC <= 2.41.
- Usar `pkg-config` apontado **somente** ao DESTDIR AArch64.
- Comprovar os `DT_NEEDED` de `libfontconfig.so.1`, `libfreetype.so.6` e `libexpat.so.1` na biblioteca e no consumidor, junto a libxml2 e Pixman.
- Não executar nenhum binário do target em Ubuntu, não instalar nada em `/usr/lib` e não modificar o SD ou firmware do R36H.
- Um CI verde comprova **somente Fontconfig e dependências prévias**, não a compilação de Cairo, HarfBuzz, WebKit, o funcionamento de HTTPS ou a exibição gráfica no R36H.

## Próximo passo

Compilar Cairo **1.17.8** efetivo do ROCKNIX com Fontconfig/Pixman/FreeType/libpng/zlib/GLib, inspecionando também suas dependências para o ambiente Wayland. Depois compilar HarfBuzz **11.2.1**, reexecutar a descoberta CMake do WPE e avançar para a compilação real do motor.

## Resultado auditado em 21/10/2026

A execução [39687860420](https://github.com/Baltdh/Fire4nix/actions/runs/39687860420)
terminou **SUCCESS** no commit `21ce0b514f595ef1b6056ac7e5b4efd07d715311`.

- `FONTCONFIG_INPUT_STAGES=PASS_REAL_AARCH64_COLLISION_SAFE`
- `EXPAT_TARGET=PASS_PREVIOUSLY_VERIFIED_CI_AARCH64`:
  importação somente do Expat 2.7.1 do artifact previamente validado
  [39678297202](https://github.com/Baltdh/Fire4nix/actions/runs/39678297202);
  uma nova tentativa de download de Expat foi rejeitada por checksum divergente.
- `FONTCONFIG_SOURCE_URL=https://ftp2.osuosl.org/pub/blfs/conglomeration/fontconfig/fontconfig-2.17.1.tar.xz`;
  SHA256 **idêntico** ao `PKG_SHA256` do ROCKNIX
  `9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541`.
  A URL atual no GitLab retornou um tarball com hash diferente. Usar apenas
  a versão exata validada, sem reduzir controles de integridade.
- `FONTCONFIG_BUILD=PASS_REAL_ROCKNIX_AARCH64`
- `FONTCONFIG_VERSION=2.17.1`
- `FONTCONFIG_FREETYPE_EXPAT_XML_PIXMAN_CONSUMER=PASS_REAL_AARCH64`
- `FONTCONFIG_GLIBC=PASS_MAX_2_41`
- Artifact temporário de compilação:
  [12387232114](https://github.com/Baltdh/Fire4nix/actions/runs/39687860420/artifacts/12387232114)
  (`Fire4Nix-ROCKNIX-Fontconfig-2.17.1-CAIRO-PREREQ-TEST-ONLY`,
  17.692.152 bytes).

**Não são testes físicos de tela, input ou HTTPS**. O artefato é uma
árvore de compilação experimental para o Cairo, não um aplicativo para
executar no R36H.
