# R36H: bloqueios observados e candidato EGL padrão

Evidência fornecida pelo usuário no console real (23/10/2026):

- WPE 2.54.1 carrega, consulta versão/símbolos e retorna preflight 0.
- `mktemp` rejeita templates terminados em `XXXXXX.txt`/`XXXXXX.log`.
  Templates corrigidos terminam em XXXXXX; testes cobrem um mktemp estrito.
- WPE release ignora WEBKIT_EXEC_PATH e busca WPENetworkProcess em /usr/libexec.
  Um bind mount em namespace privado permitiu criar WebKitWebView e WPEView.
- O WebProcess encerra com `Could not create EGL display: no supported platform
  available`. Não houve confirmação de imagem na tela.
- Driver Mali g29p1; /dev/mali0 e /dev/dri/card0 presentes, sem renderD*.
- EGL_EXTENSIONS anuncia X11, GBM e Wayland; não anuncia
  EGL_MESA_platform_surfaceless.
- Com MALI_DEFAULT_DISPLAY=wayland e socket Wayland existente,
  eglGetDisplay(EGL_DEFAULT_DISPLAY) + eglInitialize retornam 1 e EGL_SUCCESS
  (0x3000), em duas execuções. Isso não comprova criação de contexto GLES,
  troca de buffers nem renderização do WebKit.

## Correção experimental

O patch atua somente na árvore extraída do arquivo oficial 2.54.1 já fixado
por SHA256. Valida todos os pontos de alteração antes de escrever e registra
hashes por arquivo. Habilita PlatformDisplayDefault no WPE e adiciona um
fallback após as tentativas normais, somente quando
FIRE4NIX_WPE_DEFAULT_EGL=1. O iniciador do pacote define essa variável e mantém
MALI_DEFAULT_DISPLAY=wayland. Não se habilita GBM sem render node confirmado.

A busca por WEBKIT_EXEC_PATH fica disponível em release, exige diretório
absoluto e mantém o comportamento padrão quando o executável não existe.
A busca de desenvolvimento junto ao executável permanece condicionada ao
DEVELOPER_MODE. Não é preciso modificar /usr nem o firmware.

Workflow dedicado: r36h-mali-default-egl-real.yml, branch
build/r36h-mali-default-egl-20261023. Recompila biblioteca e subprocessos;
prepara as cópias auditadas do SDK, fecha dependências e só publica o ZIP se
passarem os bloqueios estáticos. Fontes de teste e relatórios não devem ser
interpretados como comprovação de funcionamento gráfico no R36H.
