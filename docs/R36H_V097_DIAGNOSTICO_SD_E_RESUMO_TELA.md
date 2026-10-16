# Fire4Nix 0.97 — Sonda WPE no cartão SD e resumo para fotografar

## Objetivo

Resolver um problema observado nos logs originais do R36H em 14/10/2026: o WebKit de aproximadamente 174 MB estava no cartão SD, mas o executável antigo informou `libWPEWebKit-2.0.so.1: cannot open shared object file` (127) em algumas execuções, enquanto em outras houve **segmentation fault** (139). Esses eventos são diferentes: o primeiro indica falha no carregador/biblioteca e o segundo significa que o processo já iniciou e foi encerrado por acesso inválido à memória. Os logs não provam uma causa única, nem confirmam se o WebKit instalado oferece WPEPlatform.

A versão 0.97 amplia `Diagnosticar-Fire4Nix.sh` para inspecionar primeiro o WebKit da pasta do navegador e depois locais já usados pelo ROCKNIX em **ambos os cartões**, sem precisar reinstalar o runtime para cada diagnóstico.

### Novo funcionamento

- Busca `runtime/lib/libWPEWebKit-2.0.so.1` na pasta instalada, no cartão interno, externo, nos diretórios `tools/Fire4Nix` e `ports/fire4nix-completo` e em `FIRE4NIX_ROMS` quando definido.
- Com runtime disponível, verifica os três processos (`WPEWebProcess`, `WPENetworkProcess`, `WPEGPUProcess`) na **mesma origem** e imprime caminho e tamanho da biblioteca.
- Se `ldd` existir, mostra apenas nomes de bibliotecas de sistema que aparecem como **not found**, sem extrair conteúdo de arquivos do usuário.
- Executa apenas `fire4nix-native-aarch64 --check-platform` com o `LD_LIBRARY_PATH` apontando para a biblioteca encontrada. Este teste nunca cria uma janela nem navega na internet.
- Registra a versão da glibc, a arquitetura, presença do socket Wayland, nó gráfico DRM, `gptokeyb`, `uinput` e os símbolos exportados WPEPlatform que o executável consegue encontrar.
- `FIRE4NIX_DIAGNOSTIC_RUNTIME=/caminho/runtime` seleciona explicitamente uma biblioteca em layout diferente do padrão, sem mudar a instalação original.
- Gera `/storage/Fire4Nix-Diagnostico-097.txt` quando `/storage` é gravável. Em outros locais utiliza a pasta de origem do script ou `FIRE4NIX_DIAGNOSTIC_OUT`.

### Resumo para foto — sem precisar copiar arquivos

Execute:

```sh
sh Diagnosticar-Fire4Nix.sh --screen
```

Além do relatório detalhado, as informações essenciais serão impressas no terminal em linhas curtas. Uma foto do texto com título **FIRE4NIX 0.97 / RESUMO PARA FOTO** pode ser usada como devolutiva mesmo se o gerenciador de arquivos não conseguir copiar logs para outro cartão.

### Interpretando os resultados

| Linha | Significado |
|---|---|
| `WPE_library=missing` | Não foi localizada uma biblioteca nos caminhos verificados |
| `WPE_library=present` | Biblioteca encontrada; isto **não** garante que a API é utilizável |
| `Nome=not_found` | Dependência dinâmica ausente, identificada por `ldd` |
| `WPEPlatform_preflight_exit=0` | Os símbolos necessários estão disponíveis para abrir o WPEView; **não** garante janela funcional |
| `WPEPlatform_preflight_exit=78` | ABI WPEPlatform esperada não está disponível; pode ser uma biblioteca legada |
| `WPEPlatform_preflight_exit=127` | Carregador ou símbolos essenciais não foram localizados |
| `WPEPlatform_preflight=skipped_runtime_missing_no_launcher` | Há um executável disponível, mas sem runtime nem script de preflight |
| `GRAPHICS_STATUS=NOT_VERIFIED_BY_PREFLIGHT` | A sonda não consegue confirmar a GPU Mali ou tela visível |

O relatório evita coletar senhas, MAC, endereços de rede, arquivos pessoais ou logs do Terminal R36. Não executa o navegador gráfico, altera drivers, instala pacotes ou desativa o sandbox.

## Cobertura de testes

O teste `native/tests/test_runtime_diagnostic.sh` cria um WebKit *mock* armazenado separadamente do pacote — equivalente ao cenário de bibliotecas em SD1 e executável em SD2 — e força saída `78`. Verifica que a sonda distingue presença do runtime, subprocessos, ABI legada e ausência da biblioteca; verifica também a saída `--screen` com linhas adequadas para foto.

A CI segue compilando o ELF AArch64 Cortex-A35 e executando os testes de instalação, gamepad simulado, rollback, WebKit mock, FAT/exFAT e verificação de JavaScript da homepage.

**Pendente:** ainda não temos o arquivo real `libWPEWebKit-2.0.so.1` do R36H para provar compatibilidade de versão nem execução da janela Mali/Wayland. O ZIP de 0.97 não contém esse runtime de 174 MB; usa os arquivos já instalados no SD.

## Etapa de validação recomendada

1. Instale a 0.97 extraindo o pacote e executando `sh Instalar-Fire4Nix-Uma-Vez.sh`.
2. Rode `sh Diagnosticar-Fire4Nix.sh --screen`, fotografe a tela de resumo e compartilhe.
3. Tente abrir Fire4Nix em Ports. Se não abrir, consulte `/storage/Fire4Nix-ultimo-resultado.txt` e compare com o diagnóstico 0.97.
