# Fire4Nix 0.99 — seleção por ABI, atualização do motor e staging WPE para ROCKNIX

## Problema identificado

Até 0.98, o instalador escolhia a primeira biblioteca `libWPEWebKit-2.0.so.1` encontrada, mesmo quando ela era incompatível com a API `WPEPlatform` do executável. Se existissem duas bibliotecas em diferentes pastas/cartões SD, a alternativa funcional poderia ser ignorada. Havia ainda outra falha: uma atualização **apenas do runtime WebKit**, com launcher e página inicial inalterados, podia ser ignorada como "já instalada".

## O que mudou

1. **Pré-seleção por compatibilidade:** cada biblioteca encontrada deve trazer os três subprocessos (WPEWebProcess, WPENetworkProcess, WPEGPUProcess) e passar `fire4nix-native-aarch64 --check-platform` com `LD_LIBRARY_PATH` e `WEBKIT_EXEC_PATH` apontando para a própria origem. Uma candidata inválida é ignorada **antes** de qualquer cópia grande para o SD.
2. **Busca entre cartões e diretórios:** procura em `tools/Fire4Nix/runtime`, `ports/Fire4Nix/runtime`, `ports/fire4nix-completo/runtime` do cartão selecionado e em destinos dos dois cartões ROCKNIX. Um `FIRE4NIX_RUNTIME_SOURCE=/caminho/runtime` opcional dá prioridade a uma origem personalizada, sem dispensar as verificações.
3. **Upgrade somente do WebKit:** quando o pacote **inclui** `Fire4Nix/runtime`, o instalador compara a biblioteca e os três executáveis auxiliares com a instalação atual, impedindo que um motor novo seja descartado por engano.
4. **Preservação da instalação antiga:** se nenhum runtime passa na pré-verificação, termina com código 5 sem trocar a instalação anterior; se nenhuma biblioteca foi encontrada, mantém o código 3.

**Importante:** o código 0 de `--check-platform` só confirma que o carregador e a API necessária estão presentes; não demonstra funcionamento real do Wayland/Mali ou ausência de problemas de renderização.

## Ferramentas de compilação e montagem do motor

A receita `Preparar-WPE-ROCKNIX-2.54.1.sh` agora suporta `--stage`, além de `--plan`, `--configure` e `--build`. Depois da compilação no SDK ARM64 do ROCKNIX `20261001`, `--stage` executa `cmake --install` com `DESTDIR` apontando para uma pasta isolada, sem alterar o `/usr` do computador. Em seguida chama `Empacotar-WPE-ROCKNIX.sh`.

A ferramenta `Empacotar-WPE-ROCKNIX.sh` recebe um DESTDIR de WebKit produzido **pelo SDK ROCKNIX** e uma pasta nova de saída:
```sh
FIRE4NIX_WPE_DESTDIR=/caminho/para/destdir \
FIRE4NIX_WPE_RUNTIME_OUT=/caminho/para/runtime \
sh Empacotar-WPE-ROCKNIX.sh --stage
```

Ela recusa destinos já existentes ou pastas perigosas e verifica:

- `libWPEWebKit-2.0.so.1` como ELF AArch64 e símbolo público `webkit_web_view_get_wpe_view` no dynsym.
- Presença e arquitetura AArch64 dos três subprocessos.
- Validade básica dos links simbólicos `.so` dentro da pasta isolada.
- Geração de `SHA256SUMS.txt` para a biblioteca e os processos.
- Relatório `BUILD-REPORT.txt` com bibliotecas `DT_NEEDED` e ressalva expressa de que ainda devem ser verificadas contra a instalação ROCKNIX e o hardware real.

O resultado é **candidato a runtime**, não um motor declarado funcional. Algumas dependências de execução, recursos embutidos, caminhos de instalação compilados para `/usr`, e integração gráfica precisarão ser identificados e adaptados para um pacote totalmente relocável. Nenhum binário fake usado pela CI é incluído no ZIP entregue ao usuário.

## O que foi testado

- Linux AArch64: construção e validação do executável Cortex-A35.
- Seleção de um runtime válido depois de rejeitar outro com ABI incompatível.
- Atualização de um pacote no qual apenas o motor WebKit mudou.
- Recusa sem sobrescrever a instalação antiga se todos os candidatos falharem.
- Staging de WebKit mock e processos AArch64 sob um DESTDIR isolado, verificação de checksums e recusa de sobreposição ou processo ausente.
- Continuidade dos testes anteriores de rollback, FAT/exFAT, teclado virtual, gamepad e diagnóstico por foto.

O teste usa WebKit simulado e **não substitui a compilação do WebKit real contra todas as dependências do ROCKNIX, nem o teste no R36H físico**.

## Próxima integração de hardware

Preparar um SDK ROCKNIX `20261001` e compilar o motor WPE 2.54.1 real, validar dependências contra a glibc do sistema e confirmar os caminhos dos recursos WPE. Depois testar `--check-platform`, a página offline e finalmente a janela Wayland no R36H, antes de declarar o navegador pronto.

Fontes: [ROCKNIX — processo de build](https://rocknix.org/contribute/build/), [ROCKNIX — pacotes](https://rocknix.org/contribute/packages/), [WPE WebKit 2.54.1](https://wpewebkit.org/release/wpewebkit-2.54.1.html).
