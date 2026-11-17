#!/bin/sh
#
# scripts/instalar.sh - aplica as configurações do repositório no roteador.
#
# Uso, como root, no roteador FreeBSD (a partir da raiz do repositório):
#   sh scripts/instalar.sh -n    # só verifica e valida; não altera nada
#   sh scripts/instalar.sh       # valida, faz backup e aplica
#   sh scripts/instalar.sh -c outro.conf
#
# Lê config/router.conf (não versionado; ver config/router.conf.exemplo).
# Gera pf.conf e dhcpd.conf com os valores reais numa pasta temporária,
# valida os dois (pfctl -nf, dhcpd -t) e só então instala. Se qualquer
# validação falhar, nada é alterado.

set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
CONF="$REPO/config/router.conf"
SO_VALIDAR=0

uso() { echo "uso: sh $0 [-n] [-c arquivo]" >&2; exit 2; }
while getopts nc: opt; do
	case $opt in
	n) SO_VALIDAR=1 ;;
	c) CONF=$OPTARG ;;
	*) uso ;;
	esac
done

msg()   { printf '==> %s\n' "$*"; }
aviso() { printf 'AVISO: %s\n' "$*" >&2; }
erro()  { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = FreeBSD ] || erro "este script roda no roteador FreeBSD"
[ "$(id -u)" -eq 0 ] || erro "execute como root"
[ -f "$CONF" ] || erro "crie $CONF: cp config/router.conf.exemplo config/router.conf"

LAN_IF= LAN_MAC= WAN_IF= WAN_MAC= WAN_CONFIG=DHCP WAN_GATEWAY=
CELULAR= CLIENTE_MAC= DNS_SERVERS=
. "$CONF"

DHCPD=/usr/local/sbin/dhcpd
MAC_EXEMPLO_CLIENTE="02:00:00:00:00:10"

# --- funções auxiliares ----------------------------------------------------

minusc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }

mac_valido() {
	printf '%s' "$1" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
}

mac_de() {
	ifconfig "$1" 2>/dev/null | awk '$1 == "ether" { print $2; exit }'
}

# Interfaces Ethernet físicas/USB (exclui loopback, pf, Wi-Fi, túneis...).
ifaces_ethernet() {
	for i in $(ifconfig -l); do
		case $i in
		lo*|pflog*|pfsync*|enc*|wlan*|bridge*|tun*|tap*|vlan*|lagg*|gif*|stf*)
			continue ;;
		esac
		if [ -n "$(mac_de "$i")" ]; then
			echo "$i"
		fi
	done
}

iface_por_mac() {
	alvo=$(minusc "$1")
	for i in $(ifaces_ethernet); do
		if [ "$(minusc "$(mac_de "$i")")" = "$alvo" ]; then
			echo "$i"
			return 0
		fi
	done
	return 0
}

listar_ifaces() {
	echo "Interfaces Ethernet encontradas:"
	for i in $(ifaces_ethernet); do
		st=$(ifconfig "$i" | awk '$1 == "status:" { $1 = ""; sub(/^ /, ""); print; exit }')
		printf '   %-8s %s  %s\n' "$i" "$(mac_de "$i")" "${st:-?}"
	done
}

# --- 1. conferir config/router.conf ------------------------------------------

msg "Lendo $CONF"

case $CELULAR in
android) MOD_CELULAR=if_urndis ;;
iphone)  MOD_CELULAR=if_ipheth ;;
"")      MOD_CELULAR= ;;
*)       erro "CELULAR deve ser android, iphone ou vazio (está: $CELULAR)" ;;
esac

mac_valido "$CLIENTE_MAC" || erro "CLIENTE_MAC inválido: '$CLIENTE_MAC'"
if [ "$(minusc "$CLIENTE_MAC")" = "$MAC_EXEMPLO_CLIENTE" ]; then
	aviso "CLIENTE_MAC ainda é o valor de exemplo; o notebook Linux não vai receber 172.16.0.10"
fi
[ -z "$LAN_MAC" ] || mac_valido "$LAN_MAC" || erro "LAN_MAC inválido: '$LAN_MAC'"
[ -z "$WAN_MAC" ] || mac_valido "$WAN_MAC" || erro "WAN_MAC inválido: '$WAN_MAC'"

printf '%s' "$DNS_SERVERS" | grep -Eq '^[0-9.]+(, *[0-9.]+)*$' ||
	erro "DNS_SERVERS deve ser uma lista de IPs separada por vírgula (está: '$DNS_SERVERS')"

case $WAN_CONFIG in
DHCP|SYNCDHCP) ;;
inet\ *) [ -n "$WAN_GATEWAY" ] || erro "WAN_CONFIG com IP fixo exige WAN_GATEWAY" ;;
*) erro "WAN_CONFIG deve ser DHCP ou 'inet <ip> netmask <máscara>'" ;;
esac

