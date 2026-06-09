module HttpdP {
  uses {
    interface Leds;
    interface Boot;
    interface Tcp;
    interface UDP as SensorUdp;
    interface Timer<TMilli> as CloseTimer;
    interface Timer<TMilli> as SensorTimer;
    interface LocalTime<TMilli>;
    interface Read<uint16_t> as TempRead;
    interface Read<uint16_t> as HumRead;
    interface Read<uint16_t> as BattRead;
  }
} implementation {

#ifndef WSN_RADIO_CHANNEL
#define WSN_RADIO_CHANNEL 26
#endif

#ifndef CC2420_DEF_RFPOWER
#define CC2420_DEF_RFPOWER 31
#endif

  enum {
    S_IDLE,
    S_CONNECTED,
    S_REQUEST_PRE,
    S_REQUEST,
    S_HEADER,

    HTTP_GET,
    HTTP_OTHER,

    SENSOR_NONE,
    SENSOR_TEMP,
    SENSOR_HUM,
    SENSOR_BATT,

    SENSOR_UDP_PORT = 7777,
    SENSOR_PERIOD_MILLI = 10000,

    REQ_BUF_LEN = 96,
    TCP_BUF_LEN = 240,
    RESP_BUF_LEN = 240,
  };

  int http_state;
  int req_verb;

  char request_buf[REQ_BUF_LEN];
  char *request;

  char tcp_buf[TCP_BUF_LEN];
  char resp[RESP_BUF_LEN];
  char body_buf[RESP_BUF_LEN];
  char sensor_udp_buf[RESP_BUF_LEN];

  uint8_t led_state = 0;
  uint8_t sensor_state = SENSOR_NONE;

  bool sensor_timer_periodic = FALSE;
  bool sensor_due = FALSE;
  bool close_pending = FALSE;
  bool sensor_sample_ok = FALSE;
  bool sensor_state_valid = FALSE;

  uint16_t temp_raw = 0;
  uint16_t hum_raw = 0;
  uint16_t batt_raw = 0;

  uint16_t sensor_seq = 0;
  uint32_t sensor_time = 0;
  uint16_t sensor_samples = 0;
  uint16_t sensor_udp_sent = 0;
  uint16_t sensor_udp_fail = 0;

  uint8_t radio_channel = WSN_RADIO_CHANNEL;
  uint8_t radio_tx_power = CC2420_DEF_RFPOWER;
  uint32_t radio_sample_time = 0;
  uint16_t radio_sample_seq = 0;

  uint16_t http_requests = 0;
  uint16_t command_success = 0;
  uint16_t command_errors = 0;

  char sensor_dst_str[] = "fd00:23:42:1::100";

#ifndef WSN_HTON16
#define WSN_HTON16(x) \
  ((uint16_t)((((uint16_t)(x)) << 8) | (((uint16_t)(x)) >> 8)))
#endif

  uint16_t putStr(char *b, uint16_t p, const char *s) {
    while (*s && p < RESP_BUF_LEN - 1) {
      b[p++] = *s++;
    }
    b[p] = '\0';
    return p;
  }

  uint16_t putUint(char *b, uint16_t p, uint32_t v) {
    char tmp[10];
    uint8_t i = 0;

    if (v == 0) {
      if (p < RESP_BUF_LEN - 1) {
        b[p++] = '0';
      }
      b[p] = '\0';
      return p;
    }

    while (v > 0 && i < sizeof(tmp)) {
      tmp[i++] = (char)('0' + (v % 10));
      v /= 10;
    }

    while (i > 0 && p < RESP_BUF_LEN - 1) {
      b[p++] = tmp[--i];
    }

    b[p] = '\0';
    return p;
  }

  /* Print a value given in hundredths as "X.XX" (handles negatives). */
  uint16_t putCenti(char *b, uint16_t p, int32_t centi) {
    uint32_t whole, frac;

    if (centi < 0) {
      if (p < RESP_BUF_LEN - 1) {
        b[p++] = '-';
      }
      centi = -centi;
    }
    whole = (uint32_t)centi / 100UL;
    frac  = (uint32_t)centi % 100UL;
    p = putUint(b, p, whole);
    if (p < RESP_BUF_LEN - 1) b[p++] = '.';
    if (p < RESP_BUF_LEN - 1) b[p++] = (char)('0' + (frac / 10));
    if (p < RESP_BUF_LEN - 1) b[p++] = (char)('0' + (frac % 10));
    b[p] = '\0';
    return p;
  }

  /* Sensirion SHT11 / MSP430 raw -> engineering units, in hundredths.
   *   temp[C]   = -39.6 + 0.01 * raw            (14-bit, ~3V)
   *   hum[%RH]  = -2.0468 + 0.0367*raw - 1.5955e-6*raw^2   (12-bit, linear)
   *   batt[V]   = raw / 4096 * 3.0              (ADC ref 1.5V, Vcc/2) */
  int32_t tempCenti(uint16_t raw) {
    return (int32_t)raw - 3960L;
  }
  int32_t voltCenti(uint16_t raw) {
    return ((int32_t)raw * 300L) / 4096L;
  }
  int32_t humCenti(uint16_t raw) {
    uint32_t s2 = (uint32_t)raw * (uint32_t)raw;
    /* coefficients scaled to centi-%RH; s2/6268 ~= 1.5955e-6*raw^2 * 100 */
    return -205L + (int32_t)((367UL * (uint32_t)raw) / 100UL)
                 - (int32_t)(s2 / 6268UL);
  }

  bool streq(const char *a, const char *b) {
    while (*a && *b) {
      if (*a++ != *b++) {
        return FALSE;
      }
    }
    return *a == '\0' && *b == '\0';
  }

  bool startsWith(const char *s, const char *prefix) {
    while (*prefix) {
      if (*s++ != *prefix++) {
        return FALSE;
      }
    }
    return TRUE;
  }

  uint16_t putNodePrefix(char *b, uint16_t p) {
    p = putStr(b, p, "node ");
    p = putUint(b, p, TOS_NODE_ID);
    p = putStr(b, p, ", ");
    return p;
  }

  void resetTcpListen(void) {
    close_pending = FALSE;
    http_state = S_IDLE;
    call CloseTimer.stop();
    call Tcp.bind(80);
  }

  void updateRadioState(void) {
    radio_channel = WSN_RADIO_CHANNEL;
    radio_tx_power = CC2420_DEF_RFPOWER;
    radio_sample_time = call LocalTime.get();
    radio_sample_seq = sensor_seq;
  }

  void setLedState(uint8_t value) {
    led_state = value & 0x07;

    if (led_state & 0x01) {
      call Leds.led0On();
    } else {
      call Leds.led0Off();
    }

    if (led_state & 0x02) {
      call Leds.led1On();
    } else {
      call Leds.led1Off();
    }

    if (led_state & 0x04) {
      call Leds.led2On();
    } else {
      call Leds.led2Off();
    }
  }

  void sendResponse(const char *body) {
    uint16_t p = 0;

    p = putStr(resp, p, body);

    /* Pad odd-length bodies to an even length. The BLIP TCP send path mangles
     * odd-length payloads (an odd-length response never reaches curl -> rc 56),
     * while even-length ones go through fine. UDP is unaffected. A trailing
     * newline is harmless to curl and keeps every TCP segment even-sized. */
    if (p & 1) {
      if (p < RESP_BUF_LEN - 1) {
        resp[p++] = '\n';
      }
      resp[p] = '\0';
    }

    if (call Tcp.send(resp, p) != SUCCESS) {
      call Tcp.abort();
      resetTcpListen();
      return;
    }

    close_pending = TRUE;
    call CloseTimer.startOneShot(6000);
  }

  void replyOk(const char *body) {
    command_success++;
    sendResponse(body);
  }

  void replyBad(const char *body) {
    command_errors++;
    sendResponse(body);
  }

  void replyNotFound(void) {
    command_errors++;
    sendResponse("error: unsupported\n");
  }

  void handleGetLed(void) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "led ");
    p = putUint(body_buf, p, led_state);
    p = putStr(body_buf, p, "\n");

    replyOk(body_buf);
  }

  void handleSetLed(char *path) {
    uint8_t v;

    if (path[9] < '0' || path[9] > '7' || path[10] != '\0') {
      replyBad("error: invalid set-led value\n");
      return;
    }

    v = (uint8_t)(path[9] - '0');
    setLedState(v);
    handleGetLed();
  }

  /* Build "<conv> <unit> (raw <raw>)" into body_buf at p. */
  uint16_t putReading(uint16_t p, int32_t centi, const char *unit,
                      uint16_t raw) {
    p = putCenti(body_buf, p, centi);
    p = putStr(body_buf, p, unit);
    p = putStr(body_buf, p, " (raw ");
    p = putUint(body_buf, p, raw);
    p = putStr(body_buf, p, ")");
    return p;
  }

  /* Shared formatters: write the reply into body_buf (used by both HTTP and
   * UDP). Each line shows the converted value AND the raw value. */
  void fmtTemp(void) {
    uint16_t p = putNodePrefix(body_buf, 0);
    if (!sensor_state_valid) { putStr(body_buf, p, "temp not ready\n"); return; }
    p = putStr(body_buf, p, "temp ");
    p = putReading(p, tempCenti(temp_raw), " C", temp_raw);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, sensor_seq);
    putStr(body_buf, p, "\n");
  }

  void fmtHum(void) {
    uint16_t p = putNodePrefix(body_buf, 0);
    if (!sensor_state_valid) { putStr(body_buf, p, "hum not ready\n"); return; }
    p = putStr(body_buf, p, "hum ");
    p = putReading(p, humCenti(hum_raw), " %", hum_raw);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, sensor_seq);
    putStr(body_buf, p, "\n");
  }

  void fmtVolt(void) {
    uint16_t p = putNodePrefix(body_buf, 0);
    if (!sensor_state_valid) { putStr(body_buf, p, "voltage not ready\n"); return; }
    p = putStr(body_buf, p, "batt ");
    p = putReading(p, voltCenti(batt_raw), " V", batt_raw);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, sensor_seq);
    putStr(body_buf, p, "\n");
  }

  void fmtSensor(void) {
    uint16_t p = putNodePrefix(body_buf, 0);
    if (!sensor_state_valid) { putStr(body_buf, p, "sensor not ready\n"); return; }
    p = putStr(body_buf, p, "seq ");
    p = putUint(body_buf, p, sensor_seq);
    p = putStr(body_buf, p, ", temp ");
    p = putReading(p, tempCenti(temp_raw), " C", temp_raw);
    p = putStr(body_buf, p, ", hum ");
    p = putReading(p, humCenti(hum_raw), " %", hum_raw);
    p = putStr(body_buf, p, ", batt ");
    p = putReading(p, voltCenti(batt_raw), " V", batt_raw);
    putStr(body_buf, p, "\n");
  }

  void handleTemp(void)     { fmtTemp();   replyOk(body_buf); }
  void handleHumidity(void) { fmtHum();    replyOk(body_buf); }
  void handleVoltage(void)  { fmtVolt();   replyOk(body_buf); }
  void handleSensor(void)   { fmtSensor(); replyOk(body_buf); }

  void handleChannel(void) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "channel ");
    p = putUint(body_buf, p, radio_channel);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, radio_sample_seq);
    p = putStr(body_buf, p, ", sampled_ms ");
    p = putUint(body_buf, p, radio_sample_time);
    p = putStr(body_buf, p, "\n");

    replyOk(body_buf);
  }

  void handleTxPower(void) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "tx_power ");
    p = putUint(body_buf, p, radio_tx_power);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, radio_sample_seq);
    p = putStr(body_buf, p, ", sampled_ms ");
    p = putUint(body_buf, p, radio_sample_time);
    p = putStr(body_buf, p, "\n");

    replyOk(body_buf);
  }

  void handleTime(void) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "sensor_time_ms ");
    p = putUint(body_buf, p, sensor_time);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, sensor_seq);
    p = putStr(body_buf, p, "\n");

    replyOk(body_buf);
  }

  void handleStats(void) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "requests ");
    p = putUint(body_buf, p, http_requests);
    p = putStr(body_buf, p, ", ok ");
    p = putUint(body_buf, p, command_success);
    p = putStr(body_buf, p, ", errors ");
    p = putUint(body_buf, p, command_errors);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, sensor_seq);
    p = putStr(body_buf, p, ", samples ");
    p = putUint(body_buf, p, sensor_samples);
    p = putStr(body_buf, p, ", ch ");
    p = putUint(body_buf, p, radio_channel);
    p = putStr(body_buf, p, ", pwr ");
    p = putUint(body_buf, p, radio_tx_power);
    p = putStr(body_buf, p, "\n");

    replyOk(body_buf);
  }

  void process_request(int verb, char *path) {
    http_requests++;

    if (verb != HTTP_GET) {
      replyBad("error: only GET supported\n");
    } else if (streq(path, "/get-led") || streq(path, "/read/leds")) {
      handleGetLed();
    } else if (startsWith(path, "/set-led/")) {
      handleSetLed(path);
    } else if (streq(path, "/get-temp")) {
      handleTemp();
    } else if (streq(path, "/get-humidity")) {
      handleHumidity();
    } else if (streq(path, "/get-voltage")) {
      handleVoltage();
    } else if (streq(path, "/get-sensor")) {
      handleSensor();
    } else if (streq(path, "/get-channel")) {
      handleChannel();
    } else if (streq(path, "/get-tx-power")) {
      handleTxPower();
    } else if (streq(path, "/get-time")) {
      handleTime();
    } else if (streq(path, "/get-route")) {
      replyOk("route unsupported\n");
    } else if (streq(path, "/get-stats")) {
      handleStats();
    } else if (streq(path, "/get-prr") || streq(path, "/get-etx")) {
      replyOk("unsupported\n");
    } else {
      replyNotFound();
    }
  }

  event void Boot.booted() {
    http_state = S_IDLE;
    sensor_state = SENSOR_NONE;
    sensor_timer_periodic = FALSE;
    sensor_due = FALSE;
    sensor_sample_ok = FALSE;
    sensor_state_valid = FALSE;
    close_pending = FALSE;

    setLedState(0);
    updateRadioState();

    if (TOS_NODE_ID == 1) {
      return;
    }

    call Tcp.bind(80);
    call SensorUdp.bind(SENSOR_UDP_PORT);
    call SensorTimer.startOneShot(500);
  }

  void sendSensorUdp(void) {
    struct sockaddr_in6 dst;
    uint16_t p = 0;

    if (!sensor_state_valid) {
      return;
    }

    memset(&dst, 0, sizeof(dst));
    inet_pton6(sensor_dst_str, &dst.sin6_addr);
    dst.sin6_port = WSN_HTON16(SENSOR_UDP_PORT);

    p = putStr(sensor_udp_buf, p, "node ");
    p = putUint(sensor_udp_buf, p, TOS_NODE_ID);
    p = putStr(sensor_udp_buf, p, ", seq ");
    p = putUint(sensor_udp_buf, p, sensor_seq);
    p = putStr(sensor_udp_buf, p, ", temp ");
    p = putCenti(sensor_udp_buf, p, tempCenti(temp_raw));
    p = putStr(sensor_udp_buf, p, " C (tr ");
    p = putUint(sensor_udp_buf, p, temp_raw);
    p = putStr(sensor_udp_buf, p, "), hum ");
    p = putCenti(sensor_udp_buf, p, humCenti(hum_raw));
    p = putStr(sensor_udp_buf, p, " % (hr ");
    p = putUint(sensor_udp_buf, p, hum_raw);
    p = putStr(sensor_udp_buf, p, "), batt ");
    p = putCenti(sensor_udp_buf, p, voltCenti(batt_raw));
    p = putStr(sensor_udp_buf, p, " V (br ");
    p = putUint(sensor_udp_buf, p, batt_raw);
    p = putStr(sensor_udp_buf, p, "), ch ");
    p = putUint(sensor_udp_buf, p, radio_channel);
    p = putStr(sensor_udp_buf, p, ", pwr ");
    p = putUint(sensor_udp_buf, p, radio_tx_power);
    p = putStr(sensor_udp_buf, p, "\n");

    if (call SensorUdp.sendto(&dst, sensor_udp_buf, p) == SUCCESS) {
      sensor_udp_sent++;
    } else {
      sensor_udp_fail++;
    }
  }

  void serviceSensor(void) {
    if (!sensor_due || sensor_state != SENSOR_NONE) {
      return;
    }

    sensor_due = FALSE;
    sensor_sample_ok = TRUE;
    sensor_state = SENSOR_TEMP;

    if (call TempRead.read() != SUCCESS) {
      sensor_sample_ok = FALSE;
      sensor_state = SENSOR_NONE;
      sensor_due = TRUE;
    }
  }

  event void SensorTimer.fired() {
    if (!sensor_timer_periodic) {
      sensor_timer_periodic = TRUE;
      call SensorTimer.startPeriodic(SENSOR_PERIOD_MILLI);
    }

    /* Watchdog: if the previous sample never finished (an SHT11 readDone got
     * lost, which otherwise freezes sampling and the seq number forever),
     * abandon the stuck read so this tick can start a fresh sample. */
    sensor_state = SENSOR_NONE;
    sensor_due = TRUE;
    serviceSensor();
  }

  event void TempRead.readDone(error_t result, uint16_t data) {
    if (sensor_state != SENSOR_TEMP) {
      return;
    }

    if (result == SUCCESS) {
      temp_raw = data;
    } else {
      sensor_sample_ok = FALSE;
    }

    sensor_state = SENSOR_HUM;

    if (call HumRead.read() != SUCCESS) {
      sensor_sample_ok = FALSE;
      sensor_state = SENSOR_BATT;

      if (call BattRead.read() != SUCCESS) {
        sensor_state = SENSOR_NONE;
      }
    }
  }

  event void HumRead.readDone(error_t result, uint16_t data) {
    if (sensor_state != SENSOR_HUM) {
      return;
    }

    if (result == SUCCESS) {
      hum_raw = data;
    } else {
      sensor_sample_ok = FALSE;
    }

    sensor_state = SENSOR_BATT;

    if (call BattRead.read() != SUCCESS) {
      sensor_sample_ok = FALSE;
      sensor_state = SENSOR_NONE;
    }
  }

  event void BattRead.readDone(error_t result, uint16_t data) {
    if (sensor_state != SENSOR_BATT) {
      return;
    }

    if (result == SUCCESS) {
      batt_raw = data;
    } else {
      sensor_sample_ok = FALSE;
    }

    sensor_state = SENSOR_NONE;

    if (sensor_sample_ok) {
      sensor_seq++;
      sensor_samples++;
      sensor_time = call LocalTime.get();
      sensor_state_valid = TRUE;

      updateRadioState();
      sendSensorUdp();
    }

    serviceSensor();
  }

  void sendUdpText(struct sockaddr_in6 *dst, char *body) {
    uint16_t len = 0;

    while (body[len] != '\0' && len < RESP_BUF_LEN - 1) {
      len++;
    }

    call SensorUdp.sendto(dst, body, len);
  }

  void udpGetLed(struct sockaddr_in6 *dst) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "led ");
    p = putUint(body_buf, p, led_state);
    p = putStr(body_buf, p, "\n");

    sendUdpText(dst, body_buf);
  }

  void udpGetTemp(struct sockaddr_in6 *dst)     { fmtTemp();   sendUdpText(dst, body_buf); }
  void udpGetHumidity(struct sockaddr_in6 *dst) { fmtHum();    sendUdpText(dst, body_buf); }
  void udpGetVoltage(struct sockaddr_in6 *dst)  { fmtVolt();   sendUdpText(dst, body_buf); }
  void udpGetSensor(struct sockaddr_in6 *dst)   { fmtSensor(); sendUdpText(dst, body_buf); }

  void udpGetChannel(struct sockaddr_in6 *dst) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "channel ");
    p = putUint(body_buf, p, radio_channel);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, radio_sample_seq);
    p = putStr(body_buf, p, ", sampled_ms ");
    p = putUint(body_buf, p, radio_sample_time);
    p = putStr(body_buf, p, "\n");

    sendUdpText(dst, body_buf);
  }

  void udpGetTxPower(struct sockaddr_in6 *dst) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "tx_power ");
    p = putUint(body_buf, p, radio_tx_power);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, radio_sample_seq);
    p = putStr(body_buf, p, ", sampled_ms ");
    p = putUint(body_buf, p, radio_sample_time);
    p = putStr(body_buf, p, "\n");

    sendUdpText(dst, body_buf);
  }

  void udpGetStats(struct sockaddr_in6 *dst) {
    uint16_t p = 0;

    p = putNodePrefix(body_buf, p);
    p = putStr(body_buf, p, "requests ");
    p = putUint(body_buf, p, http_requests);
    p = putStr(body_buf, p, ", ok ");
    p = putUint(body_buf, p, command_success);
    p = putStr(body_buf, p, ", errors ");
    p = putUint(body_buf, p, command_errors);
    p = putStr(body_buf, p, ", seq ");
    p = putUint(body_buf, p, sensor_seq);
    p = putStr(body_buf, p, ", samples ");
    p = putUint(body_buf, p, sensor_samples);
    p = putStr(body_buf, p, ", ch ");
    p = putUint(body_buf, p, radio_channel);
    p = putStr(body_buf, p, ", pwr ");
    p = putUint(body_buf, p, radio_tx_power);
    p = putStr(body_buf, p, "\n");

    sendUdpText(dst, body_buf);
  }

  event void SensorUdp.recvfrom(struct sockaddr_in6 *src,
                                void *payload,
                                uint16_t len,
                                struct ip6_metadata *meta) {
    char cmd[32];
    char *c = cmd;
    char *msg = payload;
    uint8_t i;
    uint16_t p = 0;

    for (i = 0; i < sizeof(cmd) - 1 && i < len; i++) {
      if (msg[i] == '\r' || msg[i] == '\n' || msg[i] == ' ') {
        break;
      }
      cmd[i] = msg[i];
    }

    cmd[i] = '\0';

    if (cmd[0] == '/') {
      c = cmd + 1;
    }

    if (streq(c, "get-led")) {
      udpGetLed(src);
    } else if (startsWith(c, "set-led/") &&
               c[8] >= '0' && c[8] <= '7' && c[9] == '\0') {
      setLedState((uint8_t)(c[8] - '0'));
      udpGetLed(src);
    } else if (streq(c, "get-temp")) {
      udpGetTemp(src);
    } else if (streq(c, "get-humidity")) {
      udpGetHumidity(src);
    } else if (streq(c, "get-voltage")) {
      udpGetVoltage(src);
    } else if (streq(c, "get-sensor")) {
      udpGetSensor(src);
    } else if (streq(c, "get-channel")) {
      udpGetChannel(src);
    } else if (streq(c, "get-tx-power")) {
      udpGetTxPower(src);
    } else if (streq(c, "get-time")) {
      p = putNodePrefix(body_buf, p);
      p = putStr(body_buf, p, "sensor_time_ms ");
      p = putUint(body_buf, p, sensor_time);
      p = putStr(body_buf, p, ", seq ");
      p = putUint(body_buf, p, sensor_seq);
      p = putStr(body_buf, p, "\n");
      sendUdpText(src, body_buf);
    } else if (streq(c, "get-stats")) {
      udpGetStats(src);
    } else {
      p = putNodePrefix(body_buf, p);
      p = putStr(body_buf, p, "error unsupported\n");
      sendUdpText(src, body_buf);
    }
  }

  event bool Tcp.accept(struct sockaddr_in6 *from,
                        void **tx_buf,
                        int *tx_buf_len) {
    if (http_state != S_IDLE) {
      return FALSE;
    }

    http_state = S_CONNECTED;
    close_pending = FALSE;

    request = request_buf;
    request_buf[0] = '\0';

    *tx_buf = tcp_buf;
    *tx_buf_len = TCP_BUF_LEN;

    call CloseTimer.startOneShot(4000);

    return TRUE;
  }

  event void Tcp.connectDone(error_t e) {
  }

  event void Tcp.recv(void *payload, uint16_t len) {
    char *msg = payload;

    switch (http_state) {
    case S_CONNECTED:
      call Leds.led2Toggle();

      request = request_buf;
      request_buf[0] = '\0';

      if (len < 3) {
        call Tcp.abort();
        resetTcpListen();
        return;
      }

      if (msg[0] == 'G' && msg[1] == 'E' && msg[2] == 'T') {
        req_verb = HTTP_GET;
        msg += 3;
        len -= 3;
      } else {
        req_verb = HTTP_OTHER;
      }

      http_state = S_REQUEST_PRE;

    case S_REQUEST_PRE:
      while (len > 0 && *msg == ' ') {
        len--;
        msg++;
      }

      if (len == 0) {
        break;
      }

      http_state = S_REQUEST;

    case S_REQUEST:
      while (len > 0 &&
             *msg != ' ' &&
             *msg != '\r' &&
             *msg != '\n') {
        if (request < request_buf + REQ_BUF_LEN - 1) {
          *request++ = *msg;
        }
        msg++;
        len--;
      }

      if (len == 0) {
        break;
      }

      *request = '\0';
      http_state = S_HEADER;

      call CloseTimer.stop();
      process_request(req_verb, request_buf);
      return;

    case S_HEADER:
      break;

    default:
      break;
    }
  }

  event void Tcp.acked() {
    if (!close_pending) {
      return;
    }

    close_pending = FALSE;

    if (call Tcp.close() != SUCCESS) {
      call Tcp.abort();
      resetTcpListen();
      return;
    }

    call CloseTimer.startOneShot(1500);
  }

  event void Tcp.closed(error_t e) {
    resetTcpListen();
  }

  event void CloseTimer.fired() {
    close_pending = FALSE;

    if (http_state != S_IDLE) {
      call Tcp.abort();
      resetTcpListen();
    }
  }
}