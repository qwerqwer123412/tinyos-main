#include <IPDispatch.h>
#include <lib6lowpan/lib6lowpan.h>
#include <lib6lowpan/ip.h>

#ifndef TCP_ECHO_PORT
#define TCP_ECHO_PORT 7
#endif

/*
 * Minimal TCP echo server for BLIP.
 *
 * PC ----PPP---- BaseStation(PppRouter) ----6LoWPAN/RPL---- this mote
 *
 * Test:
 *   printf 'hello\n' | nc -6 -v -w 10 fec0::2 7
 */
module TCPEchoP {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    interface Tcp as TcpEcho;
    interface Leds;
  }
}
implementation {
  enum {
    TCP_BUF_LEN = 128,
  };

  bool connected = FALSE;
  char tcp_buf[TCP_BUF_LEN];

  void bindEcho() {
    error_t e = call TcpEcho.bind(TCP_ECHO_PORT);
    if (e != SUCCESS) {
      call Leds.led2Toggle();
    }
  }

  event void Boot.booted() {
    connected = FALSE;
    call RadioControl.start();
  }

  event void RadioControl.startDone(error_t e) {
    if (e != SUCCESS) {
      call RadioControl.start();
      return;
    }

    bindEcho();
    call Leds.led0On();
  }

  event void RadioControl.stopDone(error_t e) {
  }

  event bool TcpEcho.accept(struct sockaddr_in6 *from,
                            void **tx_buf,
                            int *tx_buf_len) {
    if (connected) {
      return FALSE;
    }

    connected = TRUE;
    *tx_buf = tcp_buf;
    *tx_buf_len = TCP_BUF_LEN;

    call Leds.led1Toggle();
    return TRUE;
  }

  event void TcpEcho.connectDone(error_t e) {
  }

  event void TcpEcho.recv(void *payload, uint16_t len) {
    if (len > TCP_BUF_LEN) {
      len = TCP_BUF_LEN;
    }

    if (call TcpEcho.send(payload, len) != SUCCESS) {
      call Leds.led2Toggle();
    }
  }

  event void TcpEcho.acked() {
  }

  event void TcpEcho.closed(error_t e) {
    connected = FALSE;
    call Leds.led1Toggle();
    bindEcho();
  }
}
