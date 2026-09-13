# linux-library

Biblioteca interativa e idempotente para pós-instalação Linux. O ponto de entrada único detecta automaticamente sistemas baseados em APT, DNF ou Zypper e apresenta somente ações compatíveis.

## Estrutura

- [linux-setup.sh](linux-setup.sh) — instalações e configurações do sistema.
- [flatpak-apps.md](flatpak-apps.md) — catálogo editável de aplicativos Flatpak.
- `deb/` — pacotes locais para sistemas APT.
- `rpm/` — pacotes locais para sistemas DNF ou Zypper.
- [current-config](current-config/) — inventário dos hosts em uso e histórico técnico.

As pastas `deb/` e `rpm/` são criadas pelo script quando necessário. Seus pacotes são ignorados pelo Git; apenas os arquivos `.gitkeep` que preservam as pastas são versionados.

## Configuração atual

- [current-config/casa-lenovo.md](current-config/casa-lenovo.md) — Lenovo IdeaPad 1 com Debian 13 (Trixie)
- [current-config/trabalho-acer.md](current-config/trabalho-acer.md) — Acer Nitro com Zorin OS 18.1, usado como máquina de trabalho profissional e gestão de produtos

## Compatibilidade

| Família | Distribuições cobertas | Pacotes locais |
|---|---|---|
| APT | Debian, Ubuntu, Linux Mint e Zorin OS | `.deb` |
| DNF | Fedora e derivados | `.rpm` |
| Zypper | openSUSE e derivados | `.rpm` |

Outras famílias encerram a execução antes de qualquer alteração.

As configurações de serviços requerem `systemd`. O script usa Bash 4.3 ou mais recente por depender de arrays associativos e referências de variáveis.

## Menu

1. **Configurações**
   - Samba guest share
   - Servidor FTP
   - Cliente e servidor NFS
   - Transmission daemon e Web UI
   - Portas do Plex
   - Swapfile e zram
   - Flameshot com integração Wayland
   - Boot com splash em sistemas APT
2. **Instalações Flatpak**
   - Checklist carregado de [flatpak-apps.md](flatpak-apps.md).
   - Itens já instalados aparecem com `[i]` e não são reinstalados.
3. **Pacotes locais**
   - Em sistemas APT, apresenta os arquivos da pasta `deb/`.
   - Em sistemas DNF ou Zypper, apresenta os arquivos da pasta `rpm/`.
   - Formatos incompatíveis e arquivos inválidos são ignorados.
   - A ferramenta nativa resolve as dependências disponíveis nos repositórios.
4. **Sair**

Nos checklists, informe um ou mais números para alternar a seleção. Use `a` para selecionar todos, `n` para limpar, `c` para continuar e `q` para cancelar.

## Como usar

O script deve ser iniciado como usuário normal. Ele solicita `sudo` somente quando uma ação precisa alterar o sistema.

```bash
./linux-setup.sh
```

Para revisar comandos e navegar nos menus sem aplicar alterações:

```bash
./linux-setup.sh --dry-run
```

O Flatpak é configurado no escopo do sistema. Metadados dos repositórios são atualizados no máximo uma vez por execução.

### Boot com splash

Em sistemas APT, o menu **Configurações > Boot com splash** mostra o estado do GRUB, do boot atual, do Plymouth, do tema, do driver KMS e do initramfs. A opção pode ativar ou desativar o parâmetro `splash` para o próximo boot.

Se o Plymouth não estiver instalado durante a ativação, a ferramenta pede confirmação antes de instalar o pacote. A desativação remove somente o parâmetro `splash`: preserva `quiet`, os demais argumentos do kernel, temas e pacotes instalados.

A configuração é mantida em `/etc/default/grub.d/99-linux-setup-splash.cfg`; o `/boot/grub/grub.cfg` é regenerado somente quando o estado muda. Reinicie o sistema para observar o resultado.

Para instalar pacotes locais, coloque os arquivos na pasta correspondente antes de abrir a opção 3:

```text
deb/aplicativo.deb
rpm/aplicativo.rpm
```

Esses arquivos permanecem somente na máquina local e não aparecem no Git.

## Catálogo Flatpak

O catálogo precisa permanecer na mesma pasta de `linux-setup.sh`. Para adicionar, remover ou renomear uma opção, edite a tabela em [flatpak-apps.md](flatpak-apps.md). Cada linha precisa manter este formato:

```markdown
| `org.example.Application` | Nome exibido | Descrição curta |
```

O script ignora o cabeçalho da tabela, valida o formato dos IDs e interrompe a execução se encontrar IDs duplicados ou um catálogo vazio.

## Idempotência e segurança

- Pacotes e Flatpaks já instalados são detectados antes da instalação.
- Arquivos gerenciados só são substituídos quando o conteúdo muda.
- O script cria um backup `.linux-setup.bak` antes da primeira alteração de cada configuração existente.
- Entradas de NFS e swap não são duplicadas no `/etc/fstab`.
- Dispositivos zram ativos nunca são desativados ou recriados durante a execução.
- Senhas FTP não são armazenadas pelo script.

Samba guest, FTP, NFS e o RPC do Transmission preservam os padrões permissivos da biblioteca anterior. Use essas opções somente em uma rede doméstica confiável e leia o aviso exibido antes da confirmação.

Signal está disponível via Flatpak. Instalação nativa do Signal e drivers NVIDIA/RPM Fusion não fazem parte do script unificado.

## Sistemas registrados

- [x] Zorin OS Pro
- [x] Fedora
- [x] Debian 13 / Trixie
- [x] Ubuntu
- [x] OpenSUSE Leap 16.0
