# Testes de conectividade, NAT e isolamento — issue #3

> **Atualização (issue #14):** o `pf.conf` agora bloqueia ping da LAN para
> fora do segmento, como pede o enunciado. Os pings para `192.168.50.1` e
> `1.1.1.1` abaixo foram executados **antes** dessa regra: hoje eles devem
> falhar. O roteiro do roteador físico ([roteiro-apresentacao.md](roteiro-apresentacao.md))
> prova conectividade e NAT por TCP e testa o bloqueio.

**Simulação executada; teste físico no laboratório pendente.**
Execução em 08/11/2026 (Brasil; 09/11 em UTC), com três VMs FreeBSD
14.5-RELEASE e QEMU 11.1.2/TCG. Consulte a [topologia e inicialização](simulacao.md)
e a [aplicação das configurações](implementacao.md).

## Resultado da execução

| Grupo | Resultado simulado | Evidência de console |
|---|---|---|
| Preparação e sintaxe PF | `em0`/`em1`, forwarding=1, `pfctl -nf` retorna 0 | [configuração](evidencias/simulacao/configuracao.txt) |
| Persistência após reboot | WAN DHCP, LAN /16 e PF habilitado | [reboot](evidencias/simulacao/reboot.txt) |
| Conectividade | 3/3 respostas do roteador, gateway WAN e `1.1.1.1` | [pings](evidencias/simulacao/conectividade.txt) |
| NAT | origem LAN `172.16.0.10` vira WAN `192.168.50.101`; respostas voltam | [capturas e estados](evidencias/simulacao/nat.txt) |
| Controle da política original | WAN alcança LAN por ICMP e TCP: reproduz a falha | [controle](evidencias/simulacao/controle-politica-original.txt) |
| Isolamento com PF corrigido | ping perde 3/3; TCP direto 8080 e SSH WAN expiram | [isolamento](evidencias/simulacao/isolamento.txt) |
| Controle positivo do serviço LAN | WAN:80 → LAN:8080 funciona com o mesmo listener | [isolamento](evidencias/simulacao/isolamento.txt) |

Os arquivos contêm saída de console, com finais de linha e espaços finais normalizados; não
são resultados esperados inventados. A imagem oficial foi conferida pelo
SHA-256 registrado em `simulacao.md`. O PF aplicado na VM tem SHA-256
`9db565f01fdf80ebd8b7deb7f500124ee1386f1c700c79dccbd23dd8047fcec6`,
igual a `config/pf.conf` nesta revisão.

## Pré-condições

- Roteador: `em0=192.168.50.101/24` via DHCP, gateway `192.168.50.1`,
  `em1=172.16.0.1/16`; PF ativo e encaminhamento IPv4 habilitado.
- Cliente LAN: `172.16.0.10/16`, gateway `172.16.0.1`, MAC
  `52:54:00:16:00:10`, sem outra interface de rede.
- Máquina WAN: `192.168.50.200/24`, gateway `192.168.50.1`.
- Os comandos são de FreeBSD e executados como root quando necessário.
  O IP WAN pode mudar: confirme `ifconfig em0` no roteador e substitua
  `192.168.50.101` nos comandos se necessário.
- Antes dos testes negativos, em ambiente isolado, rode `pfctl -F states`
  no roteador. Estados da antiga política podem permitir conexões mesmo
  depois da troca de regras; esse comando interrompe conexões existentes.

## 1. Conectividade

No **cliente LAN**:

```sh
ping -c 3 -t 5 172.16.0.1
ping -c 3 -t 5 192.168.50.1
ping -c 3 -t 5 1.1.1.1
```

Esperado: três respostas por destino. O primeiro comprova o enlace LAN;
o segundo comprova roteamento/NAT até o acesso; o terceiro comprova saída
externa. Um alvo externo pode deixar de responder a ICMP: investigue também
no roteador antes de atribuir a falha ao NAT. Como diagnóstico adicional,
`nc -z -v -w 3 1.1.1.1 80` passou nesta execução.

## 2. Tradução NAT

No **roteador**, em dois terminais, antes de gerar o tráfego:

```sh
tcpdump -ni em1 -U -c 6 -w /tmp/nat-icmp-lan.pcap 'icmp and host 1.1.1.1'
```

```sh
tcpdump -ni em0 -U -c 6 -w /tmp/nat-icmp-wan.pcap 'icmp and host 1.1.1.1'
```

No **cliente LAN**, execute `ping -c 3 -t 5 1.1.1.1`. Logo depois, no
**roteador**, antes de o estado ICMP expirar:

```sh
pfctl -ss
tcpdump -nn -r /tmp/nat-icmp-lan.pcap
tcpdump -nn -r /tmp/nat-icmp-wan.pcap
```

Esperado: os mesmos números de sequência aparecem nas duas interfaces.
Na LAN, a origem do request é `172.16.0.10`; na WAN, `192.168.50.101`.
O reply retorna para o IP WAN e reaparece na LAN destinado ao cliente.
O estado do PF relaciona os endereços e os identificadores ICMP traduzidos.
Isso comprova a tradução feita pelo FreeBSD antes da saída pelo SLIRP.
Se houver perda, interrompa as capturas com Ctrl+C em vez de esperar seis
pacotes indefinidamente; registre a falha.

## 3. Isolamento com rota explícita

No **cliente LAN**, mantenha um serviço ativo:

```sh
nc -l -k 8080
```

Na **máquina WAN**, adicione a rota e confira o caminho antes dos testes:

```sh
route add -net 172.16.0.0/16 192.168.50.101
route -n get 172.16.0.10
ping -c 3 -t 5 172.16.0.10
nc -z -v -w 3 172.16.0.10 8080
echo $?
nc -z -v -w 3 192.168.50.101 22
echo $?
nc -z -v -w 3 192.168.50.101 80
echo $?
```

Se a rota já existir, confira seu gateway; não interprete `File exists`
como falha do isolamento. Esperado: rota aponta para o roteador WAN;
ping sem respostas; TCP direto ao cliente e SSH no roteador expiram e
retornam código 1; a porta publicada WAN:80 retorna 0. O último teste
confirma que o serviço está vivo, evitando confundir firewall com porta
fechada. No roteador, `pfctl -vvs rules` permite conferir os contadores.

O controle de regressão foi executado **somente na rede virtual isolada**:
carregou-se temporariamente o `pf.conf` original de `main` (commit
`574ed16`, com `pass all`). Ping e TCP direto passaram. Em seguida,
restaurou-se `/etc/pf.conf`, validou-se a sintaxe e limparam-se os estados.
A política corrigida bloqueou os mesmos acessos. Não carregue a política
aberta numa rede física para repetir esse controle.

Ao concluir, na máquina WAN, remova a rota temporária:

```sh
route delete -net 172.16.0.0/16 192.168.50.101
```

Encerre listeners/capturas e desligue as três VMs com `shutdown -p now`.

## Correções verificadas durante a execução

- Reiniciar o serviço de roteamento removeu a rota padrão aprendida por DHCP.
  Renovar `dhclient em0` reinstalou `192.168.50.1`; o passo a passo inclui
  a renovação antes dos testes externos.
- O bloqueio padrão também exige permitir a saída do fluxo DNAT na LAN.
  A tradução agora marca `DNAT_WEB`; somente o fluxo marcado passa pelas
  regras WAN/LAN. Testaram-se tanto a publicação quanto o bloqueio direto.
- O reboot confirmou o carregamento persistente das interfaces, do
  encaminhamento e do PF, sem aplicar comandos de correção após o boot.

## Limitações e pendências

- [ ] **Executar o teste físico no laboratório**, registrar a versão real,
  interfaces, rede/gateway WAN e MAC real, adaptar os arquivos e repetir
  os três grupos de testes. A simulação não valida cabos, NICs, VLANs,
  políticas de acesso nem desempenho do laboratório.
- O SLIRP do QEMU fornece DHCP/gateway e faz outra tradução para a rede do
  host. As capturas `em1` × `em0` isolam a tradução do FreeBSD. Não use
  latência/throughput da emulação TCG como medida de desempenho físico.
- Um diagnóstico TCP para outro convidado no hub compartilhado encerrou
  com RST. Sua causa não foi confirmada; ele não foi usado como prova de
  NAT. A aprovação de NAT usa ICMP externo com request/reply capturados
  nos dois lados; TCP externo também foi verificado separadamente.
- DHCP da **LAN**, reserva efetivamente concedida, leases e resolução DNS
  permanecem pendentes da etapa de DHCP. O cliente usou IP manual.
- A verificação adicional de DNAT é um teste de conexão TCP, não uma
  validação completa de aplicação HTTP ou troca de mensagens da etapa DNAT.
