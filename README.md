# Trabalho 02 – Camada de Rede: NAT + DHCP + DNAT

Fundamentos de Redes de Computadores – UnB/FGA – Prof. Tiago Alves

## Objetivo
Configurar um roteador FreeBSD que:
- recebe na interface **WAN** um IP da rede de acesso (perfil simulado: `192.168.50.0/24`, gateway `192.168.50.1`);
- provê uma rede **LAN privada /16** (`172.16.0.0/16`, RFC 1918);
- faz **NAT** da LAN para a WAN (`pf`);
- distribui configuração de rede por **DHCP** (`isc-dhcp44-server`), com IP fixo para uma máquina de testes;
- faz **DNAT** da porta TCP 80 (WAN) para a porta TCP 8080 de um cliente da LAN.

## Ambiente de validação

Este repositório usa um perfil de **simulação QEMU**, com valores definidos
para a rede virtual. **Falta executar o teste físico no laboratório.** A rede
`192.168.50.0/24`, as interfaces `em0`/`em1` e o MAC `52:54:00:16:00:10`
não foram levantados em equipamento real. Antes da implantação física,
substitua esses valores pelos observados e repita os testes.

Consulte [a preparação e reprodução da simulação](docs/simulacao.md) e
o [passo a passo de interfaces, roteamento e NAT](docs/implementacao.md).

## Topologia
```
 WAN simulada 192.168.50.0/24                     LAN 172.16.0.0/16
 [gw 192.168.50.1]---(em0 WAN: DHCP) ROTEADOR (em1 LAN: 172.16.0.1)---[clientes DHCP]
                                                                    \--[maquina-teste 172.16.0.10 :8080]
```

## Sistema operacional e aplicações
- FreeBSD 14.5-RELEASE amd64 (imagem oficial UFS para a simulação)
- `pf` (NAT e DNAT), sistema base
- `isc-dhcp44-server` (DHCP): `pkg install isc-dhcp44-server`
- `nc` / `telnet` (testes de DNAT)

## Estrutura
| Arquivo | Destino no roteador |
|---|---|
| `config/rc.conf` | trechos para `/etc/rc.conf` |
| `config/pf.conf` | `/etc/pf.conf` |
| `config/dhcpd.conf` | `/usr/local/etc/dhcpd.conf` |
| `docs/testes.md` | roteiro de validação |

## Status
- [x] Definir interfaces e rede do perfil simulado (`em0`/`em1`, rede 50)
- [ ] Levantar interfaces e rede reais e executar o teste físico
- [x] Preencher o MAC do cliente simulado no `dhcpd.conf`
- [x] Escrever o passo a passo de interfaces, roteamento e NAT
- [ ] Executar e documentar os testes
- [ ] Limitações conhecidas

## Referências
- Wright, G. R.; Stevens, W. R. *TCP/IP Illustrated, Vol. 2*. Addison-Wesley, 1995.
- Lucas, M. W. *Networking for System Administrators*. 2. ed. Tilted Windmill Press, 2025.
- Costa, M. A. L. *Conjunto de ensaios didáticos para a experimentação de fundamentos de redes de computadores* (TCC, UnB). https://markinlimac.github.io/monografia-redes/
