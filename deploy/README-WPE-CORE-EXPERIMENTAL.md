# Fire4Nix — WPE Core experimental para ROCKNIX

O pacote `Fire4Nix-ROCKNIX-ARM64-WPE-CORE-EXPERIMENTAL.zip` é um **experimento de compatibilidade**, não um navegador pronto nem um lançamento final.

## O que contém

- Inicializador AArch64 do Fire4Nix, scripts para a pasta `Tools` e diagnóstico
- `libWPEWebKit-2.0.so` da mesma compilação Debian ARM64
- `WPEWebProcess`, `WPENetworkProcess` e `WPEGPUProcess`
- `runtime/aarch64/SHA256SUMS` para validar o runtime antes de modificar `LD_LIBRARY_PATH`
- `WPE-ABI-REQUIREMENTS.json` com versões exigidas de GLIBC, GLIBCXX e CXXABI
- `WPE-CORE-SYSTEM-DEPENDENCIES.json`, listando os nomes das bibliotecas exigidas diretamente pelos cinco ELF e que **não** estão presentes no WPE Core. Dependências indiretas e módulos carregados dinamicamente não estão incluídos nessa lista.
- `WPE-CORE-NEEDED.txt`, lista de dependências ELF **diretas**, um SONAME por linha, legível sem Python ou jq.
- `WPE-CORE-ALL-NEEDED.txt` e `WPE-CORE-TRANSITIVE-NEEDED.txt`, listas produzidas no Debian ARM64 a partir da resolução `ldd` das cinco partes do WPE. A primeira combina as dependências diretas e indiretas que permanecem externas ao pacote; a segunda contém apenas dependências indiretas.
- `WPE-CORE-DEPENDENCY-CLOSURE.json`, relatório que registra as origens das bibliotecas no **ambiente Debian de compilação**. Esses caminhos não são caminhos recomendados para instalação no ROCKNIX.

O `Diagnostico.sh` prefere `WPE-CORE-ALL-NEEDED.txt` quando presente, verifica locais comuns e a saída de `ldconfig`, e registra o que não encontrou. Um SONAME não encontrado pode existir em outro caminho; um SONAME encontrado ainda pode ser incompatível. **A ausência de arquivos `dlopen`, módulos GIO/TLS, multimídia e drivers gráficos nesse relatório não significa que eles sejam dispensáveis.**

**Não inclui** todas as bibliotecas transitivas e módulos gráficos/multimídia. Não substitui `libc`, `glibc` ou loaders do ROCKNIX e não concede `sudo`. Pode não abrir no R36H mesmo passando nos testes do GitHub.

## Teste no aparelho

1. No GitHub Actions, escolha o artefato **Fire4Nix-ROCKNIX-ARM64-WPE-Core-INCOMPLETE-EXPERIMENTAL**, se disponível e se o relatório de diagnóstico estiver aprovado.
2. Extraia o ZIP. Copie **o conteúdo da pasta extraída** para a pasta `Tools` do ROCKNIX, para que `Start-Fire4Nix.sh`, `Diagnostico.sh` e a pasta `Fire4Nix` fiquem lado a lado.
3. Execute primeiro `Diagnostico.sh` e verifique `/storage/fire4nix-wpe-diagnostic.log`. Se aparecer `INCOMPATIBLE` ou `not found`, **não instale bibliotecas do Debian no sistema** para contornar o aviso.
4. Somente se a verificação for compatível, teste `Start-Fire4Nix.sh`. Se ele fechar, consulte os logs do Fire4Nix e envie o relatório de diagnóstico. Procure especialmente os avisos `INCOMPATIBLE` (versões de GLIBC/GLIBCXX/CXXABI) e `NOT FOUND in common paths` (SONAME ainda não localizado; não comprova ausência absoluta).

O inicializador ativa o runtime apenas se os três processos e a biblioteca WPE forem ELF64 ARM64, seus caminhos permanecerem dentro da pasta do aplicativo, os hashes estiverem corretos e as versões conhecidamente incompatíveis de `GLIBC`, `GLIBCXX` ou `CXXABI` forem rejeitadas. Ele não desativa o sandbox.

A auditoria de 14/10/2026 identificou **131 SONAMEs** na cadeia de dependências do WPE compilado em Debian ARM64. Esse número é específico daquela compilação e **não demonstra que as 131 bibliotecas estejam ausentes** do ROCKNIX. Recompilações podem produzir listas diferentes. O arquivo de fechamento de dependências permite comparar o conjunto real do console, mas não substitui o teste em hardware.

O diagnóstico também verifica se há `bwrap` e tenta criar um namespace com um comando sem efeito, limitado a cinco segundos quando `timeout` estiver disponível. O resultado `PASS` não comprova o sandbox completo do WebKit; `FAIL` e `UNAVAILABLE` apontam uma possível causa de falha na abertura. A ausência de `readelf`, `ldconfig` ou alguma biblioteca em locais comuns produz um aviso, não uma conclusão definitiva.

## Critérios técnicos restantes

1. Provar as dependências reais e versões GLIBC/GLIBCXX/CXXABI presentes no ROCKNIX instalado no R36H.
2. Validar a criação da janela Wayland na sessão do dispositivo (640×480) e a entrada pelos controles.
3. Validar navegação HTML/HTTPS e processos WPE com sandbox ativo no ROCKNIX.
4. Medir memória, travamentos e encerramento após uso prolongado.

**Resultados de Debian ARM64, Weston virtual e testes sem sandbox são evidências parciais, não equivalem à validação no R36H.**
