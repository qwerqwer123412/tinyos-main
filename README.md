# WSN Demo

TinyOS 기반 WSN 데모 앱입니다. 라우터 1대와 센서노드 3대를 static IPv6 + RPL로 연결하고, 각 센서노드는 HTTP 또는 UDP 명령으로 센서값 조회와 LED 제어를 제공합니다.

## 구성

| 장비 | 앱 | USB 포트 | IPv6 주소 |
|---|---|---|---|
| node1 | `PppRouter` | `/dev/ttyUSB0` | `fd00:23:42:1::1` |
| node2 | `TCPEcho` | `/dev/ttyUSB1` | `fd00:23:42:1::2` |
| node3 | `TCPEcho` | `/dev/ttyUSB2` | `fd00:23:42:1::3` |
| node4 | `TCPEcho` | `/dev/ttyUSB3` | `fd00:23:42:1::4` |
| PC `ppp0` | - | - | `fd00:23:42:1::100/64` |

무선 설정:

```text
CC2420 channel 26
local group 0xCA
tx power 31
```

## 관련 경로

| 경로 | 내용 |
|---|---|
| `PppRouter/` | node1 라우터 앱 |
| `TCPEcho/` | node2/3/4 센서노드 앱, HTTP/UDP API 구현 |
| `start-wsn-static.sh` | PC 쪽 PPP static IPv6 시작 |
| `stop-wsn-static.sh` | PC 쪽 PPP 종료 |
| `../tos/lib/net/blip/IPDispatch.h` | BLIP fragment pool 기본값 |
| `../tools/tinyos/c/blip/libtcp/tcplib.c` | BLIP TCP 송신 처리 |
| `../tools/tinyos/c/blip/lib6lowpan/ip_malloc.c` | BLIP heap allocator |
| `인수인계.md` | 상세 인수인계 및 수정 이력 |

## 빌드 및 플래시

모든 명령은 `/home/nsl/tinyos-main/apps`에서 실행합니다.

### 1. 라우터 플래시

```bash
cd /home/nsl/tinyos-main/apps
make -C PppRouter telosb
sudo make -C PppRouter telosb reinstall,1 bsl,/dev/ttyUSB0
```

### 2. 센서노드 플래시

```bash
make -C TCPEcho telosb
sudo make -C TCPEcho telosb reinstall,2 bsl,/dev/ttyUSB1
sudo make -C TCPEcho telosb reinstall,3 bsl,/dev/ttyUSB2
sudo make -C TCPEcho telosb reinstall,4 bsl,/dev/ttyUSB3
```

### 3. PPP 시작

```bash
sudo ./start-wsn-static.sh /dev/ttyUSB0
sleep 70
```

노드가 재부팅되거나 새로 플래시된 뒤 RPL 망에 합류하는 데 60~70초 정도 걸립니다. 이 시간 전에 `ping`이나 `curl`을 실행하면 실패할 수 있습니다.

### 4. 연결 확인

```bash
ip -6 addr show ppp0
ping6 -c1 fd00:23:42:1::2
ping6 -c1 fd00:23:42:1::3
ping6 -c1 fd00:23:42:1::4
```

PPP 종료:

```bash
sudo ./stop-wsn-static.sh
```

## HTTP API

HTTP는 포트 80을 사용합니다. 응답은 HTTP status/header 없이 body만 반환하므로 `curl --http0.9` 옵션이 필요합니다.

아래 예시는 node4 기준입니다. 다른 노드는 주소의 `::4`를 `::2` 또는 `::3`으로 바꾸면 됩니다.

```bash
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-temp'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-voltage'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-humidity'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-sensor'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-led'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/set-led/7'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/set-led/0'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-channel'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-tx-power'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-time'
curl --http0.9 -g --max-time 9 'http://[fd00:23:42:1::4]/get-stats'
```

대표 명령:

| 엔드포인트 | 내용 |
|---|---|
| `/get-temp` | 온도 조회 |
| `/get-voltage` | 전압 조회 |
| `/get-humidity` | 습도 조회 |
| `/get-sensor` | 온도, 습도, 전압 한 번에 조회 |
| `/get-led` | LED 상태 조회 |
| `/set-led/N` | LED 설정. `N`은 0~7, 하위 3비트가 LED 3개 |
| `/get-channel` | 무선 채널 조회 |
| `/get-tx-power` | 송신 출력 조회 |
| `/get-time` | 가동시간 조회 |
| `/get-stats` | 요청/센서/UDP/heap 통계 조회 |

