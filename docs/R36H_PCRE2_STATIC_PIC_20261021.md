# PCRE2 para GLib/WPE no ROCKNIX — 21/10/2026

A receita GLib 2.85.1 requer PCRE2 no alvo. A compilação desta etapa usa o mesmo toolchain ROCKNIX real da execução 39525819979, sem substituir bibliotecas do console.

## Fonte e configuração

- Upstream ROCKNIX fixado: `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.
- `packages/devel/pcre2/package.mk`: versão 10.45, SHA-256 `21547f3516120c75597e5b30a992e27a592a31950b5140e7b8bfde3f192033c4`.
- Bibliotecas estáticas PIC, variantes 8/16-bit, JIT habilitado; libedit/readline desabilitados conforme receita target.
- Adicionalmente desabilitados testes e pcre2grep, que não são necessários ao stage de desenvolvimento; variante 32-bit desabilitada.
- Não reproduz o pós-install do firmware: usa DESTDIR privado e não copia pcre2-config para o toolchain. Headers/pkg-config das bibliotecas são preservados.

## Critérios

Todos os membros dos arquivos estáticos precisam ser ELF64 AArch64 REL. Os arquivos pkg-config devem declarar versão 10.45. O cache CMake deve confirmar JIT e variantes 8/16.

Um consumidor compartilhado usa pcre2_compile e pcre2_jit_compile nas duas variantes e é ligado com `-z defs`. São exigidos os quatro símbolos definidos no resultado. Nenhuma dependência libpcre2 compartilhada ou TEXTREL é aceita; GLIBC máxima permitida é 2.41.

Execução inicial: https://github.com/Baltdh/Fire4nix/actions/runs/39679260246 . Conferir resultado em Actions e `result.txt` antes de afirmar aprovação.

## Limites

JIT compilado e ligado não significa execução de regex/JIT no R36H. O consumidor não é executado. PCRE2 permanece em stage separado, ainda precisa ser integrado às cinco dependências e depois à compilação GLib. Util-linux/libmount e ferramentas host do GLib também precisam ser resolvidos. WebKit completo, backend gráfico e testes físicos permanecem pendentes.
