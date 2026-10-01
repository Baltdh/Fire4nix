# Build do Fire4Nix para ROCKNIX

## Marco atual: 0.84 beta — WPE runtime

O bloqueio principal continua sendo gerar e validar um executavel
`bin/fire4nix-wpe-platform` ARM64 real para o R36H/RK3326. O projeto nao
considera mais o antigo shell placeholder como binario final.

### Build nativo no ambiente aarch64

Na raiz de `Fire4Nix/`:

```sh
make wpe-arm64
```

O build falha se:

- `pkg-config` ou o compilador C++ nao existirem;
- nenhum pacote WPE WebKit de desenvolvimento for encontrado;
- WPE WebKit estiver abaixo da linha de seguranca 2.52.6;
- o compilador nao tiver alvo `aarch64/arm64`;
- o resultado nao for reconhecido por `file(1)` como ELF ARM64.

Quando aprovado, o executavel e copiado para
`Fire4Nix/bin/fire4nix-wpe-platform`.

### Cross-build com sysroot ROCKNIX

Tambem existe um caminho reproduzivel para compilar fora do console:

```sh
ROCKNIX_SYSROOT=/caminho/para/sysroot \
  sh scripts/build_wpe_cross.sh
```

O script configura `PKG_CONFIG_SYSROOT_DIR`, localiza os diretorios
`pkgconfig` do sysroot e exige um compilador `aarch64-linux-gnu` (ou outro
fornecido em `CXX`/`CROSS_COMPILE`).

## Smoke test no R36H

Depois de instalar/copiar o binario ARM64:

```sh
bash scripts/rocknix_wpe_smoke_test.sh
```

O relatorio verifica arquitetura, socket Wayland, identidade ELF ARM64,
versao WPE, `/dev/dri`, memoria e requisitos basicos de runtime. Isso nao
substitui o teste visual e de controles no aparelho.

## One File Edition

Antes do empacotamento, o runtime WPE preparado precisa ser colocado no layout
portatil:

```sh
sh scripts/stage_wpe_runtime.sh /caminho/para/runtime-wpe-preparado
sh scripts/verify_wpe_runtime.sh
sh scripts/package_one_file.sh
```

O empacotador **recusa gerar o ZIP final** se
`bin/fire4nix-wpe-platform` nao for um ELF ARM64 real ou se o runtime nao
contiver a biblioteca WPE WebKit e os processos Web/Network/GPU ARM64. Quando a verificacao
passar, o resultado vai para `dist/Fire4Nix-OneFile-<versao>.zip`, junto de
um SHA-256.

O ZIP contem um `Fire4Nix.sh` de topo e a pasta `Fire4Nix/`. Ele foi
desenhado para ser extraido diretamente no diretorio de ports do ROCKNIX, sem
instalacao em `/usr/local` e sem exigir terminal no primeiro uso. O launcher
tambem recupera permissao de execucao perdida durante a extracao do ZIP.

## Gate antes da versao final

Ainda precisam ser confirmados no R36H:

1. pagina inicial renderizando em 640x480/fullscreen;
2. D-pad, analogicos, A/B, Start/Select e teclado virtual;
3. voltar/avancar/recarregar/endereco;
4. Wi-Fi, DNS e TLS;
5. audio sem interferir no servico do ROCKNIX;
6. memoria com 1, 3 e 5 paginas;
7. teste continuo de navegacao e recuperacao apos crash do Web Process;
8. comparacao de WPE 2.52.6 e 2.54.x, se ambos estiverem disponiveis.

O build SDL/audit do CI valida logica de host, mas nao substitui o binario WPE
ARM64 nem o teste fisico.
