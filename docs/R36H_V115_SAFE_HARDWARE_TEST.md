# Fire4Nix 1.15 — teste no R36H recuperado

O R36H voltou a ligar, mas o exFAT externo já apresentou corrupção. O teste inicial deve ser estático, sem executar a biblioteca WebKit antiga (GST_CAT_DEFAULT) e sem escrita no SD externo.

## Executar
Copie Fire4Nix-R36H-Teste-Seguro.sh para o R36H, preferencialmente no cartão interno, por SFTP ou pelo celular.
Execute no R36 Hub com o caminho correspondente ao local onde salvou:

    sh '/storage/games-internal/roms/tools/Fire4Nix-R36H-Teste-Seguro.sh' --safe

Não é necessário chmod; usar sh funciona mesmo se o gerenciador de arquivos oferecer apenas View.

O script cria seu relatório somente no diretório temporário (/tmp por padrão); mostra imediatamente no terminal e imprime RELATORIO=... no final. Não executa WebKit, fsck, ldconfig, chmod, instalar bibliotecas, baixar arquivos, explorar arquivos pessoais, nem desligar ou alterar ROCKNIX.

Interpretação: test_result=BLOCKED_KNOWN_RUNTIME_ABI significa ELF inválido ou GST_CAT_DEFAULT indefinido no runtime encontrado. STATIC_CHECK_ONLY_NO_BROWSER_EXECUTED significa só inspeção estática, não sucesso gráfico. NO_WPE_FOUND significa runtime ausente dos caminhos comuns.

**Não executar teste gráfico no cartão exFAT corrompido antes de backup/reparo com SD desmontado**. O motor WPE 2.54.1 sem GStreamer ainda não foi compilado.

Além disso, o modo --screen do antigo Fire4Nix-Teste.sh foi corrigido para usar o diagnóstico --safe, evitando iniciar bibliotecas potencialmente corrompidas apenas para obter um resumo.
