# Fire4Nix — WebP 1.6.0 compilado no SDK ROCKNIX RK3326 (experimento)

## Contexto e entradas verificáveis

O objetivo é ampliar o estágio AArch64 validado na
[PR #67](https://github.com/Baltdh/Fire4nix/pull/67), contendo sete
dependências reais (zlib 1.3.1, SQLite 3.50.2, libtasn1 4.21.0,
libpng 1.6.40, libffi 3.5.1, PCRE2 10.45 e GLib 2.85.1), com as bibliotecas
WebP necessárias ao suporte de imagens em um futuro motor de navegação WPE.

- Toolchain ROCKNIX RK3326 original, commit
  `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`, da execução
  [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979).
- Sete bibliotecas pré-compiladas e testadas: artefato
  `Fire4Nix-ROCKNIX-SEVEN-REAL-DEPS-PRIVATE-STAGE` da execução
  [39682062894](https://github.com/Baltdh/Fire4nix/actions/runs/39682062894).
- A receita
  `projects/ROCKNIX/packages/graphics/libwebp/package.mk` fixa
  **libwebp 1.6.0**, com saída compartilhada e ferramentas desabilitadas.
- Essa receita **não fornece PKG_SHA256**. Neste teste optamos pelo
  arquivo `libwebp-1.6.0.tar.gz` da distribuição oficial
  `storage.googleapis.com/downloads.webmproject.org/releases/webp/`
  com SHA256 **`e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564`**,
  conforme o [hash do Buildroot para a mesma versão](https://lists.buildroot.org/pipermail/buildroot/2026-January/794888.html).
  A fonte original diferirá, em bytes, do archive autogerado
  `github.com/webmproject/libwebp/archive/v1.6.0.tar.gz` da receita,
  embora represente a versão 1.6.0; não alegar equivalência binária dos arquivos.

## Trabalho reproduzível

Workflow:
`.github/workflows/r36h-eight-real-deps-webp.yml`

Script:
`scripts/build-rocknix-libwebp-eight-deps.sh`

Apenas em GitHub Actions, em checkout e DESTDIR privados:

1. Restaurar o checkpoint do compilador AArch64 e o estágio real das sete
   dependências, conferindo indicadores anteriores de aceite.
2. Reconstruir links SONAME em bibliotecas ELF64 AArch64 regulares
   (os artefatos GitHub não mantêm links simbólicos).
3. Verificar o hash do tarball oficial WebP 1.6.0 **antes** de extraí-lo.
4. Compilar as bibliotecas compartilhadas libwebp, libwebpmux e libwebpdemux
   com o GCC ROCKNIX e opções CMake que desabilitam ferramentas e exemplos.
5. Validar os metadados de desenvolvimento `.pc`, arquitetura AArch64 e
   GLIBC até 2.41, sem depender das bibliotecas GStreamer do console.
6. Ligar um objeto compartilhado **real AArch64** usando as APIs de
   libwebp, demux, mux, GLib e libpng, validando entradas `DT_NEEDED`.
7. Arquivar objetos, cabeçalhos, relatório e logs por período limitado.

## Critério de conclusão

O teste é aprovado somente quando o workflow termina com `success` e a
evidência contém:

- `EIGHT_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64`
- `WEBP_GLIB_PNG_CONSUMER_LINK=PASS_REAL_AARCH64`
- versão `libwebp=1.6.0` pelo pkg-config isolado;
- presença de bibliotecas compartilhadas, não apenas `.a`;
- ausência de ELF não-AArch64 no conjunto de bibliotecas construídas.

## Limitações explícitas

Esta etapa **não** compila o WPE WebKit 2.54.1, não executa o objeto de
teste AArch64 e não verifica renderização gráfica no R36H. Os artefatos
não são pacotes instaláveis. Para entregar o navegador ainda faltam
bibliotecas de desenvolvimento não resolvidas, a construção do motor,
closure `DT_NEEDED`/GLIBC completa, HTTPS/GIO TLS e testes físicos.
