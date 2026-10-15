# Fire4Nix 0.92 — usabilidade, falhas reais e logs no R36H

## Novidades

A página inicial offline `installer/www/inicio.html` ganhou um **teclado virtual** opcional. Na tela de 640×480, pressione **Teclado**, selecione letras com setas e use Enter para confirmar. O teclado é criado somente quando necessário para economizar CPU/memória. Também há espaços, números, pontuação, apagar, limpar e abrir. **Observação:** as setas precisam ser entregues ao navegador pela sessão Wayland; ainda não existe mapeamento direto dos botões físicos do gamepad.

O novo `Diagnosticar-Fire4Nix.sh` é incluído na raiz do ZIP e na pasta instalada `Fire4Nix`. Ele gera `/storage/Fire4Nix-Diagnostico-092.txt`, ou na pasta atual se `/storage` não estiver disponível. Não acessa a rede, não busca arquivos pessoais, não modifica `/usr`, não consulta ou mistura os logs do Terminal R36 Tools.

Coleta somente: nome e versão do sistema operacional, arquitetura, versão glibc quando acessível, RAM disponível, executável ELF, biblioteca WPE, três subprocessos WPE, possíveis sockets Wayland e nós DRM. Quando possível executa `--check-platform` para distinguir carregamento da biblioteca da presença da API WPEPlatform.

O launcher cria e mantém um log **antes** de verificar bibliotecas/Wayland/permissões. O último erro pode ser consultado em `/storage/Fire4Nix-ultimo-resultado.txt`. O limite de até 12 logs na pasta evita encher o cartão de novos testes. O código de saída do processo ARM64 é mantido, inclusive `127` (WebKit ausente), `69` (socket Wayland indisponível), `78` (API WPEPlatform ausente), `70` (renderer inesperadamente encerrado) e `124` (tempo esgotado no teste).

O executável deixa de mascarar um erro do processo de renderização com um evento posterior de `load-finished`, encerra uma sessão interativa quando o renderer morre, e libera o timer de teste quando o loop GLib termina.

## Instalação

1. Extraia `Fire4Nix-R36H-0.92-Completo-Para-Teste.zip`.
2. Execute `sh Instalar-Fire4Nix-Uma-Vez.sh`.
3. Para gerar um relatório **sem abrir o navegador**, execute `sh Diagnosticar-Fire4Nix.sh`.
4. Inicie Fire4Nix em **Ports** para testar a tela. Se falhar, envie `/storage/Fire4Nix-Diagnostico-092.txt` e `/storage/Fire4Nix-ultimo-resultado.txt`.

## Critérios e limites

A CI Linux AArch64 compila o ELF otimizado para Cortex-A35, valida scripts, checa a página inicial via sintaxe JavaScript, simula instalação e rollback, simula versões antigas de WebKit e força encerramento do WebProcess durante carregamento. **Não** há garantia de renderização na GPU Mali, interação dos botões físicos ou navegação real. O ZIP contém a engine ARM64 candidata, mas **não** os aproximadamente 174 MB do runtime WebKit original do cartão. Continua sendo necessária a biblioteca WPE instalada previamente no R36H.

A checagem `--check-platform` confirma apenas símbolos ABI; não confirma renderização, drivers EGL, tela nem sandbox de forma integral.
