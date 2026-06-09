# WSN Final Project 발표 대본 및 데모 체크리스트

## 1. DHCPv6 기반 IPv6/RPL Wireless Sensor Network 구현
- 이번 프로젝트의 목표는 HW2 수준의 단순 센서 수집 네트워크를 명령 기반 WSN으로 확장하는 것이다.
- node 1은 PPP border router, DHCPv6 relay, RPL root로 동작하고, node 2/3/4는 sensor node로 동작한다.
- 핵심은 WSN 내부 mote가 DHCPv6로 IPv6 주소를 자동으로 받고, 그 주소로 직접 접근 가능하게 만든 점이다.

## 2. 프로젝트 요구사항과 구현 범위
- PDF 요구사항은 base station 1개와 sensor nodes, 그리고 command 지원이다.
- 필수 명령은 get-led, set-led, get-voltage, get-temp, get-channel, get-tx-power이다.
- Part-2는 DHCPv6, RPL, TCP, Internet 연결 같은 advanced feature 중 선택할 수 있다.
- 현재 실험 환경에서는 4개 mote가 연결되어 있어 1 gateway + 3 sensor node 구성으로 데모한다.

## 3. 설계 목표
- 기존 HW2는 sensor node가 base station으로 데이터를 보내는 일방향 구조였다.
- 최종 프로젝트에서는 사용자가 node로 명령을 보내고 응답을 받아야 하므로 양방향 통신 구조가 필요했다.
- 강의의 IP narrow waist 개념처럼 IPv6를 공통 계층으로 두면 DHCPv6 주소 할당, command, TCP echo, UDP report 같은 기능을 같은 네트워크 위에서 구성할 수 있다.

## 4. 전체 시스템 구조
- PC는 PPP link를 통해 WSN에 들어가고 fd00:23:42:1::100 주소를 사용한다.
- PC의 dnsmasq가 DHCPv6 server 역할을 하며 fd00:23:42:1::/64 pool에서 주소를 배정한다.
- node 1은 PppRouter이며 PPP와 802.15.4 radio 사이에서 IPv6 packet과 DHCPv6 traffic을 forwarding/relay한다.
- node 2/3/4는 TCPEcho application을 실행하며 DHCPv6 lease로 받은 주소를 사용한다.

## 5. 프로토콜 스택과 강의 내용 연결
- IP 강의에서 배운 DHCPv6와 6LoWPAN adaptation을 사용해 작은 802.15.4 frame 위에 IPv6 packet을 실었다.
- Routing 강의에서 배운 RPL을 사용해 DODAG root와 DAO 기반 route를 구성했다.
- Transport 강의와 연결해 TCP echo와 HTTP command를 구현했고, UDP는 echo와 sensor report에 사용했다.

## 6. IPv6 주소가 없을 때 DHCPv6는 어떻게 시작되는가
- 여기서 중요한 점은 DHCPv6가 TinyOS Active Message로 따로 주소를 나눠주는 구조가 아니라는 것이다.
- sensor node는 아직 global IPv6 주소는 없지만, IEEE 802.15.4 EUI-64 기반 link-local 주소는 사용할 수 있다.
- Dhcp6ClientP는 UDP 546번 포트에 bind하고, SOLICIT 메시지를 ff02::1:2 all DHCP relay/server multicast 주소의 UDP 547번 포트로 보낸다.
- client id는 mote의 EUI-64로 만든 DUID-LL이고, DHCPv6 transaction id로 응답이 자기 요청에 대한 것인지 확인한다.
- REPLY를 받으면 IA_NA/IAADDR option에서 주소를 꺼내 SetIPAddress.setAddress()로 BLIP IPv6 stack에 global address를 등록한다.
- 따라서 bootstrap 순서는 link-local IPv6 -> DHCPv6 multicast/relay -> global IPv6 address -> application traffic이다.

## 7. DHCPv6 주소 할당 메시지 흐름
- sensor node는 SOLICIT 또는 REQUEST를 UDP 546에서 UDP 547로 보낸다.
- node1의 Dhcp6RelayP는 UDP 547에 bind되어 있고, global address가 valid해진 뒤 relay agent로 동작한다.
- node1은 sensor node의 DHCPv6 payload를 RELAY_FORW 메시지로 감싸 PC 쪽 DHCPv6 server로 전달한다.
- PC의 dnsmasq는 fd00:23:42:1::1000부터 fd00:23:42:1::1fff 범위에서 lease를 선택한다.
- server 응답은 RELAY_REPLY로 node1에 돌아오고, node1은 peer_addr을 보고 원래 sensor node에게 ADVERTISE 또는 REPLY를 전달한다.
- sensor node가 REPLY를 처리하면 그때부터 lease file에 보이는 IPv6 주소로 ping6, curl, TCP echo가 가능하다.

