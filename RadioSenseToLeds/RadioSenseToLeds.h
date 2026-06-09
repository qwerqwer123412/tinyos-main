#ifndef RADIO_SENSE_TO_LEDS_H
#define RADIO_SENSE_TO_LEDS_H

enum {
  AM_RADIO_SENSE_MSG = 6,
};

typedef nx_struct radio_sense_msg {
  nx_uint16_t sender;
  nx_uint16_t counter;
} radio_sense_msg_t;

#endif