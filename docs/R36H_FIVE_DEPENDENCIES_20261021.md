# Cinco dependências no mesmo stage ROCKNIX — 21/10/2026

Esta etapa estende a integração da PR #60 com a libffi estática PIC da PR #62.

| Biblioteca | Versão | Forma usada no teste |
|---|---|---|
| zlib | 1.3.1 | Compartilhada |
| SQLite | 3.50.2 | Compartilhada |
| libtasn1 | 4.21.0 | Compartilhada |
| libpng | 1.6.40 | Compartilhada, receita efetiva ROCKNIX |
| libffi | 3.5.1 | Estática PIC |

## Verificação

O workflow fixa os IDs das execuções produtoras e recompõe um DESTDIR privado. O script reutiliza as verificações da integração anterior, acrescenta libffi com rejeição de colisões e liga `libfive-consumer.so` ARM64 com `-z defs`.

Verifica quatro SONAMEs dinâmicos, definições de `ffi_call` e `ffi_prep_cif` no consumidor, e referências à libffi.a privada no mapa do linker. Impede TEXTREL, libffi dinâmica e dependências diretas GStreamer no consumidor. Confere requisitos GLIBC <= 2.41. Grava hashes atualizados do stage com cinco bibliotecas e preserva o código C/consumidor para auditoria.

Execução inicial 39678639462 recusou corretamente uma colisão em `usr/share/info/dir`, índice de documentação gerado separadamente por pacote. A importação de libffi agora se limita a `usr/lib` e `usr/include`; continua recusando bibliotecas/cabeçalhos conflitantes. Teste local com fixtures confirmou ambos os comportamentos. Nova execução: https://github.com/Baltdh/Fire4nix/actions/runs/39678877231 . Confirmar o resultado em Actions e em `five-acceptance.txt`.

## Próxima etapa concreta para GLib

A receita GLib 2.85.1, no commit ROCKNIX `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`, requer também pcre2 e util-linux no alvo, além de ferramentas host. A receita pcre2 desse mesmo commit fixa 10.45, hash `21547f3516120c75597e5b30a992e27a592a31950b5140e7b8bfde3f192033c4`, build estático PIC, variantes 8/16 e JIT. Essa dependência não está incluída nesta integração; precisa de build próprio e validação antes de GLib.

## Limites

O consumidor é ligado, nunca executado. Chamadas C e comparações escritas no consumidor não são testes funcionais executados. Cinco bibliotecas integradas não significam sysroot WPE completo, GLib/WebKit compilados ou navegador instalável. Ainda faltam bibliotecas, build completo sem GStreamer e teste físico de HTML/Wayland/Mali/controles no R36H.
