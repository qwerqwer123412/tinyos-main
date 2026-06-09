#include <lib6lowpan/6lowpan.h>

/*
 * TCP Echo end-node.
 *
 * Install this on a normal mote, for example node id 2.
 * The Base Station should run PppRouterC and only route packets.
 */
configuration TCPEchoC {
}
implementation {
  components MainC, LedsC;
  components TCPEchoP;

  TCPEchoP.Boot -> MainC;
  TCPEchoP.Leds -> LedsC;

  components IPStackC;
  TCPEchoP.RadioControl -> IPStackC;

  components new TcpSocketC() as TcpEcho;
  TCPEchoP.TcpEcho -> TcpEcho;

  /*
   * Address becomes IN6_PREFIX::TOS_NODE_ID.
   * Example with -DIN6_PREFIX=\"fec0::\" and node id 2:
   *   fec0::2
   */
  components StaticIPAddressTosIdC;
}
