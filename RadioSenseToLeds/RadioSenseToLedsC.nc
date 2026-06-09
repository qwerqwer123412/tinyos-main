#include "Timer.h"
#include "RadioSenseToLeds.h"
#include "AM.h"

module RadioSenseToLedsC @safe() {
  uses {
    interface Leds;
    interface Boot;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as MilliTimer;
    interface Packet;
    interface SplitControl as RadioControl;
  }
}

implementation {

  message_t packet;
  bool locked = FALSE;
  uint16_t counter = 0;

  event void Boot.booted() {
    call RadioControl.start();
  }

  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      if (TOS_NODE_ID == 1) {
        call MilliTimer.startPeriodic(500);
      }
      else if (TOS_NODE_ID == 2) {
        call MilliTimer.startPeriodic(1000);
      }
    }
  }

  event void RadioControl.stopDone(error_t err) {}

  event void MilliTimer.fired() {
    radio_sense_msg_t* rsm;

    if (locked) {
      return;
    }

    rsm = (radio_sense_msg_t*) call Packet.getPayload(&packet,
            sizeof(radio_sense_msg_t));
    if (rsm == NULL) {
      return;
    }

    rsm->sender = TOS_NODE_ID;
    rsm->counter = counter++;

    if (call AMSend.send(AM_BROADCAST_ADDR,
                         &packet,
                         sizeof(radio_sense_msg_t)) == SUCCESS) {
      locked = TRUE;
      call Leds.led0Toggle();   // red LED: 송신 시 토글
    }
  }

  event message_t* Receive.receive(message_t* bufPtr,
                                   void* payload,
                                   uint8_t len) {
    if (len != sizeof(radio_sense_msg_t)) {
      return bufPtr;
    }
    else {
      radio_sense_msg_t* rsm = (radio_sense_msg_t*) payload;

      if (rsm->sender != TOS_NODE_ID) {
        if (TOS_NODE_ID == 1) {
          call Leds.led1Toggle();   // Node 1: green LED
        }
        else if (TOS_NODE_ID == 2) {
          call Leds.led2Toggle();   // Node 2: blue LED
        }
      }

      return bufPtr;
    }
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    if (&packet == bufPtr) {
      locked = FALSE;
    }
  }
}