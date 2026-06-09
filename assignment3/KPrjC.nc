#include "Timer.h"
#include "KPrj.h"
#include "printf.h"

module KPrjC {
  uses interface Boot;
  uses interface SplitControl as AMControl;

  uses interface AMSend;
  uses interface Receive;
  uses interface Packet;

  uses interface Timer<TMilli> as SendTimer;
  uses interface Timer<TMilli> as FinishTimer;
  uses interface Timer<TMilli> as LedTimer;

  uses interface CC2420Packet;
  uses interface Leds;
}
implementation {

#ifndef PERIOD_MS
#define PERIOD_MS 1000
#endif

#ifndef CC2420_DEF_CHANNEL
#define CC2420_DEF_CHANNEL 26
#endif

  enum {
    LED_BLINK_MS = 80
  };

  message_t pkt;
  bool busy = FALSE;

  uint16_t tx_seq = 0;

  bool measuring = FALSE;
  bool done = FALSE;

  uint16_t first_seq = 0;
  uint16_t rx_count = 0;
  bool seen[TOTAL_PKTS];

  bool isSensor() {
    return TOS_NODE_ID == 2 || TOS_NODE_ID == 4 || TOS_NODE_ID == 6;
  }

  bool isBase() {
    return TOS_NODE_ID == 1 || TOS_NODE_ID == 3 || TOS_NODE_ID == 5;
  }

  uint16_t expectedSrc() {
    if (TOS_NODE_ID == 1) return 2;
    if (TOS_NODE_ID == 3) return 4;
    if (TOS_NODE_ID == 5) return 6;
    return 0xffff;
  }

  uint8_t groupLed() {
    /*
     * group1: node1, node2 -> Red   -> led0
     * group2: node3, node4 -> Green -> led1
     * group3: node5, node6 -> Blue  -> led2
     */
    if (TOS_NODE_ID == 1 || TOS_NODE_ID == 2) return 0;
    if (TOS_NODE_ID == 3 || TOS_NODE_ID == 4) return 1;
    if (TOS_NODE_ID == 5 || TOS_NODE_ID == 6) return 2;
    return 0;
  }

  void ledsOff() {
    call Leds.led0Off();
    call Leds.led1Off();
    call Leds.led2Off();
  }

  void blinkGroupLed() {
    uint8_t led = groupLed();

    ledsOff();

    if (led == 0) {
      call Leds.led0On();
    }
    else if (led == 1) {
      call Leds.led1On();
    }
    else {
      call Leds.led2On();
    }

    call LedTimer.startOneShot(LED_BLINK_MS);
  }

  void clearSeen() {
    uint8_t i;
    for (i = 0; i < TOTAL_PKTS; i++) {
      seen[i] = FALSE;
    }
  }

  event void Boot.booted() {
    ledsOff();
    call AMControl.start();
  }

  event void AMControl.startDone(error_t err) {
    if (err != SUCCESS) {
      call AMControl.start();
      return;
    }

    blinkGroupLed();

    if (isSensor()) {
      printf("BOOT node=%u role=sensor channel=%u period_ms=%u\n",
             TOS_NODE_ID,
             CC2420_DEF_CHANNEL,
             PERIOD_MS);
      printfflush();

      call SendTimer.startPeriodic(PERIOD_MS);
    }
    else if (isBase()) {
      printf("BOOT node=%u role=base channel=%u period_ms=%u expected_src=%u\n",
             TOS_NODE_ID,
             CC2420_DEF_CHANNEL,
             PERIOD_MS,
             expectedSrc());
      printfflush();
    }
    else {
      printf("BOOT node=%u role=unused channel=%u\n",
             TOS_NODE_ID,
             CC2420_DEF_CHANNEL);
      printfflush();
    }
  }

  event void AMControl.stopDone(error_t err) {}

  event void LedTimer.fired() {
    ledsOff();
  }

  event void SendTimer.fired() {
    kprr_msg_t *m;

    if (!isSensor()) return;
    if (busy) return;

    m = (kprr_msg_t *) call Packet.getPayload(&pkt, sizeof(kprr_msg_t));
    if (m == NULL) return;

    m->src = TOS_NODE_ID;
    m->seq = tx_seq;
    m->period_ms = PERIOD_MS;
    m->channel = CC2420_DEF_CHANNEL;
    m->total_pkts = TOTAL_PKTS;

    if (call AMSend.send(AM_BROADCAST_ADDR,
                         &pkt,
                         sizeof(kprr_msg_t)) == SUCCESS) {
      busy = TRUE;
      tx_seq++;

      /* packet transmit blink */
      blinkGroupLed();
    }
  }

  event void AMSend.sendDone(message_t *msg, error_t err) {
    if (msg == &pkt) {
      busy = FALSE;
    }
  }

  event message_t *Receive.receive(message_t *msg,
                                   void *payload,
                                   uint8_t len) {
    kprr_msg_t *m;
    int16_t idx;
    int8_t rssi_raw;
    int16_t rssi_dbm;
    uint8_t lqi;
    uint32_t window_ms;

    if (!isBase()) return msg;
    if (done) return msg;
    if (len != sizeof(kprr_msg_t)) return msg;

    m = (kprr_msg_t *) payload;

    if (m->src != expectedSrc()) {
      return msg;
    }

    if (!measuring) {
      measuring = TRUE;
      first_seq = m->seq;
      rx_count = 0;
      clearSeen();

      window_ms = (uint32_t)PERIOD_MS * 99 + (uint32_t)PERIOD_MS / 4;
      call FinishTimer.startOneShot(window_ms);

      printf("MEASURE_START base=%u src=%u first_seq=%u total=%u window_ms=%lu\n",
             TOS_NODE_ID,
             m->src,
             first_seq,
             TOTAL_PKTS,
             window_ms);
      printfflush();
    }

    idx = (int16_t)(m->seq - first_seq);

    if (idx >= 0 && idx < TOTAL_PKTS) {
      if (!seen[idx]) {
        seen[idx] = TRUE;
        rx_count++;
      }

      /* packet receive blink */
      blinkGroupLed();

      rssi_raw = call CC2420Packet.getRssi(msg);
      rssi_dbm = (int16_t)rssi_raw - 45;
      lqi = call CC2420Packet.getLqi(msg);

      printf("RX base=%u src=%u seq=%u idx=%d rssi_raw=%d rssi_dbm=%d lqi=%u rx_count=%u/%u\n",
             TOS_NODE_ID,
             m->src,
             m->seq,
             idx,
             rssi_raw,
             rssi_dbm,
             lqi,
             rx_count,
             TOTAL_PKTS);
      printfflush();
    }

    return msg;
  }

  event void FinishTimer.fired() {
    uint16_t prr_x100;

    done = TRUE;
    measuring = FALSE;

    prr_x100 = ((uint32_t)rx_count * 10000) / TOTAL_PKTS;

    printf("MEASURE_DONE base=%u expected=%u received=%u prr=%u.%02u%% first_seq=%u last_seq=%u\n",
           TOS_NODE_ID,
           TOTAL_PKTS,
           rx_count,
           prr_x100 / 100,
           prr_x100 % 100,
           first_seq,
           first_seq + TOTAL_PKTS - 1);
    printfflush();
  }
}