# WPE 2.54.1 ROCKNIX: HarfBuzz detectado, componente ICU obrigatório ausente

**Diagnóstico real:** [Actions 39690932990 — FAIL corretamente sinalizado](https://github.com/Baltdh/Fire4nix/actions/runs/39690932990), executado contra o GCC ROCKNIX RK3326 AArch64 e GLIBC 2.41. O workflow deixou de classificar incorretamente o erro do WebKit como sucesso.

## Evidência do upstream WPE 2.54.1

O arquivo **oficial** `Source/cmake/OptionsWPE.cmake` da versão `wpewebkit-2.54.1` contém estas linhas adjacentes:

```cmake
find_package(GLib 2.70.0 REQUIRED COMPONENTS GioUnix Thread Module)
find_package(HarfBuzz 2.7.4 REQUIRED COMPONENTS ICU)
find_package(ICU 70.1 REQUIRED COMPONENTS data i18n uc)
```

Fonte original consultada: [WebKit tag wpewebkit-2.54.1 / Source/cmake/OptionsWPE.cmake](https://github.com/WebKit/WebKit/blob/wpewebkit-2.54.1/Source/cmake/OptionsWPE.cmake).

O `Source/cmake/FindHarfBuzz.cmake` dessa mesma versão verifica `HarfBuzz_FIND_REQUIRED_ICU` e, se não encontrar `libharfbuzz-icu`, define `_HarfBuzz_REQUIRED_LIBS_FOUND=OFF` mesmo com **`libharfbuzz.so.0` e a versão da biblioteca principal reconhecidos**.

Fonte: [WebKit tag wpewebkit-2.54.1 / Source/cmake/FindHarfBuzz.cmake](https://github.com/WebKit/WebKit/blob/wpewebkit-2.54.1/Source/cmake/FindHarfBuzz.cmake).

## Falha comprovada na execução

```text
TARGET_PC_harfbuzz=11.2.1
CMake Error at FindPackageHandleStandardArgs.cmake:233:
  Could NOT find HarfBuzz (missing: _HarfBuzz_REQUIRED_LIBS_FOUND)
  (found suitable version "11.2.1", minimum required is "2.7.4")
Source/cmake/FindHarfBuzz.cmake:159
WPE_CMAKE_EXIT_CODE=1
HARFBUZZ_FIRST_BLOCKER_CLEARED=NO
```

O teste da PR #79 compilou o HarfBuzz **sem ICU**, como prescreve o pacote geral ROCKNIX 20260801 (`-Dicu=disabled`). Portanto a biblioteca principal está correta, mas **essa variante é insuficiente para o WPE 2.54.1**, que exige o componente ICU. Não há fundamento em reduzir requisitos do WPE ou misturar bibliotecas Ubuntu; o build deve preparar `harfbuzz-icu.pc`, `libharfbuzz-icu.so.0` e a cadeia de bibliotecas ICU de destino.

A primeira execução após HarfBuzz, [39690478876](https://github.com/Baltdh/Fire4nix/actions/runs/39690478876), incorretamente marcou `HARFBUZZ_FIRST_BLOCKER_CLEARED=YES` porque procurava apenas erros originados diretamente em `FindHarfBuzz.cmake`. A PR #81 corrigiu o predicado para rejeitar `Could NOT find HarfBuzz` e `_HarfBuzz_REQUIRED_LIBS_FOUND` mesmo quando a origem é `FindPackageHandleStandardArgs.cmake`. O [segundo run 39690932990](https://github.com/Baltdh/Fire4nix/actions/runs/39690932990) **falhou corretamente**, confirmando a classificação e a necessidade do componente.

## Próximas ações sem duplicidade

- O **outro agente** está preparando HarfBuzz 11.2.1 com ICU habilitado na [PR #80](https://github.com/Baltdh/Fire4nix/pull/80). O build upstream de ICU 74.1 já foi validado na [execução 39688837904](https://github.com/Baltdh/Fire4nix/actions/runs/39688837904). **A PR #80 ainda não passou no CI** no momento deste relatório.
- Na tentativa [39690390387](https://github.com/Baltdh/Fire4nix/actions/runs/39690390387), a biblioteca HarfBuzz com ICU **compilou**, mas o consumidor falhou no cabeçalho `unicode/uscript.h`, indicando caminho de headers alvo ICU ausente no compilador do consumidor. Esse dado foi comunicado ao agente da PR #80.
- Após `SUCCESS` documentado do estágio HarfBuzz+ICU, atualizar os artefatos fixados desta PR #81, unir a biblioteca `libharfbuzz-icu.so.0` e as `libicu*` ao stage seguro, passar ao CMake as localizações reais e reexecutar o configure para identificar **o primeiro bloqueio após HarfBuzz**.

## Restrições

Nenhum código AArch64 foi executado no R36H. O WebKit **não foi compilado nem configurado por completo**, não há HTML gráfico ou HTTPS validado, e nenhum firmware, cartão SD ou `/usr/lib` do console foi modificado. Um job diagnóstico bem-sucedido não implica compilação bem-sucedida; o critério é `WPE_CMAKE_EXIT_CODE=0` com media cache gate comprovado.
