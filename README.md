# Fire4Nix — ROCKNIX / R36H

O repositório está organizado em duas áreas separadas:

- **`navegador-definitivo/`** — árvore de desenvolvimento do navegador (código, scripts, recursos e binários existentes).
- **`backups/`** — quatro arquivos ZIP históricos, preservados para recuperação e comparação.
- **`deploy/`** — lançadores de teste para ROCKNIX.
- **`docs/`** — auditorias e procedimentos.
- **`.github/workflows/`** — automações existentes.

## Importante
O nome `navegador-definitivo` identifica a **pasta destinada ao produto final**; não significa que o navegador já esteja pronto ou validado no hardware. O teste real de inicialização no R36H ainda está pendente.

## Instalação experimental
Copie o **conteúdo completo** de `navegador-definitivo/` para `/storage/roms/ports/Fire4Nix/` e o script `deploy/Fire4Nix-ROCKNIX.sh` para a pasta de scripts reconhecida pelo menu ROCKNIX. Veja `docs/ROCKNIX_TEST_INSTALL.md`.

Não copie os ZIPs da pasta `backups/` para o console. Eles não fazem parte do pacote de execução.

## Conservação
Os backups não foram apagados, recompilados ou alterados. Antes de excluir qualquer um, é necessário comparar os arquivos dentro dos ZIPs e confirmar que as versões importantes estão na pasta do navegador.
