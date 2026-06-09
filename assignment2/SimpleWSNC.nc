#include "Timer.h"
#include "AM.h"
#include "SimpleWSN.h"

module SimpleWSNC @safe() {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;

    interface AMSend;
    interface Receive;
    interface Packet;

    interface Timer<TMilli> as MilliTimer;
    interface Leds;
    interface LocalTime<TMilli>;

    interface Read<uint16_t> as TempRead;
    interface Read<uint16_t> as HumRead;
    interface Read<uint16_t> as BattRead;
  }
}
implementation {

  message_t packet;
  bool locked = FALSE;
  uint16_t seqno = 0;

  uint16_t temp_data = 0;
  uint16_t hum_data = 0;
  uint16_t batt_data = 0;

  void blinkByNode(uint16_t nodeid) {
    if (nodeid == 2) {
      call Leds.led0Toggle();   // red
    }
    else if (nodeid == 3) {
      call Leds.led1Toggle();   // green
    }
    else if (nodeid == 4) {
      call Leds.led2Toggle();   // blue
    }
  }

  event void Boot.booted() {
    call RadioControl.start();
  }

  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      if (TOS_NODE_ID == 2 || TOS_NODE_ID == 3 || TOS_NODE_ID == 4) {
        call MilliTimer.startPeriodic(SEND_PERIOD_MILLI);
      }
    }
    else {
      call RadioControl.start();
    }
  }

  event void RadioControl.stopDone(error_t err) {}

  event void MilliTimer.fired() {
    if (locked) {
      return;
    }

    if (TOS_NODE_ID == 2 || TOS_NODE_ID == 3 || TOS_NODE_ID == 4) {
      call TempRead.read();
    }
  }

  event void TempRead.readDone(error_t result, uint16_t data) {
    if (result == SUCCESS) {
      temp_data = data;
    } else {
      temp_data = 0xFFFF;
    }
    call HumRead.read();
  }

  event void HumRead.readDone(error_t result, uint16_t data) {
    if (result == SUCCESS) {
      hum_data = data;
    } else {
      hum_data = 0xFFFF;
    }
    call BattRead.read();
  }

  event void BattRead.readDone(error_t result, uint16_t data) {
    simple_wsn_msg_t *msg;

    if (result == SUCCESS) {
      batt_data = data;
    } else {
      batt_data = 0xFFFF;
    }

    msg = (simple_wsn_msg_t *)call Packet.getPayload(&packet,
                                                     sizeof(simple_wsn_msg_t));
    if (msg == NULL) {
      return;
    }

    msg->sender      = TOS_NODE_ID;
    msg->seq         = seqno++;
    msg->mote_time   = call LocalTime.get();
    msg->temperature = temp_data;
    msg->humidity    = hum_data;
    msg->battery     = batt_data;

    if (call AMSend.send(BASE_STATION_ID,
                         &packet,
                         sizeof(simple_wsn_msg_t)) == SUCCESS) {
      locked = TRUE;
      blinkByNode(TOS_NODE_ID);
    }
  }

  event void AMSend.sendDone(message_t *bufPtr, error_t error) {
    if (&packet == bufPtr) {
      locked = FALSE;
    }
  }

  event message_t* Receive.receive(message_t *bufPtr,
                                   void *payload,
                                   uint8_t len) {
    simple_wsn_msg_t *msg;

    if (len != sizeof(simple_wsn_msg_t)) {
      return bufPtr;
    }

    msg = (simple_wsn_msg_t *)payload;

    if (TOS_NODE_ID == 1) {
      blinkByNode(msg->sender);
    }

    return bufPtr;
  }
}

//TinyOS의 Read.read()는 비동기라서 순서대로 이어야 합니다.

//지금 구조는:

//TempRead.read()
//TempRead.readDone()
//HumRead.read()
//HumRead.readDone()
//BattRead.read()
//BattRead.readDone()
//패킷 생성 후 AMSend.send(BASE_STATION_ID, ...)