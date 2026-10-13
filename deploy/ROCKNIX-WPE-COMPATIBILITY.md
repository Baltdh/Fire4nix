# Fire4Nix — compatibilidade WPE para ROCKNIX RK3326

Documento técnico para orientar a criação do pacote **One File Edition**. A aprovação do GitHub Actions em Debian ARM64 **não é** a aprovação no console R36H.

## Referência oficial do ROCKNIX

Arquivos verificados no código-fonte oficial da branch `next`:

- [ROCKNIX glibc](https://github.com/ROCKNIX/distribution/blob/next/packages/devel/glibc/package.mk): `PKG_VERSION="2.44"` no momento da consulta de 13/10/2026.
- [Configuração RK3326](https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/devices/RK3326/options): `TARGET_CPU="cortex-a35"`, `DISPLAYSERVER="wl"`, `WINDOWMANAGER="swaywm-env"`.
- [Diretório web da distribuição](https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/packages/web): lista `curl`, mas não demonstra uma instalação de WPE WebKit ou Cog pronta para uso.

**Atenção:** `next` muda com o tempo e **não identifica o build instalado no R36H**. O teste físico deve informar a versão de libc e as bibliotecas reais, independentemente do que o código-fonte mais recente declara.

## Resultado dos testes WPE da build Debian ARM64

Os testes de 13/10/2026 mostraram:
- launcher WPEPlatform: compilado em Debian ARM64;
- os três subprocessos `WPEWebProcess`, `WPENetworkProcess`, `WPEGPUProcess` estão presentes **no ambiente Debian**, não no aparelho;
- o conjunto build-origin exige símbolos `GLIBC_2.38` no máximo entre os cinco executáveis/objetos auditados;
- a página de teste carregou em um compositor Weston virtual ARM64, com encerramento de processo 0;
- o GitHub Actions não permite a execução de namespaces necessários para a validação com sandbox habilitado; o teste sem sandbox só existe no CI.

O arquivo `WPE-ABI-REQUIREMENTS.json` identifica hashes SHA-256 e bibliotecas NEEDED do launcher, libWPEWebKit e subprocessos, além de versões `GLIBC`, `GLIBCXX` e `CXXABI`. Esse inventário **não inclui a cadeia de dependências de todas as bibliotecas carregadas transitivamente e os módulos carregados com dlopen**.

## Critérios para liberar o pacote completo

1. Obter um sysroot verificável da mesma versão/arquitetura do ROCKNIX instalada (preferencialmente do build oficial correspondente).
2. Recompilar o launcher e o WPE WebKit contra o sysroot alvo ou demonstrar compatibilidade binária completa.
3. Verificar todas as bibliotecas NEEDED, versões de símbolos, plugins TLS/GIO, Wayland/EGL e arquitetura ARM64.
4. Validar o caminho dos subprocessos WPE num pacote relocalizável: builds upstream podem procurar em `/usr/libexec/wpe-webkit-2.0`. O fato de configurar `WEBKIT_EXEC_PATH` **não prova** que o WebKit compilado obedece a essa variável. A implementação/patch precisa ser verificada no WebKit realmente distribuído.
5. Carregar HTML local e página HTTPS, realizar navegação e encerramento sem crash e preservar o sandbox no ROCKNIX físico.
6. Só então empacotar bibliotecas e subprocessos no ZIP completo. **Não distribuir um conjunto Debian como se fosse um runtime ROCKNIX certificado**, nem sobrescrever `libc` do sistema.

## Diagnóstico no aparelho

Use `Fire4Nix-WPE-Diagnostico.sh` na pasta Tools. O relatório padrão é `/storage/fire4nix-wpe-diagnostic.log`. A comparação de versões de `glibc`, `GLIBCXX` e `CXXABI` é apenas uma triagem inicial, e pode ficar inconclusiva na ausência de `readelf` ou bibliotecas disponíveis na sessão.

O ZIP `Fire4Nix-ROCKNIX-ARM64-launcher-only-EXPERIMENTAL.zip` é **somente um launcher experimental**; não é a edição completa.
