# Roteiro de testes do roteador físico

Ordem sugerida para a apresentação. Cada teste diz **onde rodar**, o
**comando** e o **resultado esperado**. A preparação está em
[roteador-notebook.md](roteador-notebook.md).

Legenda da coluna "Dev": **sim** = dá para fazer no desenvolvimento, com o
celular como WAN; **não** = só com a rede do professor.

| Máquina | Papel |
|---|---|
| **Roteador** | Notebook com FreeBSD (HD externo). Use dois consoles: Alt+F1 e Alt+F2 |
| **Linux** | Cliente da LAN, `172.16.0.10`, servidor do DNAT |
| **Windows** | Máquina do lado WAN (só na apresentação) |

Nos comandos, troque `<wan>`/`<lan>` pelos nomes que
`sh scripts/diagnostico.sh interfaces` mostra, e `IP_WAN` pelo IP da WAN do
roteador. Para guardar evidências sem publicar dados reais, salve as saídas em
`docs/evidencias/local/`, que é ignorada pelo Git.

## Preparação

- **Linux:** Wi-Fi desligado; cabo direto no adaptador USB do roteador;
  conexão com fio em DHCP automático; `nc` instalado.
- **Windows (apresentação):** Wi-Fi desligado; cabo na rede do professor.
  Ative o cliente telnet uma vez, no PowerShell como administrador:
  `dism /online /Enable-Feature /FeatureName:TelnetClient`. Opcional: Nmap,
  que traz o `ncat`.
- **Roteador:** `sh scripts/instalar.sh -n` passa, e
  `sh scripts/diagnostico.sh interfaces` mostra a WAN com IP e a LAN com
  `172.16.0.1`.

## 1. DHCP e reserva fixa (Dev: sim)

| Onde | Comando | Esperado |
|---|---|---|
| Linux | `ip -4 addr show` e `ip route` | IP `172.16.0.10/16` na placa com fio; `default via 172.16.0.1` |
| Linux | `resolvectl status` (ou `cat /etc/resolv.conf`) | DNS igual a `DNS_SERVERS` |
| Linux | Desconecte e reconecte o cabo; repita `ip -4 addr show` | Recebe **de novo** `172.16.0.10` (a reserva é pelo MAC) |

## 2. Leases e log do DHCP (Dev: sim)

| Onde | Comando | Esperado |
|---|---|---|
| Roteador | `grep 172.16.0.10 /var/log/dhcpd.log \| tail` | `DHCPDISCOVER`, `DHCPOFFER`, `DHCPREQUEST`, `DHCPACK on 172.16.0.10 to <MAC do Linux>` |
| Roteador | `sh scripts/diagnostico.sh dhcp` | Serviço rodando, as mesmas linhas do log, e a lista de leases |
| Roteador | `cat /var/db/dhcpd/dhcpd.leases` | Leases do pool dinâmico `172.16.1.100–200` |

Explicação para o professor: **reservas fixas (`fixed-address`) não são
gravadas no arquivo de leases** do ISC DHCP, só no log. Para mostrar uma
lease dinâmica no arquivo, ligue por alguns minutos outra máquina na LAN
(por exemplo, o Windows com Wi-Fi desligado). Ela recebe um IP de
`172.16.1.100` em diante, que aparece em `dhcpd.leases`.

## 3. Conectividade (Dev: sim)

| Onde | Comando | Esperado |
|---|---|---|
| Linux | `ping -c 3 172.16.0.1` | 3 respostas (o roteador responde na LAN) |
| Linux | `curl -sI http://example.com \| head -1` | `HTTP/1.1 200 OK` (sai para fora pelo NAT) |
| Linux | `getent hosts unb.br` | Um endereço IP (DNS funcionando) |

O teste de saída para fora é feito por TCP porque o ping para fora é
bloqueado de propósito (teste 5).

## 4. Tradução de endereço, NAT (Dev: sim)

No **roteador**, um console para cada captura:

```sh
tcpdump -ni <lan> -c 4 'tcp port 80'     # Alt+F1
tcpdump -ni <wan> -c 4 'tcp port 80'     # Alt+F2
```

