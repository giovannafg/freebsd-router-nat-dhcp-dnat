# Roteiro de testes (rascunho)

## Conectividade
- [ ] Cliente da LAN recebe IP por DHCP e pinga o roteador (172.16.0.1)
- [ ] Cliente da LAN pinga o gateway do lab (192.168.X.1) e um IP externo
- [ ] Resolução de nomes funcionando no cliente

## Tradução de endereço (NAT)
- [ ] `pfctl -s state` mostra as conexões traduzidas
- [ ] `tcpdump -i em0` no roteador: origem dos pacotes é o IP da WAN, não 172.16.x.x

## Isolamento de segmento
- [ ] Máquina do lado WAN não alcança diretamente IPs 172.16.0.0/16

## DHCP
- [ ] Máquina de testes sempre recebe 172.16.0.10
- [ ] Leases em `/var/db/dhcpd.leases` e logs em `/var/log/messages`

## DNAT
- [ ] Na máquina de testes: `nc -l 8080`
- [ ] De outra máquina na WAN: `nc <IP_WAN_roteador> 80` (ou `telnet`), mensagem chega nos dois lados
