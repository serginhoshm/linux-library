# Odisseia de um Distro-Hopper Veterano: Diário de Bordo (1999 - 2026)

Este documento detalha a longa trajetória técnica, os percalços e as decisões estratégicas tomadas na busca pelo ambiente Linux ideal, equilibrando a agilidade de um **Product Manager** com a estabilidade de um sistema profissional.

---

## 📜 1. O Legado: Das Origens ao Pragmatismo
A jornada começou em **1999 com o Conectiva Linux**, moldando uma visão de que o sistema operacional deve ser uma ferramenta de trabalho invisível e veloz, e não um obstáculo. Após décadas de experiência, a filosofia consolidada é a da **praticidade e velocidade**, utilizando o Linux para gerenciar fluxos complexos como WebApps isolados, sincronismo de arquivos e chamadas de vídeo.

## 🧪 2. O Caminho das Pedras: Distros que não passaram no teste
Para chegar ao setup atual, foi necessário filtrar diversas distribuições que apresentaram falhas críticas em hardware específico (especialmente **Nvidia e Multi-monitores**):

*   **MX Linux:** Descartado devido a **congelamentos insolúveis** ao utilizar drivers Nvidia em uma configuração de dois monitores.
*   **Fedora Kinoite / Silverblue:** Embora promissores pelo conceito atômico, apresentaram instabilidade severa e dificuldades "absurdas" para configurar a Nvidia com múltiplos monitores de forma estável.
*   **Vanilla OS:** As ferramentas proprietárias da distro, como `abroot` e `apx`, foram consideradas apenas "nomes bonitos" para tecnologias que falhavam na prática, inviabilizando a instalação simples de apps essenciais.
*   **Garuda Linux:** Classificada como "horrível", apresentando problemas graves desde o processo de boot e sendo criticada por parecer um "projeto de uma única pessoa".
*   **Deepin & Manjaro:** O primeiro foi rejeitado por falta de confiança na **segurança dos dados** (potencial de vazamento), enquanto o segundo provou ser excessivamente complicado para o uso pragmático do dia a dia.

## 🛠️ 3. A Era dos Sistemas Atômicos e o Acer Nitro
A busca por fluidez levou ao uso do **laptop de trabalho (Acer Nitro AN515-55)** como principal laboratório de testes.

*   **Bluefin (Fedora Silverblue):** Foi o sistema de entrada no mundo imutável, onde foi aperfeiçoado o guia de **WebApps isolados via Brave**.
*   **Bazzite 43 (GNOME 49.6):** Migração estratégica do Bluefin para o Bazzite em busca de um sistema ainda mais fluido para o hardware do Acer Nitro.

### 🚑 Percalços e Soluções Cirúrgicas
Nesta fase, problemas críticos foram resolvidos com engenharia de software manual:
1.  **Bug do Insync (Fedora 44):** Uma mudança na gestão de certificados SSL quebrou o Insync. A solução foi o **downgrade para o pacote do Fedora 43** e o uso do `dnf versionlock` para impedir atualizações que reintroduzissem o erro.
2.  **Codecs no Vivaldi (Flatpak):** Em sistemas imutáveis, a ausência de codecs H.264 foi resolvida através de **overrides de sistema de arquivos** e a criação de links simbólicos manuais para a biblioteca `libffmpeg.so`.

## 🏠 4. O Porto Seguro: Debian 13 (Trixie)
Enquanto o trabalho exigia experimentação, o **laptop de casa (Lenovo IdeaPad 1)** foi mantido como o baluarte da estabilidade, rodando **Debian 13 (Trixie)** com GNOME 48.7. A consistência do Debian permitiu o desenvolvimento de scripts de **rsync** para manter a `/home/` sincronizada entre os diferentes ambientes.

## 🎨 5. Refinamento de Interface: Cinnamon e Fontes
Recentemente, a experiência com o **Ubuntu Cinnamon 24.04.4** no trabalho trouxe novos aprendizados sobre personalização.
*   **Estética Apple vs. Catppuccin:** Embora tenha explorado o visual macOS (WhiteSur), a escolha final recaiu sobre o tema **Catppuccin** pela modernidade e legibilidade [Conversa Anterior, 36].
*   **Configuração de Fontes:** Implementação da **SF Mono** especificamente para o explorador de arquivos (**Nemo**) via customização de CSS em `~/.config/gtk-3.0/gtk.css`, mantendo a fonte do sistema separada da fonte do terminal [46, Conversa Anterior].

## 🚀 6. Decisão Atual: Fedora Workstation (Monolítico)
Após as frustrações com sistemas imutáveis ("engessados") e os Snaps forçados do Ubuntu, a decisão para o Acer Nitro em 2026 é o **Fedora Workstation tradicional** [Chat History].
*   **Por que Fedora?** Oferece o **GNOME Vanilla** puro (focado em busca espacial com a tecla Super), suporte Nvidia facilitado via RPM Fusion e a modernidade do **Wayland**, que resolve definitivamente os antigos problemas de congelamento de mouse em múltiplos monitores [32, Chat History].

---

**Estado Atual do Hardware:**
*   **Casa:** Consulte: current-config/casa-lenovo.md
*   **Trabalho:** Consulte: current-config/trabalho-acer.md

*Este memorial documenta 25 anos de aprendizado, transformando cada erro de driver ou sistema de arquivos em um script de automação para o futuro.*.