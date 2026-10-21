# Fire4Nix — bloqueio estático de ABI/DT_NEEDED do WPE para ROCKNIX

Este teste de empacotamento é **somente leitura**: lê ELF com `readelf` e **nunca**
executa um programa compilado para o console. Ele também **não** consulta as
bibliotecas do Linux hospedeiro (`/usr/lib`, `ldd` ou `ldconfig`).

## Contexto físico

Os primeiros relatórios R36H mostraram `invalid ELF header` em
`libWPEWebKit-2.0.so.1`. O runtime resgatado posteriormente passou pela
inspeção ELF, mas continha nove dependências GStreamer, com erro
`GST_CAT_DEFAULT` em `libgstvideo`. Isso impede tratar o backup como navegador
funcional. A porta inicial usa WPE WebKit 2.54.1, `USE_GSTREAMER=OFF`, para
ROCKNIX RK3326 AArch64, com GLIBC máxima de 2.41.

## Uso **no host de compilação**, após existir um SDK e o DESTDIR real

```sh
python3 rocknix-integration/audit-wpe-target-elf-closure.py \
  --runtime /caminho/fire4nix-runtime \
  --sysroot /caminho/rocknix-rk3326-toolchain/sysroot \
  --glibc-max 2.41 --strict
```

`--inspect` gera um relatório completo mesmo se encontrar bloqueios; `--strict`
retorna código 6 diante de qualquer um deles. São verificados arquivos ELF64
AArch64, versões GLIBC requeridas, `DT_NEEDED` recursivo no runtime/sysroot,
`libgst*` proibida, símbolo indefinido `GST_CAT_DEFAULT`, links simbólicos e
`RUNPATH/RPATH` sem fuga para bibliotecas da máquina hospedeira. Um subprocesso
pode usar `$ORIGIN/../../lib` somente se a resolução permanecer dentro do
runtime isolado.

O `sysroot` precisa conter bibliotecas **do próprio ROCKNIX**, e não de Ubuntu
ARM64. `CLOSURE_STATUS=PASS_STATIC_TARGET_ELF_AUDIT_ONLY` significa apenas que
a cadeia ELF declarada foi encontrada e passou nas condições verificadas.
Dependências carregadas dinamicamente por `dlopen`, módulos GIO/TLS,
certificados CA, drivers gráficos, uso de RAM, sandbox e a execução do WPE na
tela do console ainda requerem validação específica.

`native/tests/test_wpe_target_elf_closure.sh` fabrica ELF64 AArch64 com
Clang/LLD em pastas temporárias; passa/cai intencionalmente em casos de
biblioteca ausente, ELF ilegível, RUNPATH inseguro e GStreamer. **Não é um
teste de navegador real.** Não mexer no firmware nem em `/usr/lib` do R36H.
