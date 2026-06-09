#ifndef KPRJ_H
#define KPRJ_H

enum {
  AM_KPRRMSG = 0x93,
  TOTAL_PKTS = 100,
};

typedef nx_struct kprr_msg {
  nx_uint16_t src;
  nx_uint16_t seq;
  nx_uint16_t period_ms;
  nx_uint8_t  channel;
  nx_uint8_t  total_pkts;
} kprr_msg_t;

#endif