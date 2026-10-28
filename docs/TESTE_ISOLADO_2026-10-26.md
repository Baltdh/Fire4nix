# R36H: reconciliacao e teste isolado

Base revisada: main 87af930 (PRs 182 e 183). O PR 181 estava em conflito
com a captura completa de logs e o escape de URLs do PR 182. A reconciliacao
mantem ambas as correcoes, incluindo logs exclusivos, timeout de smoke/ABI,
interrupcoes sem retry e descoberta do runtime adjacente ao kit Ports.

O novo `installer/Executar-Teste-Isolado.sh` usa exclusivamente o pacote ao
lado do script. Valida SHA256 antes de dar permissao de execucao, normaliza
locale, conserva codigos de falha e oferece modos auto, normal, software,
diagnose, egl e live. Nao atualiza kits antigos nem modifica firmware.

Validacao local: 214 testes Python aprovados; sintaxe de 64 scripts shell,
54 arquivos Python e um JSON; teste JavaScript offline com DOM simulado.
Cinco testes novos verificam root isolado em caminho com espacos, corrupcao,
manifesto ausente, modo invalido e arquitetura incorreta. Os 23 testes de
resgate preservam casos de ambos os PRs, incluindo log EGL fora do tail.

Pacote entregue: Fire4Nix-R36H-Teste-Isolado-20261026.zip. O runtime e o
executavel nativo vieram do artifact 12541332421 do run 40033262653,
source commit 5623e79c8705e7b10882cccf280fb2cfdbedc1b7. SHA256 do ZIP de
entrada validado contra a evidencia CI; CRC aprovado. O empacotador atual
verificou hashes, AArch64, requisitos GLIBC, RPATH e simbolos; confirmou-se
a presenca dos marcadores do fallback EGL e WEBKIT_EXEC_PATH na biblioteca.
Nenhum ELF foi modificado nesta revisao. Copias WPE redundantes sao removidas
apenas por igualdade de hash, conforme PR 183.

Extrair em ports: todos os arquivos ficam sob Fire4Nix-Teste-20261026/.
Executar `sh Fire4Nix-Teste-20261026/Executar-Teste.sh --auto`.
O relatorio aparece em /storage/Fire4Nix-Grafico-Resgate-ultimo.txt e em
um arquivo individual informado por FULL_REPORT. Em TEST_BLOCKED nao usar
um relatorio antigo como resultado desta execucao.

Limites: testes do host nao comprovam frames no R36H. O smoke pode fechar
apos carregar; --live permite observar cores e JS OK. O timeout envia
SIGTERM e depende da resposta do processo/driver. O modo Skia CPU ainda
depende do ambiente EGL. Nao foi confirmado novo resultado fisico.
