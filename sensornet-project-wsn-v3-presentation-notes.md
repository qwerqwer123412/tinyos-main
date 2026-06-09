# WSN Final Project 발표 대본 및 데모 체크리스트

## 1. IPv6/RPL 기반 Wireless Sensor Network 구현
- 이번 프로젝트의 목표는 HW2 수준의 단순 센서 수집 네트워크를 명령 기반 WSN으로 확장하는 것이다.
- node 1은 PPP border router와 RPL root로 동작하고, node 2/3/4는 sensor node로 동작한다.
- 핵심은 WSN 내부 mote를 IPv6 주소로 직접 접근 가능하게 만든 점이다.

## 2. 프로젝트 요구사항과 구현 범위
- PDF 요구사항은 base station 1개와 sensor nodes, 그리고 command 지원이다.
- 필수 명령은 get-led, set-led, get-voltage, get-temp, get-channel, get-tx-power이다.
- Part-2는 RPL, TCP, Internet 연결 같은 advanced feature 중 선택할 수 있다.
- 현재 실험 환경에서는 4개 mote가 연결되어 있어 1 gateway + 3 sensor node 구성으로 데모한다.

## 3. 설계 목표
- 기존 HW2는 sensor node가 base station으로 데이터를 보내는 일방향 구조였다.
- 최종 프로젝트에서는 사용자가 node로 명령을 보내고 응답을 받아야 하므로 양방향 통신 구조가 필요했다.
- 강의의 IP narrow waist 개념처럼 IPv6를 공통 계층으로 두면 command, TCP echo, UDP report 같은 기능을 같은 네트워크 위에서 구성할 수 있다.

## 4. 전체 시스템 구조
- PC는 PPP link를 통해 WSN에 들어가고 fec0::100 주소를 사용한다.
- node 1은 PppRouter이며 PPP와 802.15.4 radio 사이에서 IPv6 packet을 forwarding한다.
- node 2/3/4는 TCPEcho application을 실행하며 각각 fec0::2, fec0::3, fec0::4 주소를 가진다.

## 5. 프로토콜 스택과 강의 내용 연결
- IP 강의에서 배운 6LoWPAN adaptation을 사용해 작은 802.15.4 frame 위에 IPv6 packet을 실었다.
- Routing 강의에서 배운 RPL을 사용해 DODAG root와 DAO 기반 route를 구성했다.
- Transport 강의와 연결해 TCP echo와 HTTP command를 구현했고, UDP는 echo와 sensor report에 사용했다.

## 6. Part-1 Command 지원
- HTTP GET API로 명령을 단순화했다.
- 예를 들어 /get-led는 LED bit 상태를 decimal로 반환하고, /set-led/7은 모든 LED를 켠다.
- /get-temp, /get-voltage, /get-channel, /get-tx-power는 프로젝트 필수 명령에 대응한다.
- 하지만, 일반 HTTP response를 기대할순 없음 -> payload크기가 너무 작기 때문에.. 

## 7. 센서 데이터 수집 경로
- sensor node는 10초마다 temperature, humidity, voltage를 읽는다.
- 읽은 값은 cached state로 저장되어 HTTP 요청에 응답할 수 있다.
- 동시에 fec0::100:7777로 UDP report를 보내므로 host에서 주기적 sensor log를 받을 수 있다.

## 8. Part-2 Advanced Feature
- 첫 번째 advanced feature는 RPL integration이다. node 1이 root가 되고 sensor node가 DIO/DAO를 통해 route를 만든다.
- 두 번째는 Internet-facing access이다. PPP link를 통해 외부 host가 WSN node의 IPv6 주소로 접근한다.
- 세 번째는 TCP support이다. 각 node는 TCP echo와 HTTP command server를 제공한다.

## 9. 구현 상세
- PppRouter는 PppDaemonC, PppIpv6C, IPForwardingEngineP, RPLRoutingC를 연결한다.
- TCPEcho는 UdpSocketC, TcpSocketC, SensirionSht11C, VoltageC를 사용한다.
- StaticIPAddressTosIdC를 사용해 TOS_NODE_ID가 IPv6 주소의 마지막 부분이 되도록 했다.

## 10. 빌드 및 설치 결과
- PppRouter와 TCPEcho 모두 telosb target으로 빌드가 성공했다.
- 설치 매핑은 /dev/ttyUSB1 node 1, /dev/ttyUSB2 node 2, /dev/ttyUSB3 node 3, /dev/ttyUSB0 node 4이다.
- TelosB memory가 제한되어 PppRouter의 full UDPShell 대신 가벼운 route dump component를 넣었다.

## 11. 데모 시나리오
1. PPP link 생성
```bash
sudo pppd debug passive noauth nodetach 115200 /dev/ttyUSB1 nocrtscts nocdtrcts lcp-echo-interval 0 noccp noip ipv6 ::23,::24
sudo ip -6 addr add fec0::100/64 dev ppp0
```
2. 연결 확인
```bash
ping6 fec0::1
ping6 fec0::2
ping6 fec0::3
ping6 fec0::4
```
3. 명령 테스트
```bash
curl -g http://[fec0::2]/get-led
curl -g http://[fec0::2]/set-led/7
curl -g http://[fec0::2]/get-temp
curl -g http://[fec0::2]/get-voltage
curl -g http://[fec0::3]/get-sensor
curl -g http://[fec0::4]/get-stats
printf x | nc -6u -w3 fec0::1 2000
```

## 12. 한계와 개선 방향
- 현재 데모는 4개 mote 기준이므로, 장비가 추가되면 node 5를 같은 방식으로 확장할 수 있다.
- get-prr/get-etx, get-route를 실제 per-node link metric 기반으로 확장하면 routing 평가가 더 강해진다.
- FTSP를 붙이면 get-globaltime을 구현할 수 있고, MRHOF/QU-RPL 방식으로 routing 성능 비교도 가능하다.

## 13. 결론
- Part-1의 필수 command를 sensor node에서 HTTP API로 지원했다.
- Part-2로 IPv6/6LoWPAN/RPL/TCP/PPP를 결합해 remote host가 WSN에 접근하는 구조를 구현했다.
- 강의에서 다룬 IP, RPL, transport 개념을 실제 TinyOS/TelosB mote에서 동작하는 시스템으로 연결했다.
