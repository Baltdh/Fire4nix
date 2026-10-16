# Fire4Nix 1.01 — investigação da falha 139 do WebKit no R36H real

## Evidências recebidas do aparelho (16/10/2026)

O relatório gerado fisicamente pelo ROCKNIX confirmou:

| Característica | Valor observado |
|---|---|
| Arquitetura | aarch64 |
| Kernel | 7.1.2 |
| glibc reportada por `getconf GNU_LIBC_VERSION` | 2.41 |
| RAM total | 1.005.200 kB |
| RAM disponível no instante do relatório | 691.900 kB |
| WebKit no SD interno | `/storage/games-internal/roms/tools/Fire4Nix/runtime` |
| Tamanho da biblioteca | 174.006.016 bytes |
| WPEWebProcess, WPENetworkProcess, WPEGPUProcess | Os três presentes |
| Bibliotecas `=> not found` por `ldd` | Nenhuma exibida |
| WAYLAND_DISPLAY | wayland-1 |
| XDG_RUNTIME_DIR | /var/run/0-runtime-dir |
| Socket Wayland | Presente |
| DRM render node | Não confirmado |
| gptokeyb | Detectado |
| uinput | Gravável |
| `--check-platform` | **139**, encerramento compatível com SIGSEGV |

**Interpretação:** o pré-teste da API falha sem abrir uma janela. Os arquivos presentes e a ausência de `not found` em `ldd` não comprovam ABI, versões dos símbolos, funcionamento de inicializadores ou GPU. A RAM disponível não sustenta, isoladamente, a hipótese de esgotamento de memória. A versão do WPE instalada **ainda é desconhecida**, porque não foi escrita no relatório anterior.

A árvore de fontes ROCKNIX `20261001` consultada anteriormente declara bibliotecas diferentes das efetivamente reportadas pelo aparelho; **a glibc 2.41 medida no aparelho prevalece**. Isso não significa automaticamente incompatibilidade: a biblioteca instalada precisa ter seus símbolos GLIBC requeridos comparados à 2.41.

## Evidência do código e upstream

- O executável usava `dlopen("libWPEWebKit-2.0.so.1", RTLD_NOW | RTLD_GLOBAL)`. `RTLD_NOW` resolve relocações e `dlopen` pode executar inicializadores de objetos compartilhados **antes de retornar**. Logo, um 139 pode ocorrer mesmo antes de `dlsym`.
- GNU glibc permite `LD_DEBUG=libs,files,versions` para identificar carregamentos e requisitos. Esta flag **não será ligada automaticamente** no SD devido ao volume potencial e à segurança; os checkpoints nativos são suficientes para a primeira investigação. Fonte: https://sourceware.org/glibc/manual/latest/html_node/Dynamic-Linker-Environment-Variables.html
- WPEPlatform tornou-se estável na linha 2.54. Fonte: https://wpewebkit.org/blog/2026-09-16-wpewebkit-2.54.html
- A correção Wayland >=1.25 de WPE 2.54.1 envolvia essencialmente **inicializadores de struct ao compilar**, não foi demonstrada como origem de 139. https://bugs.webkit.org/show_bug.cgi?id=324760
- Um defeito do WPE_DISPLAY antigo na série 2.54 causava **aborto RELEASE_ASSERT**, não necessariamente SIGSEGV; o Fire4Nix já exporta `WPE_PLATFORM=wayland` e remove `WPE_DISPLAY`. https://bugs.webkit.org/show_bug.cgi?id=324726

## Correções no Fire4Nix 1.01

1. **`Diagnosticar-Fire4Nix.sh --safe`:** inspeciona somente arquivos ELF com `readelf` (se disponível), sem executar o WebKit nem `ldd`; mostra arquitetura, símbolo `webkit_web_view_get_wpe_view` e requisito GLIBC máximo da própria biblioteca. O teste em modo safe não abre a janela e não pode provar que a biblioteca funciona.
2. **`Diagnosticar-Fire4Nix.sh --screen`:** executa o pré-teste normal, mas registra a última etapa `[FIRE4NIX-NATIVE]` anterior ao 139. Diferencia travamento durante `dlopen` de um travamento posterior e preserva até 12 checkpoints relevantes no relatório (sem exigir coletar o antigo log binário). Desativa apenas os core dumps desta execução, para evitar um dump enorme no cartão.
3. **Executável nativo:** marca `dlopen success`, início/fim de `dlsym` das funções de versão, começo/fim de chamadas `webkit_get_*_version`, início/fim da busca de símbolos de WebKit. Isso ajuda a distinguir inicializadores, chamada de versão e verificação WPE.
4. **Ports:** o diagnóstico `Fire4Nix-Teste-101.sh` começa em `--safe`. O teste gráfico continua separado. Não substitui a instalação do navegador nem instala drivers.

## Sequência para confirmar a origem real

1. Extrair o pacote 1.01 no SD e usar `sh Diagnosticar-Fire4Nix.sh --safe`. Fotografar o resumo. Se `readelf` não existir no firmware, será registrado `readelf_unavailable`; **não** iremos supor arquitetura de biblioteca sem a ferramenta.
2. Opcionalmente repetir com `sh Diagnosticar-Fire4Nix.sh --screen`. Se der 139 novamente, fotografar `WPEPlatform_fault_stage` no resumo e as linhas `WPEPlatform_native_checkpoints` no relatório em `/storage/Fire4Nix-Diagnostico-101.txt`.
3. Comparar `wpe_glibc_max_required` à glibc **2.41** do próprio aparelho. Se a biblioteca exigir `GLIBC_2.42` ou posterior, será necessário substituí-la por build compatível. Se não exigir, testar separadamente os demais elos do carregador e construtores.
4. Somente depois do pré-teste passar, tentar criar a janela WPE; não mexer nos controles físicos antes de superar o 139.

## Limites

CI AArch64 mock garante os nomes e os estados dos relatórios com falso processo que retorna 139, mas não reproduz o SEGFAULT real do motor de 174 MB. O motor, suas dependências transitivas e a Mali/Wayland ainda precisam ser testados no console antes de declarar compatibilidade ou fornecer um "runtime corrigido".