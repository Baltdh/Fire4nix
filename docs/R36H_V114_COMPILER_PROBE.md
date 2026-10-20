# Fire4Nix 1.14 — validar o compilador real antes da compilação WPE

Data: 20/10/2026. Complementa `docs/R36H_V113_SDK_PREFLIGHT.md`.

## Problema
O preflight 1.13 confirmou apenas o ELF `libc.so.6` do sysroot. Um `CMAKE_TOOLCHAIN_FILE` incorreto poderia usar um compilador do host, usar outro sysroot ou produzir binários da arquitetura errada mesmo depois de o ELF do sysroot passar. O WebKit pode levar muito tempo e memória para compilar, logo o erro deve ser detectado antes.

## Solução
`rocknix-integration/check-rocknix-compiler.sh` usa um projeto **CMake/Ninja descartável**, em `TMPDIR`:
- Invoca primeiro `check-rocknix-sdk.sh` e recusa sysroot do host.
- Exige que o `CMAKE_SYSROOT` efetivamente resolvido pelo CMake coincida com `FIRE4NIX_ROCKNIX_SYSROOT`, sem sobrepor esse valor no comando de configuração.
- Verifica que `CMAKE_SYSTEM_PROCESSOR` é AArch64/arm64.
- Compila e liga dois pequenos executáveis reais, C e C++.
- Verifica ambos com `readelf -h` (ELF AArch64) e limite das referências `GLIBC_N.N`.
- **Nunca executa** os binários do alvo; apaga somente sua pasta temporária própria.
- Não executa `sudo`, não instala nem altera o firmware.

Uso no host Linux de compilação (não executar no R36H):
```sh
export FIRE4NIX_ROCKNIX_RELEASE=20260801
export FIRE4NIX_ROCKNIX_SYSROOT=/caminho/real/do/rocknix/sysroot
export FIRE4NIX_ROCKNIX_TOOLCHAIN=/caminho/real/do/rocknix/toolchain.cmake
sh rocknix-integration/build-wpe-2.54.1.sh --preflight
sh rocknix-integration/build-wpe-2.54.1.sh --probe-compiler
```
O segundo comando precisa mostrar `COMPILER_PREFLIGHT=PASS` e `status=COMPILER_VERIFIED_NO_WEBKIT_BUILD`. As etapas `--configure`, `--build` e `--stage` exigem a mesma validação.

## Limitações
- Um SDK real de ROCKNIX 20260801 ainda precisa ser obtido ou construído pelo processo oficial, não simulado. Documentação: https://rocknix.org/contribute/build/ (`make docker-RK3326`, após configuração do builder).
- Os testes GitHub Actions são **negativos/mock** e não demonstram que exista um SDK correto disponível. A verificação positiva só fica comprovada ao obter um SDK real e executar os probes compilados.
- O compilador pode usar regras adicionais de busca de dependências ou opções que o WPE não usa. Uma passagem bem-sucedida não substitui auditar as bibliotecas completas após empacotar.
- O ZIP antigo possui `GST_CAT_DEFAULT` e não foi corrigido; o navegador **não está rodando** no R36H. O cartão SD exFAT tinha erros, e o console apresentou tela preta — não tentar modificar firmware.
- O arquivo `wpewebkit-2.54.1.tar.xz` tem SHA-256 oficial `0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9`, confirmado em https://wpewebkit.org/release/wpewebkit-2.54.1.html

## Próxima etapa
Obter SDK e toolchain reais compatíveis, validar via `--probe-compiler`, depois `--configure` com `USE_GSTREAMER=OFF`, compilar, empacotar privado e testar WPE no hardware recuperado.
