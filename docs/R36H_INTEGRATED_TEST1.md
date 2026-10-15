# Fire4Nix 0.84 — teste integrado R36H / ROCKNIX

Este lançamento experimental reúne as correções dos logs coletados no R36H em 14/10/2026 e os arquivos C++/shell do backup mais completo do projeto.

## Instalação sem apagar o ambiente

1. Faça cópia de segurança dos seus arquivos do cartão antes de atualizar.
2. Extraia `Fire4Nix-R36H-0.84-integrated-github.zip` ou o pacote gerado localmente em `Download`/SD, mantendo a estrutura `Tools/Fire4Nix`.
3. Execute `sh Atualizar-Fire4Nix-R36H.sh` no Terminal R36 Tools **a partir da pasta extraída**. O instalador atualiza a pasta `/storage/games-internal/roms/tools/Fire4Nix` ou `/storage/games-external/roms/tools/Fire4Nix`, se já existir. Se o caminho for outro: `FIRE4NIX_DEST=/caminho/existente sh Atualizar-Fire4Nix-R36H.sh`.
4. Abra pelo menu ROCKNIX e confira se exibe `www/inicio.html` (offline), depois tente uma página HTTPS leve.
5. Se falhar, rode `Fire4Nix-R36H-Resgate.sh` **na pasta instalada** e envie `/storage/Fire4Nix-ultimo-diagnostico.txt` e o log da aplicação. Não misture com `Terminal-R36-inicio.log`.

O instalador guarda versão anterior dos scripts, executável WPE e configuração em `backup-prev-AAAAMMDD-HHMMSS/`, preserva executável WPE e biblioteca já instalados no cartão e não modifica o firmware ou drivers Mali.

## Principais correções

- Seleção de socket Wayland existente (o dispositivo informou `wayland-1`) e ambiente real `XDG_RUNTIME_DIR`.
- A biblioteca privada `runtime/lib/libWPEWebKit-2.0.so.1` e subprocessos do WPE são expostos apenas ao processo Fire4Nix.
- Evita diretórios de dependências `armhf` no carregador `aarch64`.
- Evita uso do `cog` ausente como fallback após SIGSEGV do binário WPE; preserva código real `139`.
- Corrige variáveis de log não inicializadas e retorno `1` genérico do dispatcher.
- Cria página inicial offline e logs de erro legíveis.

## Validações

- Shell `bash -n`/`sh -n`, integridade de ZIP, geração reprodutível em CI.
- Teste de atualização preservando o executável, arquivo de configuração, lib WPE e backup.
- Teste simulado local do processo WPE preservando o retorno `139` e caminhos do runtime.

**Ainda não validado no aparelho real**: início gráfico e navegação, comunicação com GPU Mali, sandbox dos WebProcess e causa interna do SIGSEGV. O backup GitHub não contém a biblioteca WebKit 174MB vista no R36H. Este é um **pacote de atualização** de uma instalação existente, não um motor WebKit recém-compilado.

## Histórico e organização

O log do terminal `Terminal-R36-inicio.log` corresponde exclusivamente ao **Terminal R36 Tools v3**, cujo primeiro frame SDL foi apresentado e saída foi 0. Os logs `Fire4Nix*` e `fire4nix*` correspondem ao navegador. Registros originais permanecem separados em ZIPs próprios, não misturados no pacote executável. Documentação histórica: `docs/R36H_WPE_DIAGNOSTICO_2026-10-14.md`.
