# WPEPlatform: descoberta confiável dos alvos Ninja

## Continuidade conferida em 20/10/2026

- PRs #35–#38 acrescentam preflight SDK/compilador, teste seguro, guarda ELF,
  verificação CMake media-free e receitas de quatro dependências ROCKNIX.
- A conversa posterior confirma resgate ELF AArch64 no ext4 interno. O runtime
  antigo ainda depende de nove bibliotecas GStreamer e falha em GST_CAT_DEFAULT.
  Não repetir a auditoria antiga de lost+found nem gravar no exFAT externo.
- Actions 39510128192 passou na compilação das quatro dependências e configuração
  CMake em Ubuntu ARM64. Isso não equivale a um SDK ROCKNIX nem teste físico.
- Actions 39510695762 já passou nessas etapas e iniciou WPEPlatform; resultado
  final ainda pendente ao registrar este documento.
- O túnel temporário conectou via QUIC e foi encerrado pelo usuário. O navegador
  remoto recebeu bloqueio antes da autenticação; não houve leitura remota.

## Correção

Com `set -o pipefail`, `ninja -t targets all | grep -q` pode falhar quando grep
encontra o alvo e fecha o pipe enquanto Ninja ainda escreve uma lista grande.
Agora a saída completa é registrada uma vez em `wpeplatform-ninja-targets.txt`,
o código de saída de Ninja é validado e os três alvos exatos são procurados no
arquivo. A lista também fica disponível nos diagnósticos do Actions.

Regressão usa lista de 50 mil entradas: alvos presentes chegam ao limite da
compilação; alvo ausente (mesmo com nome semelhante) e falha do produtor bloqueiam.
O teste não compila nem executa WebKit e não fabrica evidência de renderização.

## Limites

Objetos WPEPlatform não são libWPEWebKit ligada nem navegador funcional. Ainda
faltam SDK/sysroot ROCKNIX compatível, motor completo sem GStreamer, auditoria
das bibliotecas ligadas e teste offline Wayland 640×480 no R36H. Não instalar
artefatos Ubuntu no console e não substituir bibliotecas do firmware.