# --- 2. identificar as interfaces --------------------------------------------

msg "Identificando interfaces"

if [ -n "$MOD_CELULAR" ]; then
	kldload -n "$MOD_CELULAR" 2>/dev/null ||
		aviso "não carregou $MOD_CELULAR (driver do celular); a ancoragem USB pode não aparecer"
fi

if [ -z "$LAN_IF" ]; then
	[ -n "$LAN_MAC" ] || erro "defina LAN_MAC (ou LAN_IF) em $CONF"
	LAN_IF=$(iface_por_mac "$LAN_MAC")
	if [ -z "$LAN_IF" ]; then
		listar_ifaces >&2
		erro "nenhuma interface com LAN_MAC=$LAN_MAC (o adaptador USB da LAN está conectado?)"
	fi
elif [ -n "$LAN_MAC" ] && [ "$(minusc "$(mac_de "$LAN_IF")")" != "$(minusc "$LAN_MAC")" ]; then
	aviso "LAN_IF=$LAN_IF não tem o MAC LAN_MAC=$LAN_MAC; usando LAN_IF"
fi

if [ -z "$WAN_IF" ] && [ -n "$WAN_MAC" ]; then
	WAN_IF=$(iface_por_mac "$WAN_MAC")
	if [ -z "$WAN_IF" ]; then
		listar_ifaces >&2
		erro "nenhuma interface com WAN_MAC=$WAN_MAC"
	fi
fi

if [ -z "$WAN_IF" ]; then
	candidatas=
	for i in $(ifaces_ethernet); do
		if [ "$i" != "$LAN_IF" ]; then
			candidatas="$candidatas $i"
		fi
	done
	# shellcheck disable=SC2086
	set -- $candidatas
	if [ $# -ne 1 ]; then
		listar_ifaces >&2
		erro "não dá para escolher a WAN sozinho (candidatas:${candidatas:- nenhuma}); defina WAN_IF ou WAN_MAC em $CONF"
	fi
	WAN_IF=$1
fi

ifconfig "$LAN_IF" >/dev/null 2>&1 || erro "interface LAN '$LAN_IF' não existe"
ifconfig "$WAN_IF" >/dev/null 2>&1 || erro "interface WAN '$WAN_IF' não existe"
[ "$LAN_IF" != "$WAN_IF" ] || erro "WAN e LAN apontam para a mesma interface ($LAN_IF)"

WAN_IP_ATUAL=$(ifconfig "$WAN_IF" inet 2>/dev/null | awk '$1 == "inet" { print $2; exit }')
case $WAN_IP_ATUAL in
172.16.*) erro "a WAN ($WAN_IF) está em $WAN_IP_ATUAL, dentro da LAN 172.16.0.0/16: conflito de rede" ;;
esac

printf '   WAN: %-8s MAC %s  IP atual %s\n' "$WAN_IF" "$(mac_de "$WAN_IF")" "${WAN_IP_ATUAL:-(nenhum)}"
printf '   LAN: %-8s MAC %s  -> 172.16.0.1/16\n' "$LAN_IF" "$(mac_de "$LAN_IF")"

# --- 3. pacote do DHCP ----------------------------------------------------------

if [ ! -x "$DHCPD" ]; then
	if [ "$SO_VALIDAR" -eq 1 ]; then
		erro "isc-dhcp44-server não instalado: rode 'pkg install isc-dhcp44-server' (precisa de internet na WAN)"
	fi
	msg "Instalando isc-dhcp44-server (precisa de internet na WAN)"
	env ASSUME_ALWAYS_YES=yes pkg install isc-dhcp44-server
fi

# --- 4. gerar e validar os arquivos ----------------------------------------------

msg "Gerando e validando pf.conf e dhcpd.conf"

