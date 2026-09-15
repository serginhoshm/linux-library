# linux-library

Biblioteca interativa e idempotente para pós-instalação Linux. O ponto de entrada único detecta automaticamente sistemas baseados em APT, DNF ou Zypper e apresenta somente ações compatíveis.

## Estrutura

- [linux-setup.sh](linux-setup.sh) — instalações e configurações do sistema.
- `apps/` — biblioteca editável, com um Markdown por aplicativo.
- `deb/` — pacotes locais para sistemas APT.
- `rpm/` — pacotes locais para sistemas DNF ou Zypper.
- `logs/` — registros locais de execução; `latest.log` aponta para o mais recente.
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
2. **Aplicativos**
   - **Preparar cache local** usa o checklist da biblioteca `apps/` e tenta baixar os formatos DEB e RPM disponíveis, independentemente da família do sistema atual.
   - Fontes externas compatíveis podem fornecer a família oposta. Pacotes disponíveis apenas no repositório configurado da distribuição atual são armazenados somente no formato dessa distribuição.
   - **Instalar aplicativos do cache** considera apenas o pacote compatível já presente em `deb/` ou `rpm/`; essa etapa não pesquisa nem baixa pacotes nativos.
   - Antes de percorrer os aplicativos selecionados, pergunta uma única vez se a ausência de pacote compatível deve usar Flathub ou resultar em falha.
   - Uma falha ao instalar um pacote do cache preserva o Flatpak existente e não é mascarada pelo fallback.
   - Após confirmar a instalação nativa, remove a cópia Flatpak nos escopos do sistema e do usuário sem apagar seus dados.
3. **Pacotes locais**
   - Em sistemas APT, apresenta os arquivos da pasta `deb/`.
   - Em sistemas DNF ou Zypper, apresenta os arquivos da pasta `rpm/`.
   - Formatos incompatíveis e arquivos inválidos são ignorados.
   - A ferramenta nativa resolve as dependências disponíveis nos repositórios.
4. **Gerenciar biblioteca**
   - Lista, adiciona, edita, remove e valida links de aplicativos.
5. **Sair**

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

O fallback Flatpak é configurado no escopo do sistema. Metadados dos repositórios são atualizados no máximo uma vez por execução.

Cada execução grava terminal, comandos e eventos em `logs/linux-setup-*.log`. Os arquivos têm permissão `0600`, não são versionados e podem ser consultados pelo atalho `logs/latest.log`. Para compartilhar um diagnóstico, preserve o arquivo completo, pois os eventos distinguem resolução, download, instalação, fallback e encerramento.

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

## Catálogo de aplicativos

Cada aplicativo vive em `apps/<chave>.md`. O arquivo contém texto Markdown legível e um bloco JSON validado com os pacotes, fontes de descoberta, links DEB/RPM resolvidos, versões, checksums e origem Flatpak. A manutenção pode ser feita pelo menu **Aplicativos > Gerenciar biblioteca** ou editando o arquivo e executando `python3 catalog-tool.py validate apps`.

```json
{
   "schema_version": 1,
   "key": "exemplo",
   "packages": {"apt": "exemplo", "dnf": "exemplo", "zypper": ""},
   "deb": {"discovery": {"type": "github", "source": "org/projeto"}},
   "rpm": {"discovery": {"type": "github", "source": "org/projeto"}},
   "flatpak": {"id": "org.example.App", "source_type": "remote"}
}
```

Use valores vazios quando uma família não tiver candidato. **Atualizar catálogo** consulta as fontes de descoberta e atualiza somente os links resolvidos de cada Markdown; **Preparar cache** é o único fluxo que baixa bytes.

Ao preparar o cache, o motor consulta o nome da família atual e aliases exatos nos metadados do APT, DNF ou Zypper. Também consulta a fonte externa separadamente para DEB e RPM; GitHub aceita `GITHUB_TOKEN` opcional para ampliar o limite da API. A ausência de um formato é registrada sem impedir que o outro seja armazenado.

Downloads externos usam HTTPS, timeout e tentativas limitadas. SHA-256 oficial é verificado quando publicado. Na família atual, nome e arquitetura são validados pelos metadados internos do pacote; na família oposta, o arquivo precisa ter a assinatura estrutural DEB/RPM e será validado integralmente quando instalado em uma distribuição compatível. Um pacote externo em cache só é reutilizado quando o checksum oficial atual o confirma. Sem checksum, uma nova cópia é baixada.

Antes da instalação, o script fotografa os arquivos de fontes e chaves da família. Depois, remove somente arquivos novos cujo nome ou conteúdo corresponda ao aplicativo, pacote ou host da origem, atualiza os metadados e preserva tudo que já existia. Uma transação interrompida é reconciliada na próxima execução.

## Idempotência e segurança

- Pacotes e Flatpaks já instalados são detectados antes da instalação.
- O Flatpak só é removido depois que a instalação nativa é confirmada; dados do aplicativo não são apagados.
- Falhas na remoção Flatpak são registradas como resultado parcial.
- Repositórios e chaves preexistentes nunca são removidos pela transação de aplicativos.
- Arquivos gerenciados só são substituídos quando o conteúdo muda.
- O script cria um backup `.linux-setup.bak` antes da primeira alteração de cada configuração existente.
- Entradas de NFS e swap não são duplicadas no `/etc/fstab`.
- Dispositivos zram ativos nunca são desativados ou recriados durante a execução.
- Senhas FTP não são armazenadas pelo script.

Samba guest, FTP, NFS e o RPC do Transmission preservam os padrões permissivos da biblioteca anterior. Use essas opções somente em uma rede doméstica confiável e leia o aviso exibido antes da confirmação.

Drivers NVIDIA e configuração do RPM Fusion não fazem parte do motor de aplicativos.

## Sistemas registrados

- [x] Zorin OS Pro
- [x] Fedora
- [x] Debian 13 / Trixie
- [x] Ubuntu
- [x] OpenSUSE Leap 16.0
