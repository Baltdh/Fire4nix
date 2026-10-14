# Fire4Nix — WPE Core experimental para ROCKNIX

O pacote `Fire4Nix-ROCKNIX-ARM64-WPE-CORE-EXPERIMENTAL.zip` é um **experimento de compatibilidade**, não um navegador pronto nem um lançamento final.

## O que contém

- Inicializador AArch64 do Fire4Nix, scripts para a pasta `Tools` e diagnóstico
- `libWPEWebKit-2.0.so` da mesma compilação Debian ARM64
- `WPEWebProcess`, `WPENetworkProcess` e `WPEGPUProcess`
- `runtime/aarch64/SHA256SUMS` para validar o runtime antes de modificar `LD_LIBRARY_PATH`
- `WPE-ABI-REQUIREMENTS.json` com versões exigidas de GLIBC, GLIBCXX e CXXABI
- `WPE-CORE-SYSTEM-DEPENDENCIES.json`, listando os nomes das bibliotecas exigidas diretamente pelos cinco ELF e que **não** estão presentes no WPE Core. Dependências indiretas e módulos carregados dinamicamente não estão incluídos nessa lista.
- `WPE-CORE-NEEDED.txt`, lista equivalente de nomes SONAME, um por linha, que o `Diagnostico.sh` consegue consultar **sem Python ou jq**. O diagnóstico verifica locais comuns e `ldconfig`; uma biblioteca não encontrada pode existir em outro caminho, e uma encontrada ainda pode ter ABI incompatível.

**Não inclui** todas as bibliotecas transitivas e módulos gráficos/multimídia. Não substitui `libc`, `glibc` ou loaders do ROCKNIX e não concede `sudo`. Pode não abrir no R36H mesmo passando nos testes do GitHub.

## Teste no aparelho

1. No GitHub Actions, escolha o artefato **Fire4Nix-ROCKNIX-ARM64-WPE-Core-INCOMPLETE-EXPERIMENTAL**, se disponível e se o relatório de diagnóstico estiver aprovado.
2. Extraia o ZIP. Copie **o conteúdo da pasta extraída** para a pasta `Tools` do ROCKNIX, para que `Start-Fire4Nix.sh`, `Diagnostico.sh` e a pasta `Fire4Nix` fiquem lado a lado.
3. Execute primeiro `Diagnostico.sh` e verifique `/storage/fire4nix-wpe-diagnostic.log`. Se aparecer `INCOMPATIBLE` ou `not found`, **não instale bibliotecas do Debian no sistema** para contornar o aviso.
4. Somente se a verificação for compatível, teste `Start-Fire4Nix.sh`. Se ele fechar, consulte os logs do Fire4Nix e envie o relatório de diagnóstico. Procure especialmente os avisos `INCOMPATIBLE` (versões de GLIBC/GLIBCXX/CXXABI) e `NOT FOUND in common paths` (SONAME ainda não localizado; não comprova ausência absoluta).

O inicializador ativa o runtime apenas se os três processos e a biblioteca WPE forem ELF64 ARM64, seus caminhos permanecerem dentro da pasta do aplicativo, os hashes estiverem corretos e as versões conhecidamente incompatíveis de `GLIBC`, `GLIBCXX` ou `CXXABI` forem rejeitadas. Ele não desativa o sandbox.

O diagnóstico também verifica se há `bwrap` e tenta criar um namespace com um comando sem efeito, limitado a cinco segundos quando `timeout` estiver disponível. O resultado `PASS` não comprova o sandbox completo do WebKit; `FAIL` e `UNAVAILABLE` apontam uma possível causa de falha na abertura. A ausência de `readelf`, `ldconfig` ou alguma biblioteca em locais comuns produz um aviso, não uma conclusão definitiva.

## Critérios técnicos restantes

1. Provar as dependências reais e versões GLIBC/GLIBCXX/CXXABI presentes no ROCKNIX instalado no R36H.
2. Validar a criação da janela Wayland na sessão do dispositivo (640×480) e a entrada pelos controles.
3. Validar navegação HTML/HTTPS e processos WPE com sandbox ativo no ROCKNIX.
4. Medir memória, travamentos e encerramento após uso prolongado.

**Resultados de Debian ARM64, Weston virtual e testes sem sandbox são evidências parciais, não equivalem à validação no R36H.**
