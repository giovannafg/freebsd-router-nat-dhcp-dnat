# Trabalho 02 – Camada de Rede: NAT + DHCP + DNAT

Fundamentos de Redes de Computadores – UnB/FGA – Prof. Tiago Alves

## Objetivo
Configurar um roteador FreeBSD que:
- recebe na interface **WAN** um IP da rede de acesso (`192.168.X.0/24`, gateway `192.168.X.1`);
- provê uma rede **LAN privada /16** (`172.16.0.0/16`, RFC 1918);
- faz **NAT** da LAN para a WAN (`pf`);
- distribui configuração de rede por **DHCP** (`isc-dhcp44-server`), com IP fixo para uma máquina de testes;
- faz **DNAT** da porta TCP 80 (WAN) para a porta TCP 8080 de um cliente da LAN;
- **bloqueia o encaminhamento de ping** (ICMP echo) da LAN para fora do segmento.

## Ambientes

| Ambiente | Roteador | WAN | Documentação |
|---|---|---|---|
| Simulação | 3 VMs QEMU (FreeBSD 14.5) | Rede virtual `192.168.50.0/24` | [simulacao.md](docs/simulacao.md), [testes.md](docs/testes.md) |
| Desenvolvimento físico | Notebook com boot no FreeBSD pelo HD externo | Celular (ancoragem USB) | [roteador-notebook.md](docs/roteador-notebook.md) |
| **Apresentação (LDS)** | O mesmo notebook + HD externo | Cabo na rede do professor | [O que muda no dia](docs/roteador-notebook.md#o-que-muda-no-dia-da-apresentação) |

A apresentação é feita em máquina física, como exige o enunciado. A
simulação serve só de ensaio.

## Topologia da apresentação
```
 rede de acesso 192.168.X.0/24 (roteador/switch do professor, gw 192.168.X.1)
   |                                   |
 [WAN: DHCP]                        notebook Windows (máquina WAN: DNAT/isolamento)
 ROTEADOR: notebook + FreeBSD no HD externo
 [LAN: adaptador USB, 172.16.0.1/16]
   |  cabo direto
 notebook Linux 172.16.0.10 (reserva DHCP, alvo do DNAT :8080)
```

## Sistema operacional e aplicações
- FreeBSD 14.5-RELEASE amd64
- `pf` (NAT, DNAT, firewall) e `pflog`, sistema base
- `isc-dhcp44-server` (DHCP): `pkg install isc-dhcp44-server`
- `syslogd`/`newsyslog` (log do DHCP em `/var/log/dhcpd.log`), sistema base
- `tcpdump`, `nc`, `telnet` (testes)

## Uso rápido (no roteador, como root)
```sh
cp config/router.conf.exemplo config/router.conf   # preencher com o seu hardware
sh scripts/instalar.sh -n                           # só valida
sh scripts/instalar.sh                              # backup + aplica
sh scripts/diagnostico.sh                           # estado do roteador
```

## Estrutura
| Arquivo | Função |
|---|---|
| `config/router.conf.exemplo` | Modelo dos valores do hardware. A cópia `config/router.conf` **não é versionada** |
| `config/pf.conf` | `/etc/pf.conf`: NAT, DNAT, bloqueio de ping, firewall |
| `config/dhcpd.conf` | `/usr/local/etc/dhcpd.conf` |
| `config/rc.conf` | Referência do que vai para `/etc/rc.conf` |
| `config/syslog-dhcpd.conf` | `/etc/syslog.d/dhcpd.conf`: log do DHCP |
| `config/newsyslog-dhcpd.conf` | `/etc/newsyslog.conf.d/dhcpd.conf`: rotação do log |
| `scripts/instalar.sh` | Valida (`pfctl -nf`, `dhcpd -t`), faz backup e aplica |
| `scripts/diagnostico.sh` | Mostra interfaces, regras, estados, log e leases (só leitura) |
| `docs/roteador-notebook.md` | Montagem física, instalação e **o que muda no dia** |
| `docs/roteiro-apresentacao.md` | Roteiro de testes do roteador físico |
| `docs/simulacao.md`, `docs/implementacao.md`, `docs/testes.md` | Simulação QEMU, aplicação manual e evidências |

## Privacidade
O repositório é **público**. Valores reais (MACs, IPs, nomes de interface)
ficam só em `config/router.conf` e em `docs/evidencias/local/`, ambos no
`.gitignore`. No repositório só entram valores fictícios.

## Status
- [x] Simulação: conectividade, NAT e isolamento ([testes.md](docs/testes.md))
- [x] Bloqueio de ping para fora da LAN no `pf.conf` (#14)
- [x] Log do DHCP em arquivo próprio (#5)
- [x] Script de instalação com validação e backup (#7)
- [ ] Instalar o FreeBSD no HD externo e testar com o celular como WAN
- [ ] Ensaio no LDS com a rede do professor (DNAT e isolamento)
- [ ] Limitações conhecidas e documentação final (#8, #9)

## Referências
- Wright, G. R.; Stevens, W. R. *TCP/IP Illustrated, Vol. 2*. Addison-Wesley, 1995.
- Lucas, M. W. *Networking for System Administrators*. 2. ed. Tilted Windmill Press, 2025.
- Costa, M. A. L. *Conjunto de ensaios didáticos para a experimentação de fundamentos de redes de computadores* (TCC, UnB). https://markinlimac.github.io/monografia-redes/