No **Linux**: `curl -sI http://example.com`. Logo depois, no **roteador**:
`pfctl -ss | grep ':80 '`.

Esperado:
- na captura da `<lan>`, a origem é `172.16.0.10.<porta>`;
- na captura da `<wan>`, a origem é `IP_WAN.<porta>`: o endereço foi traduzido;
- `pfctl -ss` mostra `IP_WAN:<porta> (172.16.0.10:<porta>) -> <destino>:80`.

## 5. Bloqueio do ping para fora da LAN (Dev: sim)

| Onde | Comando | Esperado |
|---|---|---|
| Roteador | `tcpdump -n -e -ttt -i pflog0 icmp` (deixe rodando) | – |
| Linux | `ping -c 3 <gateway da WAN>` (veja `netstat -rn` no roteador) | 100% de perda |
| Linux | `ping -c 3 1.1.1.1` | 100% de perda |
| Roteador | (saída do `tcpdump` acima) | `block in on <lan>: 172.16.0.10 > ...: ICMP echo request` |
| Roteador | `pfctl -vsr \| grep -A 3 'icmp-type echoreq'` | Contador `Packets` da regra `block in log quick on <lan> ...` maior que zero |
| Linux | `ping -c 3 172.16.0.1` | Continua respondendo: o bloqueio é só para fora do segmento |
| Roteador | `ping -c 3 1.1.1.1` | Responde: o roteador pinga, só não **encaminha** ping da LAN |

## 6. DNAT: WAN TCP 80 → Linux TCP 8080 (Dev: não)

| Onde | Comando | Esperado |
|---|---|---|
| Linux | `nc -l 8080` (netcat tradicional: `nc -l -p 8080`) | Fica esperando |
| Windows | `telnet IP_WAN 80` | Conecta. O que se digita aparece no Linux, e o que se digita no Linux aparece no Windows |
| Windows | `ncat IP_WAN 80` (opcional, com Nmap) | Mesmo comportamento, com netcat |
| Roteador | `pfctl -ss \| grep 8080` | `172.16.0.10:8080 (IP_WAN:80) <- <IP do Windows>:<porta>` |

Para encerrar: Ctrl+C no Linux, ou Ctrl+] e depois `quit` no telnet.

## 7. Isolamento do segmento (Dev: não)

Mantenha `nc -l 8080` rodando no Linux. No **Windows**, no PowerShell como
administrador, crie uma rota que aponta a LAN privada para o roteador:

```powershell
route add 172.16.0.0 mask 255.255.0.0 IP_WAN
ping -n 3 IP_WAN
ping -n 3 172.16.0.10
Test-NetConnection 172.16.0.10 -Port 8080
Test-NetConnection IP_WAN -Port 22
Test-NetConnection IP_WAN -Port 80
route delete 172.16.0.0
```

Esperado:
- `ping IP_WAN` **responde**: o roteador está alcançável na WAN;
- `ping 172.16.0.10` **falha**: a LAN não é alcançável pela WAN, mesmo com rota;
- porta 8080 direto no IP privado: `TcpTestSucceeded : False`;
- porta 22 do roteador: `False` (sem SSH pela WAN);
- porta 80 da WAN: `True`. É o DNAT funcionando, o que prova que o `False`
  anterior é o firewall, e não um serviço desligado.

No roteador, `pfctl -vsr` mostra os contadores do bloqueio padrão subindo.

## 8. Persistência (Dev: sim)

`reboot` no roteador. Depois do boot, sem rodar nenhum comando de
configuração: `sh scripts/diagnostico.sh`. As interfaces, o
encaminhamento (`net.inet.ip.forwarding: 1`), o PF, o pflog e o `isc-dhcpd`
devem estar ativos. Repita o teste 1 no Linux.

## Se algo falhar

1. `sh scripts/diagnostico.sh` mostra papéis, IPs, regras com contadores,
   estados e DHCP.
2. Um cabo ou adaptador trocado muda os nomes das interfaces: rode
   `sh scripts/instalar.sh` de novo.
3. Estados antigos podem mascarar testes negativos: `pfctl -F states`.
