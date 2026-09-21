# Build no ROCKNIX

## Marco atual: WPE ARM64 real

O alvo prioritario agora e substituir o launcher de compatibilidade por um ELF ARM64 real ligado ao WPE WebKit do ambiente ROCKNIX.

Na raiz de `Fire4Nix/`:

```sh
make wpe-arm64
```

O build agora falha de forma explicita se:

- `pkg-config` ou o compilador C++ nao existirem;
- nenhum pacote WPE WebKit de desenvolvimento for encontrado;
- o compilador nao tiver alvo `aarch64/arm64`;
- o resultado nao for reconhecido por `file(1)` como ELF ARM64.

Quando aprovado, o executavel e copiado para:

```
Fire4Nix/bin/fire4nix-wpe-platform
```

Isso evita o erro antigo de tratar um script POSIX como se fosse o binario ARM64 final.

## Build/auditoria geral

1. Copie a pasta do projeto.
2. Execute os scripts de build disponiveis no ambiente ROCKNIX.
3. Guarde o log de build para diagnostico.
4. Se estiver testando a instalacao, rode `Install-Fire4Nix.sh`.
5. Antes do teste final, confirme Wayland, runtime e arquitetura do binario.

O build SDL/audit continua sendo util para validar logica no host, mas nao substitui o build WPE ARM64 nem o teste no R36H.

## Direct launch

Depois de copiar a pasta para ROCKNIX, `Fire4Nix.sh` pode ser usado para iniciar o fluxo do navegador sem instalar permanentemente.
