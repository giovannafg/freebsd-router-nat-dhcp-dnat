# Roteador físico: notebook com FreeBSD no HD externo

Não teremos PC no laboratório, e o enunciado proíbe ambiente virtualizado.
Por isso o roteador é um **notebook dando boot no FreeBSD instalado num HD
externo**. É uma máquina física rodando FreeBSD (não é VM). O sistema do
notebook não é tocado: sem o HD, ele volta a ser o que era.

Os testes no QEMU ([simulacao.md](simulacao.md)) continuam valendo como
ensaio. Este documento cobre o hardware real.

## Dois cenários

| | **Desenvolvimento** (agora) | **Apresentação** (no LDS) |
|---|---|---|
| WAN do roteador | Celular com **ancoragem USB** | **Cabo** da porta do notebook (ou 2º adaptador USB) até o switch/roteador do professor |
| Rede da WAN | A rede que o celular cria | `192.168.X.0/24`, gateway `192.168.X.1` |
| LAN do roteador | Adaptador USB-Ethernet → **cabo direto** → notebook Linux | Igual |
| DNS para a LAN | `1.1.1.1, 8.8.8.8` | `192.168.X.1` (se responder) ou `164.41.101.4, 164.41.101.11` |
| Máquina do lado WAN | Não existe | Notebook Windows ligado na rede do professor |
| Testes possíveis | DHCP, reserva fixa, log/leases, conectividade, NAT, bloqueio de ping | Todos, incluindo **DNAT** e **isolamento** |

## Topologia

Desenvolvimento:

```
celular ==USB (ancoragem)== [WAN] notebook FreeBSD [LAN: adaptador USB 172.16.0.1]
                                                        |
                                                   cabo direto
                                                        |
                                           notebook Linux 172.16.0.10
```

Apresentação:

```
roteador/switch do professor (192.168.X.1)
   |                      |
 cabo                   cabo
   |                      |
[WAN] notebook FreeBSD   notebook Windows (máquina WAN)
[LAN: adaptador USB 172.16.0.1]
   |
 cabo direto
   |
notebook Linux 172.16.0.10 (reserva DHCP, alvo do DNAT :8080)
```

> **Nunca ligue o cabo da LAN (adaptador USB) na rede do professor.** O
> servidor DHCP de vocês passaria a disputar com o dele e derrubaria a rede
> de todos os grupos.

## Material

- Notebook roteador + HD externo (ou SSD/pendrive de 8 GB ou mais)
- Pendrive com o instalador `FreeBSD-14.5-RELEASE-amd64-memstick.img`
- Adaptador USB-Ethernet (LAN). Se o notebook não tiver porta de rede, um
  **segundo adaptador** para a WAN na apresentação.
- Celular Android com ancoragem USB (iPhone também funciona com o driver
  `if_ipheth`, mas não foi testado)
- Cabos de rede: 1 para a LAN (desenvolvimento) e mais 2 para a apresentação
- Notebook Linux (cliente LAN) e notebook Windows (máquina WAN)

## 1. Preparar o notebook roteador (uma vez)

1. Entre na BIOS/UEFI (F2, F10, Del ou Esc ao ligar, conforme a marca).
2. **Desligue o Secure Boot.** O FreeBSD não dá boot com ele ligado.
3. Garanta que o boot por USB está habilitado. O menu de boot costuma abrir
   com F12, F9 ou Esc.

## 2. Instalar o FreeBSD no HD externo (uma vez)

1. Grave o `memstick.img` no pendrive (Rufus em **modo DD**, ou balenaEtcher).
2. Conecte o pendrive **e** o HD externo e dê boot pelo pendrive. Escolha
   **Install**.
3. Hostname: `roteador`.
4. Componentes: deixe só o obrigatório (`kernel` e `base`). Desmarque
   `lib32`, `ports`, `src` e `tests`.
5. Rede durante a instalação: pode pular. A rede é configurada depois.
6. Particionamento: **Auto (UFS)** → **Entire Disk** → **GPT**.
   **Escolha o HD externo.** Ele aparece como `da0`/`da1`. O disco interno
   do notebook aparece como `nda0`/`ada0`: **não o escolha**. Confira pelo
   tamanho antes de confirmar.
7. Defina a senha de root. Os serviços extras (sshd etc.) podem ficar
   desligados: tudo é feito pelo console.
8. Ao terminar, retire o pendrive e dê boot pelo HD externo.

## 3. Primeiro boot: internet, pacotes e repositório

Faça login como `root`. Para ter internet só agora, use o celular:

1. Ligue o celular no USB e ative **Ancoragem USB** (Android: Configurações →
   Rede → Ponto de acesso e ancoragem).
2. Carregue o driver e descubra a interface nova:

   ```sh
   kldload if_urndis      # Android; no iPhone: kldload if_ipheth
   ifconfig -l            # a interface nova do celular é um "ue"
   dhclient ue0           # troque ue0 pela interface do celular
   ```

3. Instale os pacotes e baixe o repositório (é público; não precisa de
   senha nem de token):

   ```sh
   pkg install -y git isc-dhcp44-server
   git clone https://github.com/giovannafg/freebsd-router-nat-dhcp-dnat.git /root/roteador
   cd /root/roteador
   ```

## 4. Preencher `config/router.conf` (só local)

```sh
cp config/router.conf.exemplo config/router.conf
ee config/router.conf
```