TMP=$(mktemp -d /tmp/roteador.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

sed -e "s|^ext_if = .*|ext_if = \"$WAN_IF\"|" \
    -e "s|^int_if = .*|int_if = \"$LAN_IF\"|" \
    "$REPO/config/pf.conf" > "$TMP/pf.conf"
grep -q "^ext_if = \"$WAN_IF\"\$" "$TMP/pf.conf" &&
	grep -q "^int_if = \"$LAN_IF\"\$" "$TMP/pf.conf" ||
	erro "não encontrei as linhas ext_if/int_if em config/pf.conf"

sed -e "s|^option domain-name-servers .*|option domain-name-servers $DNS_SERVERS;|" \
    -e "s|^\([[:space:]]*hardware ethernet\) [^;]*;.*|\1 $CLIENTE_MAC;|" \
    "$REPO/config/dhcpd.conf" > "$TMP/dhcpd.conf"
grep -q "hardware ethernet $CLIENTE_MAC;" "$TMP/dhcpd.conf" &&
	grep -q "^option domain-name-servers $DNS_SERVERS;" "$TMP/dhcpd.conf" ||
	erro "não encontrei as linhas de DNS/MAC em config/dhcpd.conf"

kldload -n pf
pfctl -nf "$TMP/pf.conf" || erro "pf.conf inválido (nada foi alterado)"
if ! saida=$("$DHCPD" -t -cf "$TMP/dhcpd.conf" 2>&1); then
	printf '%s\n' "$saida" >&2
	erro "dhcpd.conf inválido (nada foi alterado)"
fi
echo "   pf.conf e dhcpd.conf válidos"

if [ "$SO_VALIDAR" -eq 1 ]; then
	msg "Verificação concluída (-n): nada foi alterado"
	exit 0
fi

# --- 5. backup -------------------------------------------------------------------

BACKUP=/var/backups/roteador-$(date +%Y%m%d-%H%M%S)
msg "Backup dos arquivos atuais em $BACKUP"
mkdir -p "$BACKUP"
for f in /etc/rc.conf /etc/pf.conf /usr/local/etc/dhcpd.conf /etc/syslog.conf \
         /etc/syslog.d/dhcpd.conf /etc/newsyslog.conf.d/dhcpd.conf /boot/loader.conf; do
	if [ -f "$f" ]; then
		cp -p "$f" "$BACKUP/$(echo "$f" | sed 's|^/||; s|/|_|g')"
	fi
done

# --- 6. instalar arquivos ------------------------------------------------------------

msg "Instalando arquivos de configuração"
install -m 600 "$TMP/pf.conf" /etc/pf.conf
install -m 644 "$TMP/dhcpd.conf" /usr/local/etc/dhcpd.conf
mkdir -p /etc/syslog.d /etc/newsyslog.conf.d
install -m 644 "$REPO/config/syslog-dhcpd.conf" /etc/syslog.d/dhcpd.conf
install -m 644 "$REPO/config/newsyslog-dhcpd.conf" /etc/newsyslog.conf.d/dhcpd.conf
if ! grep -Eq '^[[:space:]]*include[[:space:]]+/etc/syslog\.d' /etc/syslog.conf; then
	printf 'include\t\t\t/etc/syslog.d\n' >> /etc/syslog.conf
fi
touch /var/log/dhcpd.log
chmod 644 /var/log/dhcpd.log

# --- 7. rc.conf e loader.conf ----------------------------------------------------------

msg "Atualizando /etc/rc.conf"

# Se os papéis mudaram desde a última execução, remove a configuração antiga.
ANTIGAS="$(sysrc -n roteador_wan_if 2>/dev/null || true) $(sysrc -n roteador_lan_if 2>/dev/null || true)"
for i in $ANTIGAS; do
	if [ "$i" != "$WAN_IF" ] && [ "$i" != "$LAN_IF" ]; then
		sysrc -x "ifconfig_$i" >/dev/null 2>&1 || true
	fi
done
# A imagem/instalação pode pedir DHCP em todas as interfaces (inclusive na LAN).
sysrc -x ifconfig_DEFAULT >/dev/null 2>&1 || true

sysrc hostname=roteador \
	roteador_wan_if="$WAN_IF" roteador_lan_if="$LAN_IF" \
	"ifconfig_$WAN_IF=$WAN_CONFIG" \
	"ifconfig_$LAN_IF=inet 172.16.0.1 netmask 255.255.0.0" \
	gateway_enable=YES \
	pf_enable=YES pf_rules=/etc/pf.conf pflog_enable=YES \
	dhcpd_enable=YES dhcpd_ifaces="$LAN_IF"

case $WAN_CONFIG in
DHCP|SYNCDHCP) sysrc -x defaultrouter >/dev/null 2>&1 || true ;;
*)             sysrc defaultrouter="$WAN_GATEWAY" ;;
esac

if [ -n "$MOD_CELULAR" ]; then
	sysrc -f /boot/loader.conf "${MOD_CELULAR}_load=YES"
fi

# --- 8. aplicar sem reiniciar --------------------------------------------------------------

msg "Aplicando rede, PF, syslog e DHCP"
sysctl net.inet.ip.forwarding=1 >/dev/null
service netif restart "$LAN_IF"
service netif restart "$WAN_IF"
case $WAN_CONFIG in
DHCP|SYNCDHCP) ;;
*) service routing restart ;;
esac
service syslogd restart
service pflog restart
service pf restart
pfctl -q -F states    # descarta estados criados por regras antigas
service isc-dhcpd restart

msg "Pronto. Backup em $BACKUP"
echo "    Confira com: sh scripts/diagnostico.sh"
echo "    Para garantir que tudo sobe sozinho, reinicie (reboot) e confira de novo."
