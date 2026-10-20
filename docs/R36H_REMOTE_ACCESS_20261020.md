# Continuidade e acesso temporário — 20/10/2026

## Evidência atual

PR #33 aberta, head `c3a7df3b3fe66ba2c71b9ccb87fa6e1e572a9b72` na consulta.
A descrição dessa PR e o documento v1.11 falam em resgate íntegro em um teste anterior.
O dossiê posterior de 20/10 registra três cópias não-ELF e ZIP com `short read`.
Não assumir que as cópias são os mesmos bytes: comparar identidade/hash com original
confiável antes de instalar. Não repetir as leituras de cabeçalho já documentadas.
A CI anterior validou scripts e fixtures; WebKit funcional no R36H segue pendente.

## Resultado da inspeção do Hub

Fonte: `R36-Hub-1.18-Base-Original.sh`, payload SHA256
`f68ab3df45dc5108fcbf8deadb009ef55c28ddc7de9a56cf496997e39f93488f`.
A versão atualmente executada no aparelho ainda precisa ser confirmada.

`transfer/server.py` tem PIN de oito dígitos, cookie de sessão e limitação de
login; `remote_terminal.py` exige autorização local de 1800 segundos.
Mas `enforce_host()` exige IP privado/loopback/link-local e `enforce_origin()`
aceita somente `http://` + Host. Um hostname HTTPS externo falha nessas
verificações. Reescrever apenas Host não resolve o Origin do login.
Não remover essas proteções nem confiar cegamente em X-Forwarded-*.

## Primeira etapa implementada

- `tools/remote/preflight.sh`: verifica ferramentas localmente, sem abrir túnel,
  sem rede e sem criar relatório. Não faz diagnóstico de WebKit novamente.
- `tools/remote/share_report.py`: disponibiliza apenas uma cópia em memória de
  um relatório escolhido explicitamente, em `127.0.0.1:8767`.
- Senha aleatória de 192 bits por execução, cookie Secure/HttpOnly/SameSite,
  dez falhas bloqueiam login até reinício local, expiração padrão de 600 segundos
  (máximo 900), saída por Ctrl+C/SIGTERM. Não aceita comandos, upload, proxy,
  navegação de arquivos ou caminhos enviados pelo visitante.
- Servidor não inicia nem instala cloudflared e não altera Hub, firmware ou SD.
- Selecionar apenas relatório técnico revisado, sem credenciais/dados pessoais.
  A leitura do arquivo é limitada a 2 MiB e recusa symlink final/dispositivos.
- É uma primeira conexão de consulta, não administração remota do R36H.

## Fluxo operacional pendente no aparelho

1. Executar o preflight pelo terminal do Hub. Se cloudflared não estiver
   instalado, obter versão ARM64 oficial e verificar seu checksum antes de
   executar; essa instalação ainda não foi preparada nem autorizada nesta etapa.
2. Transferir o script Python pelo Hub para uma pasta nova e abrir em terminal
   local dedicado, para que Ctrl+C continue disponível:

   `python3 share_report.py --report /storage/Fire4Nix-Dependencias-ELF.txt`

3. Após revisar o relatório e autorizar explicitamente o acesso externo, usar
   outro terminal local dedicado para o túnel, limitado também a dez minutos:

   `timeout -s TERM -k 5 600 cloudflared tunnel --url http://127.0.0.1:8767 --allowed-mail SEU_EMAIL`

   É um modelo, não comando já executado. Verificar suporte de `timeout` e de
   `--allowed-mail` antes. Não apontar esse túnel para 8765/8766.
   Encerrar o processo cloudflared com Ctrl+C revoga o túnel imediatamente;
   encerrar o leitor revoga acesso ao relatório mesmo se o túnel continuar.
   O botão “Desligar servidor” do Hub não encerra estes processos separados.
4. Compartilhar a URL privadamente. O navegador remoto deve passar pelo login
   por email do provedor e pela senha temporária do leitor. A autenticação
   interativa no navegador Work ainda não foi testada; requer participação do
   titular no login. Nunca publicar URL/senha/email em GitHub ou relatórios.
5. Validar consulta, expiração e indisponibilidade após encerramento. Só depois
   considerar uma interface restrita de diagnóstico com ações fixas.

Documentação oficial consultada em 20/10/2026:
https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
Documenta `--allowed-mail`, PIN por email, necessidade de navegador interativo,
encerramento pelo processo e ausência de garantia de disponibilidade.

## Validação e limitações

`python3 native/tests/test_remote_report.py`: autenticação, cookies, escape HTML,
origem, bloqueio de tentativas, expiração, rejeição de rotas de terminal/arquivos,
symlink e limite de tamanho. Testes HTTP locais, não túnel real nem teste ARM64.
O preflight neste ambiente encontrou Python/timeout e não encontrou cloudflared;
isso não descreve o R36H. Nenhuma conexão ao aparelho foi estabelecida.

Próximo dado mínimo: presença de cloudflared no R36H. Não é necessário retirar SD,
reexecutar auditoria ELF, descompactar o resgate ou modificar a instalação.