| Variável | Onde descobrir |
|---|---|
| `LAN_MAC` | No roteador, com o adaptador conectado: `ifconfig` → linha `ether` da interface `ue` que **não** é a do celular |
| `CLIENTE_MAC` | No notebook Linux: `ip link` → `link/ether` da placa **com fio** (`enp...`/`eth0`) |
| `CELULAR` | `android` (desenvolvimento) ou vazio (apresentação) |
| `DNS_SERVERS` | Ver a tabela de cenários acima |
| `WAN_IF` / `WAN_MAC` | Vazio no desenvolvimento. Na apresentação, a porta com fio (ex.: `re0`) |

> `config/router.conf` está no `.gitignore` e **não vai para o GitHub**. Não
> use `git add -f` nele. O repositório é público e só deve conter valores
> fictícios.

## 5. Aplicar e conferir

```sh
sh scripts/instalar.sh -n    # só valida: interfaces, pf.conf, dhcpd.conf
sh scripts/instalar.sh       # backup + aplica + reinicia os serviços
reboot                       # prova que tudo sobe sozinho
sh scripts/diagnostico.sh    # depois do boot
```

O script descobre o adaptador da LAN pelo MAC. Se a ordem de conexão trocar
`ue0`/`ue1`, basta rodar `sh scripts/instalar.sh` de novo. Para evitar
isso, siga sempre a mesma ordem: **adaptador da LAN conectado antes de ligar
o notebook; ancoragem do celular ativada depois do boot**.

Se algo falhar, o script para **antes** de alterar qualquer arquivo. Quando
ele aplica, guarda os arquivos anteriores em `/var/backups/roteador-<data>/`.

## 6. Notebook Linux (cliente da LAN)

- Ligue o cabo direto no adaptador USB do roteador.
- **Desligue o Wi-Fi.** Senão ele sai para a internet sem passar pelo roteador
  e os testes de NAT perdem o sentido.
- A conexão com fio deve estar em **Automático (DHCP)**.
- Instale o netcat, se não tiver (`sudo apt install netcat-openbsd`). Se
  houver firewall ativo: `sudo ufw allow 8080/tcp`.

Siga o [roteiro de testes](roteiro-apresentacao.md).

## O que muda no dia da apresentação

Faça **nesta ordem**, já no LDS:

1. **Desconecte o celular.** Ele não participa da apresentação.
2. **Ligue um cabo da porta de rede do notebook** (ou do 2º adaptador USB)
   **numa porta do switch/roteador do professor.** Essa é a WAN.
3. **Mantenha a LAN como está:** adaptador USB → cabo direto → notebook Linux.
4. **Edite `config/router.conf`:**

   ```sh
   CELULAR=""
   WAN_IF="re0"                # nome real da porta com fio (veja ifconfig -l)
   # ou: WAN_IF="" e WAN_MAC="<MAC do 2º adaptador>"
   DNS_SERVERS="192.168.X.1"   # se 'host unb.br 192.168.X.1' responder;
                               # senão "164.41.101.4, 164.41.101.11"
   WAN_CONFIG="DHCP"           # ou o IP fixo que o professor indicar
   ```

   `LAN_MAC` e `CLIENTE_MAC` **não mudam**: são o mesmo adaptador e o mesmo
   notebook Linux.
5. **Aplique:** `sh scripts/instalar.sh -n`, depois `sh scripts/instalar.sh`,
   depois `reboot`.
6. **Confira:** `sh scripts/diagnostico.sh interfaces`. A WAN deve ter IP em
   `192.168.X.0/24` e rota padrão via `192.168.X.1`. **Anote esse IP da WAN**:
   é o que o Windows usa no DNAT.
7. **Notebook Windows:** cabo na rede do professor, Wi-Fi desligado.
8. **Rode o [roteiro de testes](roteiro-apresentacao.md) completo**, incluindo
   DNAT e isolamento.

Ensaie esses passos uma vez antes do dia da apresentação, no próprio LDS.

## Problemas comuns

| Sintoma | O que fazer |
|---|---|
| Notebook não dá boot pelo HD | Secure Boot ligado, ou o HD não foi escolhido no menu de boot (F12/F9/Esc) |
| Adaptador USB não aparece no `ifconfig -l` | `dmesg \| grep -i ue` e `usbconfig`. Troque de porta USB. Chips Realtek RTL8153 e ASIX AX88179 funcionam |
| Celular não vira interface `ue` | `kldload if_urndis`, desligue e ligue a ancoragem USB, confira `dmesg` |
| Cliente recebe IP mas não resolve nomes | Com o celular, os DNS da UnB podem recusar consultas de fora: use `1.1.1.1, 8.8.8.8` |
| `instalar.sh` diz que não dá para escolher a WAN | Há mais de uma interface Ethernet além da LAN: defina `WAN_IF` ou `WAN_MAC` |
| Linux não recebe `172.16.0.10` | `CLIENTE_MAC` errado (tem que ser o da placa com fio) ou a conexão está em IP manual |

## Privacidade (repositório público)

- **Fica só no seu computador:** `config/router.conf` e a pasta
  `docs/evidencias/local/`, ambos ignorados pelo Git.
- A saída de `diagnostico.sh` e as capturas `tcpdump` contêm IPs e MACs reais.
  Salve-as em `docs/evidencias/local/` (ex.:
  `sh scripts/diagnostico.sh > docs/evidencias/local/diag.txt`).
- Antes de publicar qualquer evidência, troque MACs e IPs reais por valores
  fictícios.
- Antes de cada commit, confira com `git status` e `git diff --cached` se
  nada real entrou.