응답 예:

```text
node 4, temp 25.65 C (raw 6525), seq 9
node 4, hum 33.93 % (raw 1026), seq 9
node 4, batt 2.49 V (raw 3410), seq 9
node 4, seq 8, temp 25.66 C (raw 6526), hum 33.93 % (raw 1026), batt 2.49 V (raw 3409)
node 4, led 7
node 4, requests 41, ok 40, errors 0, sensor_seq 29, samples 29, udp_sent 29, udp_fail 0, heap 1348
```

센서 변환식:

```text
temp[C] = -39.6 + 0.01 * raw
hum[%]  = -2.0468 + 0.0367 * raw - 1.5955e-6 * raw^2
batt[V] = raw / 4096 * 3.0
```

## UDP API

UDP는 포트 7777을 사용합니다. HTTP보다 안정적이므로 백업 또는 비교용으로 유용합니다.

```bash
printf 'get-temp\n'     | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'get-voltage\n'  | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'get-humidity\n' | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'get-sensor\n'   | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'get-led\n'      | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'set-led/7\n'    | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'get-channel\n'  | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'get-tx-power\n' | nc -6 -u -w3 fd00:23:42:1::4 7777
printf 'get-stats\n'    | nc -6 -u -w3 fd00:23:42:1::4 7777
```

HTTP와 명령/응답 포맷은 동일합니다.

## curl 실패 시

BLIP TCP는 단일 소켓이라 무선 손실이나 직전 연결 정리 상태에 따라 가끔 `Connection reset by peer` 또는 timeout이 날 수 있습니다. 노드가 죽은 것이 아니면 몇 초 뒤 재시도하면 됩니다.

편의 함수:

```bash
g() { for i in 1 2 3 4 5 6; do o=$(curl -s --http0.9 -g --max-time 9 "http://[fd00:23:42:1::4]/$1"); [ -n "$o" ] && { echo "$o"; return; }; sleep 7; done; echo "(failed: retry later)"; }

g get-sensor
g get-led
g set-led/7
g get-stats
```

요청을 연속으로 빠르게 보내면 단일 TCP 소켓이 묶여 일부 요청이 실패할 수 있습니다. 요청 사이에는 몇 초 간격을 두는 것이 좋습니다.

## 문제 해결

노드가 응답하지 않을 때:

```bash
ping6 -c1 fd00:23:42:1::4
printf 'get-stats\n' | nc -6 -u -w3 fd00:23:42:1::4 7777
```

UDP가 응답하면 노드는 살아 있고 HTTP/TCP 쪽만 일시적으로 실패한 상태일 가능성이 큽니다.

PPP를 다시 시작할 때:

```bash
sudo ./stop-wsn-static.sh
sudo ./start-wsn-static.sh /dev/ttyUSB0
sleep 70
```

해당 노드만 다시 플래시할 때:

```bash
make -C TCPEcho telosb
sudo make -C TCPEcho telosb reinstall,4 bsl,/dev/ttyUSB3
sleep 70
```

## 구현 메모

이번 데모에서 핵심적으로 해결한 문제는 다음과 같습니다.

1. TCP 요청 몇 번 후 노드가 영구 정지하던 문제를 `TCPEcho`의 `N_FRAGMENTS=20` 설정으로 완화했습니다.
2. `IPDispatch.h`는 앱별 `-D N_FRAGMENTS` 오버라이드를 허용하도록 조정했습니다.
3. `tcplib_send()`에서 즉시 송신으로 인한 수신 콜백 재진입을 제거했습니다.
4. `ip_malloc.c`에서 0길이 cell이 생기지 않도록 split 방어를 추가했습니다.
5. HTTP 응답 길이가 홀수일 때 BLIP TCP 송신 경로에서 깨지는 문제를 `HttpdP.nc`에서 짝수 길이 패딩으로 우회했습니다.
6. 센서 `readDone` 유실 시 샘플링이 멈추지 않도록 센서 워치독을 추가했습니다.

상세한 배경과 검증 결과는 `인수인계.md`를 참고합니다.
