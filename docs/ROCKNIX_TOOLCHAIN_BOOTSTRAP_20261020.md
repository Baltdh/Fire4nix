# Construção real do toolchain antes do teste no R36H

WPEPlatform já compilou 54 objetos AArch64 no Actions 39510695762 (32 core,
19 Wayland, 3 headless). Esse build usou Ubuntu, não o sysroot ROCKNIX.

O novo workflow usa o commit oficial da release 20260801:
`3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`. Confere a receita efetiva do
projeto ROCKNIX (glibc 2.41, GCC 15.2.0) e executa `scripts/build toolchain`
com PROJECT=ROCKNIX DEVICE=RK3326 ARCH=aarch64, sem gerar imagem de firmware.
As ferramentas Ubuntu são ferramentas do host; compilador e libc alvo vêm
das receitas ROCKNIX. A release é candidata compatível com a glibc observada;
isso não comprova equivalência de todas as bibliotecas do firmware instalado.

Após o build, um arquivo CMake aponta explicitamente ao compilador e sysroot
produzidos. O verificador existente compila e liga programas C/C++ pequenos,
inspeciona AArch64 e requisitos GLIBC, sem executar os programas alvo.

Limite do job: 180 minutos. Diagnósticos são guardados mesmo na falha. Somente
após sucesso é publicado um checkpoint do toolchain para o host, com caminhos
absolutos do runner; não é relocatável automaticamente nem instalável no R36H.
O upload é checkpoint, não cache automático entre builds. Não publicar sucesso
de toolchain, WebKit ou teste físico antes dos respectivos resultados.

Ainda pendente após o toolchain: compilar as dependências com as receitas do
overlay, obter sysroot completo de desenvolvimento, compilar e ligar WebKit
sem GStreamer, auditar ABI e empacotar em pasta separada no ext4 interno.
O teste físico será a página offline 640x480; preservar /usr/lib e SD externo.
