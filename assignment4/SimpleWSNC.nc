#include "Timer.h"
#include "AM.h"
#include "SimpleWSN.h"

module SimpleWSNC @safe() {
  uses {
    interface Boot;

    interface SplitControl as RadioControl;
    interface SplitControl as SerialControl;

    interface AMSend as RadioSend;
    interface Receive as RadioReceive;
    interface Packet as RadioPacket;

    interface AMSend as SerialSend;
    interface Receive as SerialReceive;
    interface Packet as SerialPacket;

    interface Timer<TMilli> as MilliTimer;
    interface Timer<TMilli> as ReplyTimer;

    interface Leds;
    interface LocalTime<TMilli>;

    interface Read<uint16_t> as TempRead;
    interface Read<uint16_t> as HumRead;
    interface Read<uint16_t> as BattRead;
  }
}
implementation {
  enum {
    READ_NONE = 0,
    READ_PERIODIC = 1,
    READ_CMD_TEMP = 2,
    READ_CMD_VOLTAGE = 3,
  };

  message_t radioPacket;
  message_t serialPacket;

  bool radioLocked = FALSE;
  bool serialLocked = FALSE;

  uint16_t seqno = 0;

  uint16_t temp_data = 0;
  uint16_t hum_data = 0;
  uint16_t batt_data = 0;

  uint8_t led_state = 0;
  uint8_t readMode = READ_NONE;
  bool readCmdWasBroadcast = FALSE;

  bool pendingReplyValid = FALSE;
  simple_wsn_msg_t pendingReply;

  bool isSensorNode() {
    return TOS_NODE_ID == 2 ||
           TOS_NODE_ID == 3 ||
           TOS_NODE_ID == 4 ||
           TOS_NODE_ID == 5;
  }

  bool isTarget(simple_wsn_msg_t *msg) {
    return msg->target == TOS_NODE_ID || msg->target == NODE_BROADCAST;
  }

  void setLedsByValue(uint8_t value) {
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

  void blinkBaseByNode(uint16_t nodeid) {
    if (nodeid == 2) {
      call Leds.led0Toggle();
    }
    else if (nodeid == 3) {
      call Leds.led1Toggle();
    }
    else if (nodeid == 4 || nodeid == 5) {
      call Leds.led2Toggle();
    }
  }

  void copyMsg(simple_wsn_msg_t *dst, simple_wsn_msg_t *src) {
    dst->msg_type = src->msg_type;
    dst->cmd = src->cmd;
    dst->sender = src->sender;
    dst->target = src->target;
    dst->seq = src->seq;
    dst->value = src->value;
    dst->status = src->status;
    dst->mote_time = src->mote_time;
    dst->temperature = src->temperature;
    dst->humidity = src->humidity;
    dst->battery = src->battery;
    dst->led = src->led;
    dst->channel = src->channel;
    dst->tx_power = src->tx_power;
  }

  void fillCommon(simple_wsn_msg_t *msg,
                  uint8_t msg_type,
                  uint8_t cmd,
                  uint16_t target,
                  uint16_t value,
                  uint8_t status) {
    msg->msg_type = msg_type;
    msg->cmd = cmd;
    msg->sender = TOS_NODE_ID;
    msg->target = target;
    msg->seq = seqno++;
    msg->value = value;
    msg->status = status;
    msg->mote_time = call LocalTime.get();

    msg->temperature = temp_data;
    msg->humidity = hum_data;
    msg->battery = batt_data;

    msg->led = led_state;
    msg->channel = WSN_RADIO_CHANNEL;
    msg->tx_power = WSN_RADIO_TX_POWER;
  }

  bool sendRadio(simple_wsn_msg_t *src, am_addr_t dest) {
    simple_wsn_msg_t *msg;

    if (radioLocked) {
      return FALSE;
    }

    msg = (simple_wsn_msg_t *)call RadioPacket.getPayload(
        &radioPacket, sizeof(simple_wsn_msg_t));

    if (msg == NULL) {
      return FALSE;
    }

    copyMsg(msg, src);

    if (call RadioSend.send(dest,
                            &radioPacket,
                            sizeof(simple_wsn_msg_t)) == SUCCESS) {
      radioLocked = TRUE;
      return TRUE;
    }

    return FALSE;
  }

  bool sendSerial(simple_wsn_msg_t *src) {
    simple_wsn_msg_t *msg;

    if (serialLocked) {
      return FALSE;
    }

    msg = (simple_wsn_msg_t *)call SerialPacket.getPayload(
        &serialPacket, sizeof(simple_wsn_msg_t));

    if (msg == NULL) {
      return FALSE;
    }

    copyMsg(msg, src);

    if (call SerialSend.send(AM_BROADCAST_ADDR,
                             &serialPacket,
                             sizeof(simple_wsn_msg_t)) == SUCCESS) {
      serialLocked = TRUE;
      return TRUE;
    }

    return FALSE;
  }

  void sendPeriodicData() {
    simple_wsn_msg_t msg;

    fillCommon(&msg,
               TYPE_DATA,
               CMD_NONE,
               BASE_STATION_ID,
               0,
               SUCCESS);

    sendRadio(&msg, BASE_STATION_ID);
  }

  void scheduleReply(simple_wsn_msg_t *msg, bool broadcastCmd) {
    copyMsg(&pendingReply, msg);
    pendingReplyValid = TRUE;

    if (broadcastCmd) {
      call ReplyTimer.startOneShot(50 + (TOS_NODE_ID * 80));
    } else {
      call ReplyTimer.startOneShot(20);
    }
  }

  void makeAndScheduleReply(uint8_t cmd,
                            uint16_t value,
                            uint8_t status,
                            bool broadcastCmd) {
    simple_wsn_msg_t msg;

    fillCommon(&msg,
               TYPE_RESP,
               cmd,
               BASE_STATION_ID,
               value,
               status);

    scheduleReply(&msg, broadcastCmd);
  }

  void handleCommand(simple_wsn_msg_t *cmdMsg) {
    bool broadcastCmd;

    if (!isSensorNode()) {
      return;
    }

    if (!isTarget(cmdMsg)) {
      return;
    }

    broadcastCmd = (cmdMsg->target == NODE_BROADCAST);

    if (cmdMsg->cmd == CMD_GET_LED) {
      makeAndScheduleReply(CMD_GET_LED, led_state, SUCCESS, broadcastCmd);
    }
    else if (cmdMsg->cmd == CMD_SET_LED) {
      setLedsByValue((uint8_t)cmdMsg->value);
      makeAndScheduleReply(CMD_SET_LED, led_state, SUCCESS, broadcastCmd);
    }
    else if (cmdMsg->cmd == CMD_GET_CHANNEL) {
      makeAndScheduleReply(CMD_GET_CHANNEL,
                           WSN_RADIO_CHANNEL,
                           SUCCESS,
                           broadcastCmd);
    }
    else if (cmdMsg->cmd == CMD_GET_TX_POWER) {
      makeAndScheduleReply(CMD_GET_TX_POWER,
                           WSN_RADIO_TX_POWER,
                           SUCCESS,
                           broadcastCmd);
    }
    else if (cmdMsg->cmd == CMD_GET_TEMP) {
      if (readMode != READ_NONE) {
        makeAndScheduleReply(CMD_GET_TEMP, 0, EBUSY, broadcastCmd);
        return;
      }

      readMode = READ_CMD_TEMP;
      readCmdWasBroadcast = broadcastCmd;

      if (call TempRead.read() != SUCCESS) {
        readMode = READ_NONE;
        makeAndScheduleReply(CMD_GET_TEMP, 0, FAIL, broadcastCmd);
      }
    }
    else if (cmdMsg->cmd == CMD_GET_VOLTAGE) {
      if (readMode != READ_NONE) {
        makeAndScheduleReply(CMD_GET_VOLTAGE, 0, EBUSY, broadcastCmd);
        return;
      }

      readMode = READ_CMD_VOLTAGE;
      readCmdWasBroadcast = broadcastCmd;

      if (call BattRead.read() != SUCCESS) {
        readMode = READ_NONE;
        makeAndScheduleReply(CMD_GET_VOLTAGE, 0, FAIL, broadcastCmd);
      }
    }
  }

  event void Boot.booted() {
    setLedsByValue(0);
    call RadioControl.start();
  }

  event void RadioControl.startDone(error_t err) {
    if (err == SUCCESS) {
      if (TOS_NODE_ID == BASE_STATION_ID) {
        call SerialControl.start();
      }
      else if (isSensorNode()) {
        call MilliTimer.startPeriodic(SEND_PERIOD_MILLI);
      }
    }
    else {
      call RadioControl.start();
    }
  }

  event void RadioControl.stopDone(error_t err) {}

  event void SerialControl.startDone(error_t err) {
    if (err != SUCCESS) {
      call SerialControl.start();
    }
  }

  event void SerialControl.stopDone(error_t err) {}

  event void MilliTimer.fired() {
    if (!isSensorNode()) {
      return;
    }

    if (readMode != READ_NONE) {
      return;
    }

    readMode = READ_PERIODIC;

    if (call TempRead.read() != SUCCESS) {
      readMode = READ_NONE;
    }
  }

  event void TempRead.readDone(error_t result, uint16_t data) {
    if (result == SUCCESS) {
      temp_data = data;
    }
    else {
      temp_data = 0xFFFF;
    }

    if (readMode == READ_PERIODIC) {
      if (call HumRead.read() != SUCCESS) {
        readMode = READ_NONE;
      }
    }
    else if (readMode == READ_CMD_TEMP) {
      readMode = READ_NONE;
      makeAndScheduleReply(CMD_GET_TEMP,
                           temp_data,
                           result,
                           readCmdWasBroadcast);
    }
  }

  event void HumRead.readDone(error_t result, uint16_t data) {
    if (result == SUCCESS) {
      hum_data = data;
    }
    else {
      hum_data = 0xFFFF;
    }

    if (readMode == READ_PERIODIC) {
      if (call BattRead.read() != SUCCESS) {
        readMode = READ_NONE;
      }
    }
  }

  event void BattRead.readDone(error_t result, uint16_t data) {
    if (result == SUCCESS) {
      batt_data = data;
    }
    else {
      batt_data = 0xFFFF;
    }

    if (readMode == READ_PERIODIC) {
      readMode = READ_NONE;
      sendPeriodicData();
    }
    else if (readMode == READ_CMD_VOLTAGE) {
      readMode = READ_NONE;
      makeAndScheduleReply(CMD_GET_VOLTAGE,
                           batt_data,
                           result,
                           readCmdWasBroadcast);
    }
  }

  event void ReplyTimer.fired() {
    if (!pendingReplyValid) {
      return;
    }

    if (sendRadio(&pendingReply, BASE_STATION_ID)) {
      pendingReplyValid = FALSE;
    }
    else {
      call ReplyTimer.startOneShot(50);
    }
  }

  event message_t* RadioReceive.receive(message_t *bufPtr,
                                        void *payload,
                                        uint8_t len) {
    simple_wsn_msg_t *msg;

    if (len != sizeof(simple_wsn_msg_t)) {
      return bufPtr;
    }

    msg = (simple_wsn_msg_t *)payload;

    if (TOS_NODE_ID == BASE_STATION_ID) {
      blinkBaseByNode(msg->sender);
      sendSerial(msg);
    }
    else if (isSensorNode()) {
      if (msg->msg_type == TYPE_CMD) {
        handleCommand(msg);
      }
    }

    return bufPtr;
  }

  event message_t* SerialReceive.receive(message_t *bufPtr,
                                         void *payload,
                                         uint8_t len) {
    simple_wsn_msg_t *msg;
    simple_wsn_msg_t out;
    am_addr_t dest;

    if (TOS_NODE_ID != BASE_STATION_ID) {
      return bufPtr;
    }

    if (len != sizeof(simple_wsn_msg_t)) {
      return bufPtr;
    }

    msg = (simple_wsn_msg_t *)payload;

    if (msg->msg_type != TYPE_CMD) {
      return bufPtr;
    }

    copyMsg(&out, msg);
    out.sender = BASE_STATION_ID;
    out.seq = seqno++;
    out.mote_time = call LocalTime.get();

    if (out.target == NODE_BROADCAST) {
      dest = AM_BROADCAST_ADDR;
    }
    else {
      dest = out.target;
    }

    sendRadio(&out, dest);

    return bufPtr;
  }

  event void RadioSend.sendDone(message_t *bufPtr, error_t error) {
    if (&radioPacket == bufPtr) {
      radioLocked = FALSE;
    }
  }

  event void SerialSend.sendDone(message_t *bufPtr, error_t error) {
    if (&serialPacket == bufPtr) {
      serialLocked = FALSE;
    }
  }
}