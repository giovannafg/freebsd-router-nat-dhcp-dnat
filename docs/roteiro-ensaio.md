# Ensaio do grupo: quem faz o quê

Roteiro para montar e testar o roteador **sem a rede do professor**. Depois
que tudo passar aqui, a apresentação só troca a WAN (última seção).

A ordem e o resultado esperado de cada teste estão em
[roteiro-apresentacao.md](roteiro-apresentacao.md), que usa Linux e Windows
nos exemplos. Aqui está a divisão de tarefas, os cabos, a ordem e os
[comandos equivalentes em cada sistema](#comandos-por-sistema).

## As três máquinas

| Máquina | Quem | Papel | Sistema |
|---|---|---|---|
| **Roteador** | **Giovanna** | O notebook Acer da Giovanna, dando boot pelo FreeBSD instalado no HD externo. Faz NAT, DHCP, DNAT e firewall | FreeBSD (no HD externo) |
| **Cliente LAN** | Pessoa B | Notebook do lado de dentro. Recebe `172.16.0.10` por DHCP e é o servidor do DNAT (porta 8080) | Qualquer: Linux, macOS ou Windows |
| **Máquina WAN** | Pessoa C | Notebook do lado de fora. Faz o papel da "internet" que tenta acessar a LAN | Qualquer: Linux, macOS ou Windows |

### Restrições

- **Roteador:** tem que ser o Acer da Giovanna com o HD externo. É a única
  máquina com o FreeBSD instalado, e o enunciado proíbe VM: o roteador precisa
  ser uma máquina física. Os outros dois notebooks não têm restrição de
  sistema.
- **São três máquinas diferentes.** O cliente LAN e a máquina WAN não podem
  ser o mesmo notebook: cada um fica de um lado do roteador.
- **Cliente LAN:**
  - precisa de **porta de rede com fio**, própria ou num adaptador
    USB-Ethernet (comum em MacBook);
  - o `CLIENTE_MAC` é o MAC dessa placa **com fio**, e não o do Wi-Fi. Se
    trocar de notebook ou de adaptador, o MAC muda e precisa rodar
    `sh scripts/instalar.sh` de novo;
  - precisa de um programa que escute na porta 8080 (netcat, ou `ncat` no
    Windows), e o firewall do sistema tem que liberar a 8080 de entrada;
  - **Wi-Fi desligado** durante os testes. Senão ele sai pelo Wi-Fi sem
    passar pelo roteador, e os testes de NAT perdem o sentido.
- **Máquina WAN:**
  - na fase 2, precisa de **porta de rede com fio** (cabo direto até o
    roteador);
  - precisa de `telnet` ou netcat para o teste de DNAT;
  - precisa de permissão de administrador para criar uma rota (teste 7);
  - **Wi-Fi desligado** durante os testes.

## As interfaces do roteador

| Interface | O que é fisicamente | Liga em |
|---|---|---|
| **LAN** (`172.16.0.1`) | Adaptador USB-Ethernet | Cabo direto até o cliente LAN. **Sempre igual, em todas as fases** |
| **WAN**, fase 1 | Celular com ancoragem USB | Só o celular (dá internet) |
| **WAN**, fase 2 | Porta de rede do próprio Acer | Cabo direto até a máquina WAN |
| **WAN**, apresentação | A mesma porta de rede do Acer | Switch/roteador do professor |

> Regra de ouro: **o cabo do adaptador USB (LAN) só vai no cliente LAN.**
> Nunca em roteador de casa nem na rede do professor: o DHCP de vocês
> disputaria com o da rede e derrubaria todo mundo.

## Material

- Acer da Giovanna + HD externo + cabo Y. O pendrive do instalador não é
  mais necessário
- Adaptador USB-Ethernet (LAN do roteador)
- Celular Android + cabo USB (iPhone também serve, com `CELULAR="iphone"`,
  mas não foi testado)
- 2 cabos de rede (LAN e WAN)
- Cliente LAN e máquina WAN carregados, com porta de rede ou adaptador

## Fase 0: preparar (antes de juntar as máquinas)

**Giovanna (roteador):** seções 3, 4 e 5 de [roteador-notebook.md](roteador-notebook.md):
boot pelo HD, internet pelo celular, `pkg install`, `git clone`,
`git checkout feat/roteador-notebook-hd` (enquanto o PR #16 não estiver na
`main`), preencher `config/router.conf`. O `CLIENTE_MAC` vem da Pessoa B.

**Pessoa B (cliente LAN):**
- Descobre o MAC da placa **com fio** (ver [comandos](#comandos-por-sistema))
  e passa para a Giovanna.
- Instala o netcat (Linux/macOS) ou o Nmap, que traz o `ncat` (Windows).
- Libera a porta 8080 de entrada no firewall.
- Deixa a conexão com fio em **automático (DHCP)**.

**Pessoa C (máquina WAN):**
- Windows: ativa o telnet uma vez, no PowerShell como administrador:
  `dism /online /Enable-Feature /FeatureName:TelnetClient`.
- Linux/macOS: confere se tem `nc` (ou instala o netcat).

## Fase 1: celular como WAN (testa a saída para a internet)

```
celular ==USB== [WAN] Acer da Giovanna (FreeBSD) [LAN: adaptador USB] ---cabo--- cliente LAN
```

`config/router.conf` da Giovanna:

```sh
CELULAR="android"
WAN_IF=""                 # o script acha o celular sozinho
WAN_CONFIG="DHCP"
WAN_GATEWAY=""
DNS_SERVERS="1.1.1.1, 8.8.8.8"
```

Ordem:
1. **Giovanna:** conecta o adaptador USB da LAN **antes** de ligar o Acer.
   Liga, loga como root e ativa a ancoragem USB no celular.
2. **Giovanna:** `sh scripts/instalar.sh -n`, depois `sh scripts/instalar.sh`.
3. **Pessoa B:** desliga o **Wi-Fi** e liga o cabo no adaptador USB do
   roteador.
4. Testes do [roteiro](roteiro-apresentacao.md):

| Teste | Quem roda | O que prova |
|---|---|---|
| 1. DHCP e reserva fixa | B | Cliente LAN recebe `172.16.0.10` |
| 2. Leases e log | Giovanna | O DHCP registra o que entregou |
| 3. Conectividade | B | Cliente LAN navega passando pelo roteador |
| 4. NAT | Giovanna (tcpdump) + B (curl) | Endereço `172.16.0.10` vira o IP da WAN |
| 5. Bloqueio de ping | Giovanna + B | Ping para fora da LAN é bloqueado |
| 8. Persistência | Giovanna (reboot) + B | Tudo volta sozinho depois do boot |

A Pessoa C não participa da fase 1.

## Fase 2: máquina WAN como "rede do professor" (testa DNAT e isolamento)

O celular sai. A WAN do roteador passa a ser um cabo direto da porta de rede
do Acer até a máquina WAN, com IPs fixos. Não tem internet nesta fase, e nem
precisa: os testes 6 e 7 só olham o tráfego entre a WAN e a LAN.

```
máquina WAN 192.168.50.2 ---cabo--- [WAN 192.168.50.1] Acer da Giovanna [LAN 172.16.0.1] ---cabo--- cliente LAN 172.16.0.10
```

1. **Giovanna:** desconecta o celular e liga o cabo da porta de rede do Acer
   na máquina WAN. Descobre o nome da porta com `ifconfig -l` (no Acer deve
   ser algo como `re0`; não é a `ue` do adaptador da LAN).
2. **Giovanna:** edita `config/router.conf`:

   ```sh
   CELULAR=""
   WAN_IF="re0"              # o nome real da porta de rede do Acer
   WAN_CONFIG="inet 192.168.50.1 netmask 255.255.255.0"
   WAN_GATEWAY="192.168.50.2"
   ```

   Aplica: `sh scripts/instalar.sh -n`, depois `sh scripts/instalar.sh`.
3. **Pessoa C:** desliga o **Wi-Fi** e põe na placa com fio o IP manual
   `192.168.50.2`, máscara `255.255.255.0`, sem gateway (ver
   [comandos](#comandos-por-sistema)).
4. **Pessoa C:** `ping 192.168.50.1` tem que responder. Se não responder,
   confira o cabo e rode `sh scripts/diagnostico.sh interfaces` no roteador.
5. Testes do [roteiro](roteiro-apresentacao.md), com `IP_WAN = 192.168.50.1`:

| Teste | Quem roda | O que prova |
|---|---|---|
| 6. DNAT | B (escuta na 8080) + C (conecta em `192.168.50.1` porta 80) | A porta 80 da WAN chega na 8080 do cliente LAN |
| 7. Isolamento | C (cria a rota e testa), com a B escutando na 8080 | A WAN não alcança a LAN diretamente, nem com rota |

6. **Pessoa C:** no final, volta a placa com fio para **automático (DHCP)** e
   apaga a rota do teste 7.

> Atalho: se alguém tiver um **roteador de casa com portas de rede**, ligue
> nele a WAN do Acer e a máquina WAN, com `WAN_CONFIG="DHCP"` e
> `WAN_GATEWAY=""`. Isso é igual à rede do professor, tem internet e permite
> fazer os 8 testes de uma vez, sem celular e sem IP fixo.

## Comandos por sistema

`IP_WAN` é o IP da WAN do roteador (`192.168.50.1` na fase 2). `<if>` é o
nome da placa com fio (Linux: `enp...`/`eth0`; macOS: `en...`).

### Cliente LAN (Pessoa B)

| Para quê | Linux | macOS | Windows |
|---|---|---|---|
| MAC da placa com fio | `ip link` → `link/ether` | `networksetup -listallhardwareports` → `Ethernet Address` | `getmac /v` (linha "Ethernet") |
| Ver IP, gateway e DNS (teste 1) | `ip -4 addr show`, `ip route`, `resolvectl status` | `ifconfig <if>`, `netstat -rn`, `scutil --dns` | `ipconfig /all` |
| Renovar o DHCP (teste 1) | Desconectar e reconectar o cabo | Desconectar e reconectar o cabo | `ipconfig /release` e `ipconfig /renew` |
| Ping (testes 3 e 5) | `ping -c 3 <ip>` | `ping -c 3 <ip>` | `ping -n 3 <ip>` |
| Saída HTTP (testes 3 e 4) | `curl -sI http://example.com` | `curl -sI http://example.com` | `curl.exe -sI http://example.com` |
| DNS (teste 3) | `getent hosts unb.br` | `nslookup unb.br` | `nslookup unb.br` |
| Escutar na 8080 (testes 6 e 7) | `nc -l 8080` (ou `nc -l -p 8080`) | `nc -l 8080` | `ncat -l 8080` (vem com o Nmap) |
| Liberar a 8080 no firewall | `sudo ufw allow 8080/tcp` (se usar ufw) | Aceitar o aviso "permitir conexões" ao rodar o `nc` | `New-NetFirewallRule -DisplayName "DNAT 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow` (PowerShell como admin) |

### Máquina WAN (Pessoa C)

| Para quê | Linux | macOS | Windows |
|---|---|---|---|
| IP fixo na fase 2 | Configurações de rede → Com fio → IPv4 manual (ou `nmcli`) | Ajustes → Rede → Ethernet → Detalhes → TCP/IP → Manualmente | Configurações → Rede → Ethernet → Atribuição de IP → Manual |
| Conectar no DNAT (teste 6) | `nc IP_WAN 80` | `nc IP_WAN 80` | `telnet IP_WAN 80` (ou `ncat IP_WAN 80`) |
| Criar a rota (teste 7) | `sudo ip route add 172.16.0.0/16 via IP_WAN` | `sudo route -n add -net 172.16.0.0/16 IP_WAN` | `route add 172.16.0.0 mask 255.255.0.0 IP_WAN` (como admin) |
| Ping (teste 7) | `ping -c 3 <ip>` | `ping -c 3 <ip>` | `ping -n 3 <ip>` |
| Testar porta TCP (teste 7) | `nc -zv -w 3 <ip> <porta>` | `nc -zv -G 3 <ip> <porta>` | `Test-NetConnection <ip> -Port <porta>` |
| Apagar a rota (fim do teste 7) | `sudo ip route del 172.16.0.0/16` | `sudo route -n delete -net 172.16.0.0/16` | `route delete 172.16.0.0` |

No teste 7, "conectou" é `succeeded`/`open` no `nc` ou `TcpTestSucceeded : True`
no Windows. "Falhou" é timeout ou `False`.

## Checklist de "está pronto para mostrar"

- [ ] Testes 1 a 8 passaram pelo menos uma vez
- [ ] Saídas do roteador salvas em `docs/evidencias/local/` (Giovanna) e
      prints do cliente LAN e da máquina WAN
- [ ] Cada pessoa sabe explicar o teste que roda
- [ ] `config/router.conf` **não** foi commitado (`git status` sem ele)

## No dia, na rede do professor

Só a WAN muda. A LAN, o cliente LAN e o `CLIENTE_MAC` ficam iguais. Usem
**os mesmos notebooks** do ensaio. Se o cliente LAN mudar, o `CLIENTE_MAC`
muda junto.

1. **Giovanna:** liga o cabo da porta de rede do Acer (a mesma da fase 2) no
   switch/roteador do professor.
2. **Giovanna:** em `config/router.conf`:

   ```sh
   WAN_CONFIG="DHCP"         # ou o IP fixo que o professor indicar
   WAN_GATEWAY=""            # só preencha se usar IP fixo
   DNS_SERVERS="192.168.X.1" # se 'host unb.br 192.168.X.1' responder;
                             # senão "164.41.101.4, 164.41.101.11"
   ```

   Roda `sh scripts/instalar.sh -n`, `sh scripts/instalar.sh`, `reboot` e
   `sh scripts/diagnostico.sh interfaces`. **Anota o IP da WAN** e passa para
   a Pessoa C.
3. **Pessoa C:** máquina WAN com cabo na rede do professor, Wi-Fi desligado,
   IP automático.
4. Rodem o [roteiro completo](roteiro-apresentacao.md) na ordem, de 1 a 8.
