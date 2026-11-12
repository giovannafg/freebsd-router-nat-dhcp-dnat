#!/bin/sh
#
# scripts/diagnostico.sh - mostra o estado do roteador (somente leitura).
#
# Uso, como root, no roteador FreeBSD:
#   sh scripts/diagnostico.sh             # tudo
#   sh scripts/diagnostico.sh interfaces  # papéis, IPs, rotas, encaminhamento
#   sh scripts/diagnostico.sh pf          # NAT/DNAT, regras com contadores, estados
#   sh scripts/diagnostico.sh dhcp        # serviço, log e leases
#
# ATENÇÃO: a saída contém IPs e MACs reais. Guarde em docs/evidencias/local/
# (ignorada pelo Git) e não publique no GitHub sem trocar esses valores.

set -u

[ "$(id -u)" -eq 0 ] || { echo "execute como root" >&2; exit 1; }

WAN=$(sysrc -n roteador_wan_if 2>/dev/null)
LAN=$(sysrc -n roteador_lan_if 2>/dev/null)
LEASES=/var/db/dhcpd/dhcpd.leases
[ -f "$LEASES" ] || LEASES=/var/db/dhcpd.leases

titulo() { printf '\n===== %s =====\n' "$*"; }

info_iface() {
	papel=$1 i=$2
	if [ -z "$i" ]; then
		echo "$papel: (não definido; rode scripts/instalar.sh)"
		return
	fi
	if ! ifconfig "$i" >/dev/null 2>&1; then
		echo "$papel: $i NÃO EXISTE (adaptador/celular desconectado ou com outro nome?)"
		return
	fi
	ifconfig "$i" | awk -v p="$papel" -v i="$i" '
		$1 == "ether"   { mac = $2 }
		$1 == "inet"    { ip = ip " " $2 }
		$1 == "status:" { st = $2 }
		END { printf "%s: %-8s MAC %s  IP%s  status %s\n", p, i, mac, (ip == "" ? " (nenhum)" : ip), st }'
}

sistema() {
	titulo "Sistema"
	echo "FreeBSD $(freebsd-version -k) ($(uname -m)) - $(date)"
}

interfaces() {
	titulo "Interfaces"
	info_iface WAN "$WAN"
	info_iface LAN "$LAN"
	sysctl net.inet.ip.forwarding
	titulo "Rotas IPv4"
	netstat -rn -f inet
}

pf() {
	titulo "PF"
	pfctl -s info 2>/dev/null | head -1
	titulo "NAT e DNAT (pfctl -sn)"
	pfctl -sn 2>/dev/null
	titulo "Regras com contadores (pfctl -vsr)"
	pfctl -vsr 2>/dev/null
	titulo "Estados ativos (pfctl -ss)"
	pfctl -ss 2>/dev/null
}

dhcp() {
	titulo "Servidor DHCP"
	service isc-dhcpd status
	echo "Interfaces atendidas: $(sysrc -n dhcpd_ifaces 2>/dev/null)"
	titulo "Log (/var/log/dhcpd.log, últimas concessões)"
	if [ -f /var/log/dhcpd.log ]; then
		grep -E 'DHCP(DISCOVER|OFFER|REQUEST|ACK|NAK|RELEASE|INFORM)' /var/log/dhcpd.log | tail -20
	else
		echo "(sem /var/log/dhcpd.log)"
	fi
	titulo "Leases do pool dinâmico ($LEASES)"
	echo "(a reserva fixa 172.16.0.10 não aparece aqui, só no log acima)"
	if [ -f "$LEASES" ]; then
		awk '
			{ sub(/;$/, "") }
			/^lease /               { ip = $2; st = ""; hw = ""; nome = ""; fim = "" }
			/^  ends /              { fim = $3 " " $4 " UTC" }
			/^  binding state /     { st = $3 }
			/^  hardware ethernet / { hw = $3 }
			/^  client-hostname /   { nome = $2 }
			/^}/ { if (ip != "") ult[ip] = sprintf("%-15s %-8s %-18s %-20s até %s", ip, st, hw, nome, fim); ip = "" }
			END  { n = 0; for (k in ult) { print ult[k]; n++ } if (n == 0) print "(nenhuma lease dinâmica)" }
		' "$LEASES"
	else
		echo "(arquivo de leases ainda não existe)"
	fi
}

case ${1:-tudo} in
tudo)       sistema; interfaces; pf; dhcp ;;
interfaces) interfaces ;;
pf)         pf ;;
dhcp)       dhcp ;;
*)          echo "uso: sh $0 [tudo|interfaces|pf|dhcp]" >&2; exit 2 ;;
esac
