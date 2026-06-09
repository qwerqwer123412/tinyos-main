#ifndef SIMPLE_WSN_H
#define SIMPLE_WSN_H


enum {
  AM_SIMPLE_WSN_MSG = 6,
  BASE_STATION_ID = 1,
  SEND_PERIOD_MILLI = 2000,
};

typedef nx_struct simple_wsn_msg {
  nx_uint16_t sender;
  nx_uint16_t seq;
  nx_uint32_t mote_time;
  nx_uint16_t temperature;
  nx_uint16_t humidity;
  nx_uint16_t battery;
} simple_wsn_msg_t;

#endif