## 8. RPL 경로와 TCP/HTTP 동작
- DHCPv6는 주소를 주는 기능이고, RPL은 그 주소까지 packet이 갈 수 있는 경로를 만드는 기능이다.
- node1은 PppRouter에서 RootControl.setRoot()를 호출해 RPL DODAG root가 된다.
- sensor node들은 DIO를 듣고 parent를 선택하며, OF0와 storing mode 설정에 따라 default route와 downward route를 구성한다.
- PC에서 curl을 실행하면 PC -> ppp0 -> node1 -> RPL radio path 순서로 IPv6/TCP packet이 전달된다.
- sensor node에서는 TcpSocketC가 port 80 HTTP server와 port 7 TCP echo를 제공한다.
- 즉 TCP도 Active Message가 아니라 IPv6 위에서 동작하며, DHCPv6로 얻은 주소와 RPL route가 준비된 뒤 정상적으로 연결된다.

## 9. Part-1 Command 지원
- HTTP GET API로 명령을 단순화했다.
- 예를 들어 /get-led는 LED bit 상태를 decimal로 반환하고, /set-led/7은 모든 LED를 켠다.
- /get-temp, /get-voltage, /get-channel, /get-tx-power는 프로젝트 필수 명령에 대응한다.

## 10. 센서 데이터 수집 경로
- sensor node는 10초마다 temperature, humidity, voltage를 읽는다.
- 읽은 값은 cached state로 저장되어 HTTP 요청에 응답할 수 있다.
- 동시에 host의 UDP 7777 포트로 report를 보내도록 구성할 수 있으므로 host에서 주기적 sensor log를 받을 수 있다.

## 11. Part-2 Advanced Feature
- 첫 번째 advanced feature는 DHCPv6 integration이다. node들이 고정 prefix가 아니라 lease 기반 IPv6 주소를 받는다.
- 두 번째는 RPL integration이다. node 1이 root가 되고 sensor node가 DIO/DAO를 통해 route를 만든다.
- 세 번째는 TCP support이다. 각 node는 TCP echo와 HTTP command server를 제공한다.

## 12. 구현 상세
- PppRouter는 PppDaemonC, PppIpv6C, IPForwardingEngineP, RPLRoutingC, Dhcp6C를 연결한다.
- TCPEcho는 UdpSocketC, TcpSocketC, SensirionSht11C, VoltageC를 사용한다.
- TCPEcho는 StaticIPAddressTosIdC 대신 Dhcp6C를 사용해 DHCPv6로 global IPv6 주소를 획득한다.

## 13. 빌드 및 설치 결과
- PppRouter와 TCPEcho 모두 telosb target으로 빌드가 성공했다.
- 설치 매핑은 /dev/ttyUSB1 node 1, /dev/ttyUSB2 node 2, /dev/ttyUSB3 node 3, /dev/ttyUSB0 node 4이다.
- TelosB memory가 제한되어 PppRouter에서는 DHCPv6를 살리기 위해 UDP shell/route dump를 제거했다.

## 14. 데모 시나리오
1. PPP link와 DHCPv6 server 생성
```bash
./start-wsn-dhcpv6.sh /dev/ttyUSB1
```
2. lease 확인
```bash
tail -f wsn-dhcpv6.leases
tail -f wsn-dhcpv6.log
```
3. 명령 테스트
```bash
NODE2=fd00:23:42:1::1001   # 실제 값은 lease file에서 확인
ping6 $NODE2
curl -g http://[$NODE2]/get-led
curl -g http://[$NODE2]/set-led/7
curl -g http://[$NODE2]/get-temp
curl -g http://[$NODE2]/get-voltage
curl -g http://[$NODE2]/get-sensor
```

## 15. 한계와 개선 방향
- 현재 데모는 4개 mote 기준이므로, 장비가 추가되면 node 5를 같은 방식으로 확장할 수 있다.
- DHCPv6 lease를 확인해야 실제 node 주소를 알 수 있으므로, 발표 데모에서는 lease file을 먼저 보여준다.
- get-prr/get-etx, get-route를 실제 per-node link metric 기반으로 확장하면 routing 평가가 더 강해진다.
- FTSP를 붙이면 get-globaltime을 구현할 수 있고, MRHOF/QU-RPL 방식으로 routing 성능 비교도 가능하다.

## 16. 결론
- Part-1의 필수 command를 sensor node에서 HTTP API로 지원했다.
- Part-2로 DHCPv6/IPv6/6LoWPAN/RPL/TCP/PPP를 결합해 remote host가 WSN에 접근하는 구조를 구현했다.
- 강의에서 다룬 IP, DHCPv6, RPL, transport 개념을 실제 TinyOS/TelosB mote에서 동작하는 시스템으로 연결했다.
