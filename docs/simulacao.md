# Preparação do ambiente simulado — issue #1

**Falta executar o teste físico no laboratório.** Os valores abaixo pertencem
exclusivamente à simulação. Não substituem o levantamento da rede real.

## Perfil

| Item | Valor simulado |
|---|---|
| SO das três VMs | FreeBSD 14.5-RELEASE amd64, UFS |
| Roteador WAN | `em0`, DHCP, `192.168.50.101/24` |
| Gateway WAN | `192.168.50.1` (SLIRP do QEMU) |
| Roteador LAN | `em1`, `172.16.0.1/16` |
| Cliente LAN | `em0`, IP manual `172.16.0.10/16`, gateway `172.16.0.1` |
| MAC do cliente LAN | `52:54:00:16:00:10` |
| Máquina WAN | `em0`, IP manual `192.168.50.200/24` |

A interface WAN e a máquina WAN compartilham um hub virtual. A LAN usa outro
segmento Ethernet, conectado apenas ao roteador e ao cliente. As máquinas
LAN/WAN não têm uma segunda interface que permita contornar o roteador.

## Imagem e integridade

Requisitos no host: QEMU (`qemu-system-x86_64`, `qemu-img`), `curl`, `xz`,
`sha256sum` e espaço para a imagem e três overlays. TCG permite executar sem KVM.
Não grave discos, chaves ou capturas de tráfego externo no Git.

```sh
mkdir -p /tmp/freebsd-lab
cd /tmp/freebsd-lab
curl -fLO https://download.freebsd.org/releases/VM-IMAGES/14.5-RELEASE/amd64/Latest/FreeBSD-14.5-RELEASE-amd64-ufs.qcow2.xz
curl -fLO https://download.freebsd.org/releases/VM-IMAGES/14.5-RELEASE/amd64/Latest/CHECKSUM.SHA256
sha256sum FreeBSD-14.5-RELEASE-amd64-ufs.qcow2.xz
```

Compare a saída com a entrada correspondente de `CHECKSUM.SHA256`:
`a027c3a9deafa5af07a8f910c38aed3a58e9adefa18ffb040bc512ecfbc1799a`.
Somente depois de conferir, descompacte e crie os discos diferenciais:

```sh
xz -dk FreeBSD-14.5-RELEASE-amd64-ufs.qcow2.xz
mv FreeBSD-14.5-RELEASE-amd64-ufs.qcow2 base.qcow2
for vm in router lan wan; do
  qemu-img create -f qcow2 -F qcow2 -b /tmp/freebsd-lab/base.qcow2 "$vm.qcow2"
done
```

## Inicialização das três VMs

Execute no diretório `/tmp/freebsd-lab`, em três terminais. Inicie o roteador
primeiro. Os sockets TCP ficam vinculados ao loopback do host. Os adaptadores
`e1000` aparecem como `em0`/`em1` no FreeBSD.

Roteador:

```sh
qemu-system-x86_64 -accel tcg -m 512 -smp 1 -display curses -monitor none \
  -serial none -drive file=router.qcow2,format=qcow2,if=virtio \
  -netdev user,id=upstream,net=192.168.50.0/24,host=192.168.50.1,dns=192.168.50.3,dhcpstart=192.168.50.100 \
  -netdev hubport,id=upstreamport,hubid=0,netdev=upstream \
  -netdev socket,id=wanpeer,listen=127.0.0.1:15150 \
  -netdev hubport,id=wanpeerport,hubid=0,netdev=wanpeer \
  -netdev hubport,id=routerwan,hubid=0 \
  -device e1000,netdev=routerwan,mac=52:54:00:50:00:02 \
  -netdev socket,id=lanpeer,listen=127.0.0.1:15160 \
  -device e1000,netdev=lanpeer,mac=52:54:00:16:00:01
```

Cliente LAN:

```sh
qemu-system-x86_64 -accel tcg -m 512 -smp 1 -display curses -monitor none \
  -serial none -drive file=lan.qcow2,format=qcow2,if=virtio \
  -netdev socket,id=peer,connect=127.0.0.1:15160 \
  -device e1000,netdev=peer,mac=52:54:00:16:00:10
```

Máquina WAN:

```sh
qemu-system-x86_64 -accel tcg -m 512 -smp 1 -display curses -monitor none \
  -serial none -drive file=wan.qcow2,format=qcow2,if=virtio \
  -netdev socket,id=peer,connect=127.0.0.1:15150 \
  -device e1000,netdev=peer,mac=52:54:00:50:00:20
```

O primeiro boot usa o console VGA no terminal (`-display curses`), pois a
imagem UFS padrão não habilita um login serial por padrão. O IP DHCP pode
variar conforme a ordem de boot; confira `ifconfig em0` e use o IP observado
nos testes.

Use o console local da imagem oficial para configurar cada VM. Ao terminar,
execute `shutdown -p now` em cada uma antes de descartar seus discos.

## Levantamento e adaptação para o laboratório

No roteador, registre `freebsd-version -kru`, `ifconfig -l`, `ifconfig` e
`route -n get default`. Confirme os cabos/adaptadores WAN e LAN pelo MAC e pelo
segmento conectado, não apenas pela ordem dos nomes. Verifique o prefixo real
`192.168.X.0/24` e se o gateway é mesmo `192.168.X.1`.

No cliente de testes, obtenha o MAC com `ifconfig` (FreeBSD) ou `ip link`
(Linux). Atualize as interfaces em `config/rc.conf` e `config/pf.conf`,
`dhcpd_ifaces` no `rc.conf`, a reserva de MAC em `config/dhcpd.conf` e a
versão/topologia no README. A LAN permanece `172.16.0.0/16`.

A reserva DHCP está fora do pool dinâmico. Nesta etapa, o cliente usa IP
manual: a distribuição DHCP da LAN será validada na etapa própria.

## Fontes

- [Imagens oficiais do FreeBSD](https://download.freebsd.org/releases/VM-IMAGES/14.5-RELEASE/amd64/Latest/)
- [Instalação do FreeBSD](https://docs.freebsd.org/en/books/handbook/bsdinstall/)
- [Rede no QEMU](https://www.qemu.org/docs/master/system/devices/net.html)
