# Fire4Nix / ROCKNIX R36H — diagnóstico e recuperação (14/10/2026)

## Evidências verificadas nos registros do aparelho

- ROCKNIX oficial 20261001 / kernel 7.1.2 / RK3326 aarch64 / glibc 2.41, sessão Wayland `wayland-1` e diretório `/var/run/0-runtime-dir`.
- `libWPEWebKit-2.0.so.1` é requerida pelo binário e não foi encontrada pelo carregador em uma das tentativas, **apesar de estar** em `Fire4Nix/runtime/lib/`.
- O binário WPE também falha com `Segmentation fault` **139**. A causa interna não está demonstrada (falta backtrace).
- Depois de 139, o launcher atual tenta usar `cog` ausente e substitui o resultado visível por **127**. 127 não é a causa original desse crash.
- `WPEWebProcess`, `WPENetworkProcess`, `WPEGPUProcess` existem no runtime portátil. Não estão nos diretórios do sistema pesquisados pelo preflight.
- `bwrap` está ausente; o sandbox não foi comprovado funcional. **A correção não desabilita o sandbox.**
- A configuração `MALI_WAYLAND_AFBC=0` é sugerida, mas os logs não demonstram que estivesse ativa no processo.
- O terminal independente **Terminal R36 Tools v3** inicializou a interface SDL e saiu com código 0; seu log não é um log do navegador.

## Correção experimental

O arquivo [scripts/Fire4Nix-R36H-Resgate.sh](../scripts/Fire4Nix-R36H-Resgate.sh) é um inicializador separado. Ele:

1. Localiza o pacote Fire4Nix no cartão sem modificá-lo.
2. Define `LD_LIBRARY_PATH` para a biblioteca privada do WPE e `WEBKIT_EXEC_PATH` para os três subprocessos.
3. Verifica dependências diretas/transitivas com `ldd` antes da execução e alerta sobre sandbox.
4. Oferece perfis `--stable` (renderização conservadora), `--normal` (sem workarounds gráficos), `--trace` (rastreio do carregador), e `--check` (somente dependências).
5. Preserva os códigos nativos de erro, sem confundir 139 e 127, e escreve logs legíveis no armazenamento do usuário.

Copie o arquivo .sh para a mesma pasta da instalação ou para Download, rode o script, e consulte `/storage/Fire4Nix-ultimo-diagnostico.txt`. Caso a pasta não seja detectada, use `--root /storage/games-internal/roms/tools/Fire4Nix`.

**Limites**: `sh -n` e os testes de execução simulada confirmam a lógica do wrapper, mas não provam que a GPU, a biblioteca de 174 MB nem a interface gráfica funcionarão no hardware. Validação real requer abrir `www/inicio.html` no R36H e garantir o sandbox ativo.

## Próximo trabalho de engenharia

O repositório atualmente mantém os backups do projeto em arquivos ZIP, sem a árvore-fonte dos scripts originais extraída e versionada. Para uma correção definitiva, extrair os scripts originais e o C/C++ do `fire4nix-wpe-platform` para uma árvore-fonte auditável, corrigir o erro de fallback dentro de `fire4nix_env.sh`, executar testes de carregador, backend EGL/Wayland e backtrace do 139, e gerar um build ARM64 testável. Não substituir drivers do sistema nem copiar bibliotecas WPE para `/usr/lib`.
