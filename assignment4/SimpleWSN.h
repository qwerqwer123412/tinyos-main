#ifndef SIMPLE_WSN_H
#define SIMPLE_WSN_H

#ifndef WSN_RADIO_CHANNEL
#define WSN_RADIO_CHANNEL 26
#endif

#ifndef WSN_RADIO_TX_POWER
#define WSN_RADIO_TX_POWER 31
#endif

enum {
  AM_SIMPLE_WSN_MSG = 6,

  BASE_STATION_ID = 1,
  NODE_BROADCAST = 0xFFFF,

  SEND_PERIOD_MILLI = 2000,

  TYPE_DATA = 1,
  TYPE_CMD  = 2,
  TYPE_RESP = 3,

  CMD_NONE         = 0,
  CMD_GET_LED      = 1,
  CMD_SET_LED      = 2,
  CMD_GET_VOLTAGE  = 3,
  CMD_GET_TEMP     = 4,
  CMD_GET_CHANNEL  = 5,
  CMD_GET_TX_POWER = 6,
};

typedef nx_struct simple_wsn_msg {
  nx_uint8_t  msg_type;
  nx_uint8_t  cmd;

  nx_uint16_t sender;
  nx_uint16_t target;
  nx_uint16_t seq;

  nx_uint16_t value;
  nx_uint8_t  status;

  nx_uint32_t mote_time;

  nx_uint16_t temperature;
  nx_uint16_t humidity;
  nx_uint16_t battery;

  nx_uint8_t led;
  nx_uint8_t channel;
  nx_uint8_t tx_power;
} simple_wsn_msg_t;

#endif