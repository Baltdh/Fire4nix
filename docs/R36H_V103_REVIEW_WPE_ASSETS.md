# Fire4Nix 1.03 — auditoria do pacote real e dependências WPE no R36H

## Arquivos efetivamente inspecionados

- ZIP 1.02 do GitHub Actions: executável `fire4nix-native-aarch64` com **67.568 bytes**, scripts POSIX/Bash, interface offline e diagnósticos; sem `runtime/lib/libWPEWebKit-2.0.so.1`.
- ZIP `Fire4Nix-R36H-1.02-PRONTO.zip` é outro empacotamento do mesmo núcleo, com atalho e instalador; seus arquivos comprimidos passaram no teste de integridade. O nome “PRONTO” **não indica** motor WPE embutido.
- Os relatórios de 14/10 e 16/10 mostram biblioteca **174.006.016 bytes**, glibc **2.41** no dispositivo, três auxiliares presentes, Wayland `wayland-1` e falha nativa `139` durante pré-verificação WPEPlatform. Sem backtrace, não atribuir causa à GPU/Mali, glibc, Fontconfig ou sandbox.

## Compatibilidade confirmada em upstream

1. [WPEPlatform oficial, 06/10/2026](https://wpewebkit.org/blog/2026-10-06-wpe-platform.html): com 2.54 a nova API é estável. `WPE_PLATFORM=wayland|drm|headless` escolhe implementação do display. O Fire4Nix usa WPEPlatform via `g_object_new` e deve evitar `WPE_DISPLAY` antigo.
2. [WPE FAQ oficial](https://wpewebkit.org/about/faq.html): fontes fallback ausentes podem causar crash na inicialização. Banco `shared-mime-info` ausente pode prejudicar acesso a arquivos HTML locais. Isto é **hipótese**, ainda não constatada no R36H.
3. [Notas WPE 2.54.1, 06/10/2026](https://wpewebkit.org/release/wpewebkit-2.54.1.html): correção de suporte Wayland >=1.25; **não prova** que essa incompatibilidade causou o SIGSEGV no aparelho.
4. [ROCKNIX Ports](https://rocknix.org/systems/ports/): `roms/ports` aceita `.sh`; [documentação de adicionar jogos](https://rocknix.org/play/add-games/) explica atualizar listas no EmulationStation.

## Problemas objetivos corrigidos em 1.03

- `installer/Fire4Nix-Direto.sh` ignorava a falta dos três WebKitProcess auxiliares ao selecionar a primeira cópia no SD. Agora não escolhe tal cópia e continua procurando uma instalação completa.
- Diagnóstico `--safe`: auditoria de arquivos estáticos e do Fontconfig, sem carregar WPE nem executar o navegador. Relatório avisa ausência de fontes, MIME e bwrap; identifica candidatos de conflito quando `runtime/lib/` inclui `libc`, `libEGL`, `libGLESv2`, `libwayland-client`, `libgbm`, `libdrm` etc.
- Comparação da versão requerida `GLIBC_...` da biblioteca WPE principal com glibc real do console. **A comparação não valida dependências transitivas**: um resultado de requisito direto satisfatório não elimina incompatibilidade.
- Regressões no CI ARM64: instância inválida no caminho prioritário, instalação válida alternativa, teste `--safe` sem executar WPE, arquivos de fontes presentes/ausentes e aviso de biblioteca gráfica potencialmente conflitante.

## Próxima decisão técnica — após captura local

1. Executar `sh Diagnosticar-Fire4Nix.sh --safe` com uma cópia no cartão e fotografar `fontconfig_fonts`, `wpe_elf_arch`, `wpe_glibc_max_required`, `wpe_direct_glibc_compat`, `wpeplatform_static_symbol` e `private_library_conflict_candidate`. Saída padrão: `/storage/Fire4Nix-Diagnostico-103.txt`.
2. Se `wpeplatform_static_symbol=absent_or_unreadable`: a biblioteca atual não expõe a API esperada; reconstruir runtime com WPEPlatform ou usar um launcher legado específico; **não** renomear bibliotecas para fingir ABI.
3. Se `wpe_direct_glibc_compat=requires_newer_than_device`: reconstruir WPE com toolchain/SDK apropriado ao dispositivo, glibc <=2.41, preservando drivers Mali e sandbox.
4. Se símbolos e requisito direto passam e o crash 139 permanece: usar `--screen` e capturar o último checkpoint antes/durante `dlopen`. Segregar conflitos em dependências transitivas, fontes e inicializadores; só então testar Wayland e headless em separado.
5. Apenas declarar o navegador **funcional** depois de renderização HTML local no R36H com sandbox ativo, entrada pelos controles e navegação HTTPS.

**Segurança:** não copiar bibliotecas privadas para `/usr/lib`, não trocar drivers do sistema, não desligar sandbox como solução permanente, não coletar histórico de navegação, cookies ou senhas.
