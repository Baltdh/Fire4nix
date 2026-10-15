# Auditoria e otimização Fire4Nix 0.87 — R36H / ROCKNIX

## Materiais revisados

- Pacote integrado `Fire4Nix-R36H-0.86-Pacote-Integrado-Seguro.zip`: **106 arquivos**, aproximadamente **1.081.696 bytes comprimidos**.
- Scripts do Fire4Nix, instalador, mecanismo de seleção WPE/Cog, sonda ARM64 e relatório de início do R36H.
- O log `Terminal-R36-inicio.log` continua sendo um registro de **outro programa**, não uma falha da engine Fire4Nix.

## Problemas corrigidos

1. **Distribuição inflada:** o ZIP antigo incluía fontes C++, configurações do EmulationStation, imagens e documentação de compilação. O update de scripts **não copia esses itens para a instalação**, então deixaram de ser redistribuídos. O código-fonte permanece íntegro neste repositório.
2. **Wayland:** o launcher agora confere o socket antes de tratá-lo como Wayland ativo, recupera `wayland-1` quando válido e busca também o caminho `/run/user/<uid>` sem forçar `/usr` ou o firmware.
3. **Cog ausente:** antes de tentar um fallback, verifica `command -v cog`; registra **127** para programa ausente. O crash anterior do WPE **139** continua separado.
4. **Logs excessivos:** rotação conservadora do log principal ao atingir **1 MiB**; arquivo anterior permanece como `.previous`. `FIRE4NIX_MAX_LOG_KB=0` desativa a rotação.
5. **Sonda ARM64:** `--selftest` não requer os 174MB da biblioteca WebKit; `--headless` permite um experimento separado da GPU. Nenhuma dessas opções desativa o sandbox.
6. **Permissões após extrair ZIP:** a sonda tenta restaurar o bit executável em `fire4nix-native-086-aarch64`; reporta 126 caso não seja possível executá-lo.
7. **Integridade na instalação:** o atualizador rejeita `bin/browser.arm64` e `runtime/` se acidentalmente incluídos na pasta do pacote, preservando também a configuração e o tema do usuário.

## Nova construção

Workflow: `.github/workflows/r36h-slim-087.yml`.

- Compilação do candidato C++ em runner Linux AArch64 com GLib/GObject e verificação ELF;
- Construção reprodutível do pacote **runtime-only** a partir de `source_r36h`, em `tools/build_r36h_slim_087.py`;
- Teste com 23 arquivos, sintaxe shell, integridade ZIP, SHA-256, atualização preservando **seis arquivos** existentes e rejeição de binário substituto;
- Ciclo de carregamento WebKit **simulado**, usando `native/tests/mock_wpewebkit.cpp`, inclusive teste headless; não equivale ao driver Mali real;
- O pacote ZIP **não inclui** `libWPEWebKit-2.0.so.1` ou os processos auxiliares WPE, que precisam existir na instalação anterior.

## Teste recomendado

1. Extraia o pacote `Fire4Nix-R36H-0.87-Teste-Otimizado.zip` numa pasta separada do cartão, sem sobrescrever a pasta antiga manualmente.
2. No Terminal R36 Tools, execute `sh Atualizar-Fire4Nix-R36H.sh`.
3. Execute `sh 1-Verificar-Fire4Nix-R36H.sh`.
4. Execute `sh Teste-Nativo-086/Fire4Nix-086-Teste.sh --selftest`.
5. Execute `sh 3-Testar-Navegador-086.sh` e `sh 4-Abrir-Navegador-086.sh`.
6. Se não abrir, execute `sh Teste-Nativo-086/Fire4Nix-086-Teste.sh --headless` e envie `/storage/Fire4Nix-086-Resultado.txt`.

**Importante:** o update é 0.87, mas o candidato WPE nativo conserva o nome `086`, pois não há homologação de uma engine nova no RK3326.

## Limites

- Só testes em CI Linux ARM64 e mocks passaram. **Sem confirmação** da abertura na tela R36H, input do controle, sandbox e compatibilidade Mali.
- WPEPlatform passou a ser a integração padrão com WPE WebKit **2.54**; o backup do projeto contém fontes de referência de WPE **2.52.5**. Não atribuir à biblioteca do cartão uma versão sem checagem direta e não prometer compatibilidade só pelo nome do arquivo.
- A execução real do navegador continuará dependendo do WPE pré-instalado no cartão; a atualização evita apagar o trabalho anterior.
