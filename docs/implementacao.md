# Interfaces, roteamento e NAT — issue #2

**Validação física pendente.** Primeiro prepare as VMs descritas em
[simulacao.md](simulacao.md), ou levante os valores reais do laboratório.
Execute os comandos do roteador pelo console local, como root: a política
não libera novas conexões SSH pela WAN.

## Aplicar as interfaces

Faça backup antes de editar:

```sh
cp -p /etc/rc.conf /etc/rc.conf.antes-nat
[ ! -f /etc/pf.conf ] || cp -p /etc/pf.conf /etc/pf.conf.antes-nat
```

Mescle as entradas de `config/rc.conf` em `/etc/rc.conf`; não substitua o
arquivo inteiro, pois a instalação pode conter outras configurações.
Remova entradas duplicadas/conflitantes. Na imagem oficial, remova também
`ifconfig_DEFAULT` para não solicitar DHCP na LAN. Habilite `dhcpd` somente
quando o pacote e sua configuração estiverem instalados; os testes de NAT
usam IP manual e não dependem desse serviço.

No perfil simulado, aplique imediatamente:

```sh
sysrc ifconfig_em0=DHCP
sysrc ifconfig_em1='inet 172.16.0.1 netmask 255.255.0.0'
sysrc gateway_enable=YES pf_enable=YES pf_rules=/etc/pf.conf
service dhclient stop em1
ifconfig em1 inet 172.16.0.1 netmask 255.255.0.0 up
service routing restart
service dhclient restart em0
ifconfig em0
route -n get default
sysctl net.inet.ip.forwarding
```

Espere IP WAN na rede `192.168.50.0/24`, gateway `192.168.50.1` e
`net.inet.ip.forwarding: 1`. O IP recebido por DHCP pode variar; use o
endereço observado nas próximas etapas.

## Validar e carregar PF

Transfira `config/pf.conf` para `/etc/pf.conf` e valide antes de ativar:

```sh
kldload pf                         # apenas se ainda não estiver carregado
pfctl -nf /etc/pf.conf && service pf restart
pfctl -s info
pfctl -sn
pfctl -sr
```

O encadeamento com `&&` impede a carga se a análise falhar. A checagem
`-n` não aplica regras. A saída de `pfctl -s info` deve indicar PF habilitado.
Um reload preserva estados antigos: no ambiente isolado, antes dos testes
negativos, use `pfctl -F states` para eliminar permissões criadas pela antiga
política aberta. Isso interrompe conexões existentes.

## Política

- Bloqueio padrão de IPv4/IPv6, com loopback fora da filtragem.
- LAN `172.16.0.0/16` inicia conexões pela `em1`; o estado permite respostas.
- NAT usa `($ext_if)` para acompanhar o endereço DHCP da WAN.
- DHCP WAN (cliente) e LAN (servidor) têm exceções UDP específicas, inclusive
  broadcast e cliente ainda com origem `0.0.0.0`.
- A publicação existente TCP 80 WAN → `172.16.0.10:8080` marca o fluxo com `DNAT_WEB`.
  As regras de entrada WAN e saída LAN exigem essa marca. Uma rota estática da máquina WAN
  até a LAN não libera conexão direta a `172.16.0.10:8080`.
- Novas conexões WAN → roteador/LAN ficam bloqueadas, salvo DHCP e DNAT.
  IPv6 roteado não faz parte do trabalho e permanece bloqueado.

## Cliente manual e verificação

No cliente LAN FreeBSD, como root:

```sh
service dhclient stop em0
ifconfig em0 inet 172.16.0.10 netmask 255.255.0.0 up
route delete default              # só se houver uma rota anterior
route add default 172.16.0.1
ping -c 3 172.16.0.1
ping -c 3 192.168.50.1
```

Configure a máquina WAN com `192.168.50.200/24` e gateway `192.168.50.1`.
Siga [testes.md](testes.md) para comprovar tradução e isolamento. Se houver
falha, confira interfaces, rotas e contadores de `pfctl -vvs rules` antes de
alterar regras.

## Recuperação pelo console

Para retornar às regras anteriores, valide e recarregue o backup de PF, se
existir. Restaure `/etc/rc.conf.antes-nat` e reinicie a VM para reaplicar as
interfaces anteriores. Não dependa de uma sessão WAN para corrigir o firewall.

## Referências

- [PF no Handbook do FreeBSD](https://docs.freebsd.org/en/books/handbook/firewalls/#firewalls-pf)
- [pf.conf(5) do FreeBSD](https://man.freebsd.org/cgi/man.cgi?query=pf.conf&sektion=5)
