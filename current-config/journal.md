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

## 🏠 4. O Porto Seguro: do openSUSE Leap ao Debian no Lenovo
Enquanto o trabalho exige experimentação, o **laptop de casa (Lenovo IdeaPad 1)** permanece como ambiente estável e enxuto. Depois de uma etapa com o **openSUSE Leap 16.0**, a máquina passou a rodar **Debian GNU/Linux 13 (Trixie)** com GNOME e Wayland, mantendo o foco em previsibilidade, simplicidade e baixo ruído operacional.

## 🎨 5. Refinamento de Interface: Minimalismo e estabilidade
A experiência com ambientes mais pesados e visuais excessivos levou a uma mudança de foco para **minimalismo funcional** e estabilidade de uso diário.
*   **Estética e produtividade:** a preferência passou a priorizar clareza visual, baixo consumo de atenção e ausência de camadas desnecessárias na interface.
*   **Configuração de fontes e desktop:** a regra passou a ser manter a aparência leve e confiável, com ajustes concentrados na produtividade e não em estética artificial.

## 🚀 6. Decisão Atual: Debian para casa e Zorin OS para trabalho
A configuração doméstica atual ficou no **Debian 13 (Trixie)**, enquanto o Acer Nitro de trabalho roda **Zorin OS 18.1** e continua sendo usado como laboratório de testes e experimentação. Essa divisão deixa a máquina de casa estável e de manutenção simples, e o Acer como palco para validar drivers, múltiplos monitores e novos fluxos de trabalho.
*   **Por que Debian?** Oferece uma base estável, manutenção direta e ampla compatibilidade com os scripts usados no ambiente doméstico.
*   **Por que manter o Acer como laboratório?** O hardware do Nitro continua sendo a plataforma ideal para validar Fedora, GNOME e fluxos mais modernos de drivers e multi-monitor.

---

**Estado Atual do Hardware:**
*   **Casa:** Consulte: current-config/casa-lenovo.md
*   **Trabalho:** Consulte: current-config/trabalho-acer.md

*Este memorial documenta 25 anos de aprendizado, transformando cada erro de driver ou sistema de arquivos em um script de automação para o futuro.*.